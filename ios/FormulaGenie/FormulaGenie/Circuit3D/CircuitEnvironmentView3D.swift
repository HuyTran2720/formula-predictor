//
//  CircuitEnvironmentView3D.swift
//  FormulaGenie
//
//  Assembles the separate pieces `TrackMeshFactory` builds (terrain, runoff,
//  track surface, kerbs, pit lane) from the real GeoJSON-derived centerline
//  into one scene, and provides the same free, Sims-style camera as
//  `TrackMapView3D` - unrestricted pan/orbit/rotate, with only the camera's
//  *position* ever stopped from crossing the ground plane, never its
//  rotation. Buildings, grandstands, vegetation, and barriers are the next
//  phase, once this base environment is confirmed working.
//

import SwiftUI
import SceneKit

struct CircuitEnvironmentView3D: UIViewRepresentable {
    let rows: [StandingRow]
    let selectedCode: String?
    let tickInterval: Double

    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.scene = context.coordinator.scene
        scnView.backgroundColor = UIColor(red: 0.55, green: 0.75, blue: 0.92, alpha: 1)
        context.coordinator.setupSceneIfNeeded()
        scnView.pointOfView = context.coordinator.cameraNode
        context.coordinator.attachGestures(to: scnView)
        return scnView
    }

    func updateUIView(_ scnView: SCNView, context: Context) {
        context.coordinator.update(rows: rows, selectedCode: selectedCode, tickInterval: tickInterval)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        let scene = SCNScene()
        private var didSetupScene = false
        private(set) var cameraNode: SCNNode?
        private var cameraController: SCNCameraController?
        /// The ground's own lowest point, plus a small buffer - not a fixed
        /// 0, since this circuit's terrain/track sit at a real, GeoJSON-
        /// derived elevation rather than being centered on world Y=0.
        private var minCameraHeight: Float = 2
        /// The larger of the circuit's real x/z extents, in meters -
        /// computed from the actual samples once they're built, so the
        /// initial camera distance below can be sized to the real track
        /// (roughly 1.4 km across for Barcelona) instead of a guessed
        /// constant that only showed a fraction of the lap.
        private var trackSpan: Double = 400
        /// The dense, resampled skeleton `buildCircuit` generates every
        /// mesh from - kept around so drivers can be positioned against the
        /// exact same points, via `CircuitCenterline.position(atFraction:)`
        /// below, without rebuilding it every tick.
        private var samples: [CenterlineSample] = []

        private var driverPucks: [String: SCNNode] = [:]
        private var driverTags: [String: SCNNode] = [:]
        private var driverVisualKeys: [String: String] = [:]

        private static let trackWidth: Double = 12
        private static let runoffWidth: Double = 10
        private static let kerbWidth: Double = 1.0
        private static let kerbHeight: Double = 0.08
        private static let kerbStripeLength: Double = 6
        private static let pitLaneWidth: Double = 9
        private static let pitLaneGap: Double = 2
        private static let dollySensitivity: Float = 6

        func setupSceneIfNeeded() {
            guard !didSetupScene else { return }
            didSetupScene = true
            buildCircuit()
            setupCameraAndLighting()
        }

        private func buildCircuit() {
            let samples = CircuitCenterline.build()
            self.samples = samples
            guard !samples.isEmpty else { return }

            scene.rootNode.addChildNode(TrackMeshFactory.makeTerrain(samples: samples, margin: 120))
            scene.rootNode.addChildNode(TrackMeshFactory.makeRunoff(samples: samples, trackWidth: Self.trackWidth, runoffWidth: Self.runoffWidth))
            scene.rootNode.addChildNode(TrackMeshFactory.makeTrackSurface(samples: samples, width: Self.trackWidth))

            let kerbSections = CircuitFeatureDetection.detectKerbSections(samples: samples)
            scene.rootNode.addChildNode(TrackMeshFactory.makeKerbs(
                samples: samples,
                trackWidth: Self.trackWidth,
                kerbWidth: Self.kerbWidth,
                kerbHeight: Self.kerbHeight,
                stripeLength: Self.kerbStripeLength,
                sections: kerbSections
            ))

            if let straight = CircuitFeatureDetection.longestStraight(samples: samples),
               let pitLane = TrackMeshFactory.makePitLane(
                   samples: samples,
                   range: straight,
                   trackWidth: Self.trackWidth,
                   pitLaneWidth: Self.pitLaneWidth,
                   gap: Self.pitLaneGap
               ) {
                scene.rootNode.addChildNode(pitLane)
            }

            let minElevation = samples.map(\.position.y).min() ?? 0
            minCameraHeight = Float(minElevation) + 2

            let xs = samples.map(\.position.x)
            let zs = samples.map(\.position.z)
            let width = (xs.max() ?? 0) - (xs.min() ?? 0)
            let depth = (zs.max() ?? 0) - (zs.min() ?? 0)
            trackSpan = max(width, depth, 100)
        }

        private func setupCameraAndLighting() {
            let cameraNode = SCNNode()
            let camera = SCNCamera()
            camera.fieldOfView = 60
            camera.zFar = 6000
            cameraNode.camera = camera
            // High and back enough to frame the whole lap at once - sized to
            // the real circuit's own measured extent (`trackSpan`, computed
            // in `buildCircuit`), not a guessed constant. The camera
            // controller takes over from here.
            let distance = trackSpan * 0.8
            cameraNode.position = SCNVector3(0, distance * 0.75, distance * 0.75)
            cameraNode.look(at: SCNVector3Zero)
            scene.rootNode.addChildNode(cameraNode)
            self.cameraNode = cameraNode

            let controller = SCNCameraController()
            controller.pointOfView = cameraNode
            controller.interactionMode = .orbitTurntable
            controller.target = SCNVector3Zero
            self.cameraController = controller

            let sun = SCNNode()
            sun.light = SCNLight()
            sun.light?.type = .directional
            sun.light?.intensity = 1100
            sun.light?.castsShadow = false
            sun.eulerAngles = SCNVector3(-Float.pi / 3.2, Float.pi / 4, 0)
            scene.rootNode.addChildNode(sun)

            let ambient = SCNNode()
            ambient.light = SCNLight()
            ambient.light?.type = .ambient
            ambient.light?.intensity = 450
            scene.rootNode.addChildNode(ambient)
        }

        // MARK: - Camera gestures
        //
        // Unrestricted panning, orbiting, and horizontal/vertical rotation -
        // one-finger drag orbits (and tilts, all the way past horizontal if
        // the user keeps dragging - no pitch clamp), two-finger drag pans,
        // pinch dollies in/out. Only the resulting camera *position* is ever
        // corrected (`clampCameraHeight`); its orientation from
        // `SCNCameraController` is never touched. Driven through
        // `beginInteraction`/`continueInteraction`/`endInteraction` -
        // `SCNCameraController`'s own correctly-scaled interaction API,
        // the same one `allowsCameraControl` uses internally - rather than
        // guessed-at sensitivity constants on `rotateBy`/
        // `translateInCameraSpaceBy`. See `TrackMapView3D` for the same
        // pattern (and why a per-frame render-loop clamp doesn't work: it
        // races against the gesture updates and loses).

        func attachGestures(to view: SCNView) {
            let orbit = UIPanGestureRecognizer(target: self, action: #selector(handleOrbitPan(_:)))
            orbit.maximumNumberOfTouches = 1
            orbit.delegate = self
            view.addGestureRecognizer(orbit)

            let pan = UIPanGestureRecognizer(target: self, action: #selector(handleTranslatePan(_:)))
            pan.minimumNumberOfTouches = 2
            pan.delegate = self
            view.addGestureRecognizer(pan)

            let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
            pinch.delegate = self
            view.addGestureRecognizer(pinch)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }

        @objc private func handleOrbitPan(_ gr: UIPanGestureRecognizer) {
            guard let controller = cameraController, let view = gr.view else { return }
            controller.interactionMode = .orbitTurntable
            driveInteraction(controller, with: gr, in: view)
        }

        @objc private func handleTranslatePan(_ gr: UIPanGestureRecognizer) {
            guard let controller = cameraController, let view = gr.view else { return }
            controller.interactionMode = .truck
            driveInteraction(controller, with: gr, in: view)
        }

        private func driveInteraction(_ controller: SCNCameraController, with gr: UIPanGestureRecognizer, in view: UIView) {
            let point = gr.location(in: view)
            switch gr.state {
            case .began:
                controller.beginInteraction(point, withViewport: view.bounds.size)
            case .changed:
                controller.continueInteraction(point, withViewport: view.bounds.size, sensitivity: 1)
                clampCameraHeight()
            case .ended, .cancelled, .failed:
                controller.endInteraction(point, withViewport: view.bounds.size, velocity: .zero)
                clampCameraHeight()
            default:
                break
            }
        }

        @objc private func handlePinch(_ gr: UIPinchGestureRecognizer) {
            guard let controller = cameraController, let view = gr.view else { return }
            let delta = Float(1 - gr.scale)
            controller.dolly(by: delta * Self.dollySensitivity, onScreenPoint: gr.location(in: view), viewport: view.bounds.size)
            gr.scale = 1
            clampCameraHeight()
        }

        private func clampCameraHeight() {
            guard let cameraNode else { return }
            if cameraNode.position.y < minCameraHeight {
                cameraNode.position.y = minCameraHeight
            }
        }

        // MARK: - Drivers
        //
        // Each driver is a glowing, always-camera-facing circle plus a tag
        // floating above it - the same visual language as `TrackMapView3D`,
        // just built at real-world (meter) scale for this environment.
        // Position comes from `row.lapProgress` (0...1 through the driver's
        // current lap) walked along `samples` - the exact same dense
        // GeoJSON-derived skeleton the track/kerbs/runoff were built from,
        // so a driver can never end up anywhere the real track doesn't
        // actually go. Live pit-lane diversion (the dogleg into the pit
        // lane mesh) isn't wired up yet - a pitting driver still follows the
        // main racing line for now.

        private static let puckHeightAboveTrack: Double = 0.4
        private static let tagGap: Double = 1.6

        func update(rows: [StandingRow], selectedCode: String?, tickInterval: Double) {
            guard !samples.isEmpty else { return }
            let visibleRows = rows.filter { !$0.hasRetiredYet }
            let hasSelection = selectedCode != nil
            var seenCodes: Set<String> = []

            for row in visibleRows {
                let code = row.driver.code
                seenCodes.insert(code)
                let isSelected = code == selectedCode
                let isPitting = row.isCurrentlyPitting

                let puck = puckNode(for: code)
                let tag = tagNode(for: code)

                let visualKey = "\(row.driver.teamYear)|\(isSelected)|\(hasSelection)|\(isPitting)"
                if driverVisualKeys[code] != visualKey {
                    driverVisualKeys[code] = visualKey
                    puck.geometry = Self.makePuckGeometry(row: row, isSelected: isSelected, isPitting: isPitting)
                    tag.geometry = Self.makeTagGeometry(row: row, isPitting: isPitting)
                    tag.isHidden = hasSelection && !isSelected
                }

                let diameter = Self.dotDiameter(isSelected: isSelected, isPitting: isPitting)
                let base = CircuitCenterline.position(atFraction: row.lapProgress, samples: samples)
                let puckPosition = base + SIMD3(0, Self.puckHeightAboveTrack, 0)
                let tagPosition = base + SIMD3(0, Self.puckHeightAboveTrack + Self.tagGap + diameter / 2, 0)

                SCNTransaction.begin()
                SCNTransaction.animationDuration = tickInterval
                SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .linear)
                puck.position = SCNVector3(puckPosition)
                tag.position = SCNVector3(tagPosition)
                SCNTransaction.commit()
            }

            for code in driverPucks.keys where !seenCodes.contains(code) {
                driverPucks[code]?.removeFromParentNode()
                driverTags[code]?.removeFromParentNode()
                driverPucks.removeValue(forKey: code)
                driverTags.removeValue(forKey: code)
                driverVisualKeys.removeValue(forKey: code)
            }
        }

        private func puckNode(for code: String) -> SCNNode {
            if let existing = driverPucks[code] { return existing }
            let node = SCNNode()
            node.constraints = [SCNBillboardConstraint()]
            scene.rootNode.addChildNode(node)
            driverPucks[code] = node
            return node
        }

        private func tagNode(for code: String) -> SCNNode {
            if let existing = driverTags[code] { return existing }
            let node = SCNNode()
            node.constraints = [SCNBillboardConstraint()]
            scene.rootNode.addChildNode(node)
            driverTags[code] = node
            return node
        }

        /// F1 cars are roughly 2m wide - these are sized relative to that,
        /// not to the flat 2D map's own arbitrary point sizes.
        private static func dotDiameter(isSelected: Bool, isPitting: Bool) -> Double {
            isPitting ? 1.6 : (isSelected ? 3.4 : 2.2)
        }

        private static func makePuckGeometry(row: StandingRow, isSelected: Bool, isPitting: Bool) -> SCNGeometry {
            let diameter = dotDiameter(isSelected: isSelected, isPitting: isPitting)
            let teamColor = DriverInfo.color(forTeam: DriverInfo.team(fromTeamYear: row.driver.teamYear))

            let content = Circle()
                .fill(teamColor)
                .opacity(isPitting ? 0.55 : 1)
                .overlay(Circle().stroke(.white, lineWidth: isSelected ? 3 : 1))
                .frame(width: 40, height: 40)

            let renderer = ImageRenderer(content: content)
            renderer.scale = 3
            let image = renderer.uiImage ?? UIImage()

            let plane = SCNPlane(width: diameter, height: diameter)
            let material = SCNMaterial()
            material.diffuse.contents = image
            material.lightingModel = .constant
            material.isDoubleSided = true
            material.writesToDepthBuffer = false
            plane.materials = [material]
            plane.firstMaterial?.transparencyMode = .aOne
            return plane
        }

        private static func makeTagGeometry(row: StandingRow, isPitting: Bool) -> SCNGeometry {
            let content = Text(isPitting ? "PIT" : row.driver.code)
                .font(.system(size: isPitting ? 6 : 7, weight: .bold))
                .padding(.horizontal, 3)
                .padding(.vertical, 1)
                .background(isPitting ? AnyShapeStyle(.orange) : AnyShapeStyle(Color.white.opacity(0.9)), in: Capsule())
                .foregroundStyle(isPitting ? .white : .black)
                .fixedSize()

            let renderer = ImageRenderer(content: content)
            renderer.scale = 3
            let image = renderer.uiImage ?? UIImage()
            let aspect = image.size.width == 0 ? 1 : image.size.height / image.size.width
            let planeWidth: Double = 3.6
            let plane = SCNPlane(width: planeWidth, height: planeWidth * aspect)

            let material = SCNMaterial()
            material.diffuse.contents = image
            material.lightingModel = .constant
            material.isDoubleSided = true
            material.writesToDepthBuffer = false
            plane.materials = [material]
            plane.firstMaterial?.transparencyMode = .aOne
            return plane
        }
    }
}

private extension SCNVector3 {
    init(_ v: SIMD3<Double>) {
        self.init(Float(v.x), Float(v.y), Float(v.z))
    }
}
