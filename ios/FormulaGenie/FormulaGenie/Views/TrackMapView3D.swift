//
//  TrackMapView3D.swift
//  FormulaGenie
//
//  The real 2D track (outline, start/finish, pit lane - no driver dots) laid
//  flat as a single textured floor, with each driver a glowing, always-
//  camera-facing circle sprite plus a tag that floats above it. A free
//  SceneKit camera (`allowsCameraControl`) orbits, tilts, and zooms around
//  this fixed scene.
//
//  Positions come from `TrackMapView.displayPoint(for:)` - the exact
//  function the 2D map uses for the same row - mapped into world space by
//  the SAME formula the floor's own texture mapping uses (see
//  `worldPosition(for:)`), so a puck can never end up anywhere the floor's
//  own drawn racing line doesn't also pass through.
//

import SwiftUI
import SceneKit

struct TrackMapView3D: UIViewRepresentable {
    let rows: [StandingRow]
    let selectedCode: String?
    let tickInterval: Double

    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.scene = context.coordinator.scene
        scnView.backgroundColor = .black
        context.coordinator.setupSceneIfNeeded()
        // Without this, SCNView ignores the camera node added to the scene
        // and falls back to its own default (unaimed) camera.
        scnView.pointOfView = context.coordinator.cameraNode
        // `allowsCameraControl`'s built-in gesture handling updates the
        // camera on its own timeline (main-thread gesture events), racing
        // against any attempt to clamp its height from the render loop -
        // the clamp would get overwritten by the next gesture update before
        // it ever reached the screen. Driving an `SCNCameraController`
        // directly from our own gestures instead means every camera-moving
        // call and its height clamp happen back-to-back in the same call,
        // with nothing able to interleave in between.
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
        /// Does the actual camera math (orbit/pan/dolly) for each gesture -
        /// SceneKit's own scriptable camera-rig API, the same one
        /// `allowsCameraControl` uses internally, just driven by hand here
        /// so every update can be height-clamped immediately afterward.
        private var cameraController: SCNCameraController?
        /// The floor sits at world Y=0 - `SCNCameraController` has no
        /// notion of that on its own, so it's enforced by hand, immediately
        /// after every gesture-driven camera move (see `clampCameraHeight`):
        /// never let the camera's height reach or pass the floor, the same
        /// way it couldn't physically go through a real one. Rotation/pitch
        /// is never touched here - only ever the camera's own Y position.
        private static let minCameraHeight: Float = 0.5

        private static let dollySensitivity: Float = 4

        /// SwiftUI points (`TrackMapView.trackSize`'s own unit) per SceneKit
        /// world unit.
        private static let worldScale: CGFloat = 10
        /// How far above the floor a driver's circle sprite sits - just
        /// enough to avoid z-fighting with the floor texture underneath it.
        private static let puckHeight: CGFloat = 0.35
        /// Gap between the top of the puck and the bottom of its tag - large
        /// enough that the tag reads as clearly floating above the puck
        /// rather than sitting right on top of (and hiding) it, even from a
        /// near-overhead camera angle where a small gap barely registers.
        private static let tagGap: CGFloat = 1.6

        private var driverPucks: [String: SCNNode] = [:]
        private var driverTags: [String: SCNNode] = [:]
        private var driverVisualKeys: [String: String] = [:]

        func setupSceneIfNeeded() {
            guard !didSetupScene else { return }
            didSetupScene = true
            setupFloor()
            setupCameraAndLighting()
        }

        private func setupFloor() {
            let trackSize = TrackMapView.trackSize
            // Empty `rows` - this floor is only the track outline,
            // start/finish line, and pit lane now; drivers are real 3D
            // objects added separately below, not baked into this texture.
            let renderer = ImageRenderer(
                content: TrackMapView(rows: [], selectedCode: nil, tickInterval: 0.1)
                    .frame(width: trackSize.width, height: trackSize.height)
            )
            renderer.scale = 3
            guard let floorImage = renderer.uiImage else { return }

            let plane = SCNPlane(
                width: trackSize.width / Self.worldScale,
                height: trackSize.height / Self.worldScale
            )
            let material = SCNMaterial()
            material.diffuse.contents = floorImage
            // A `UIImage`'s origin is top-left; a plane's UV origin is
            // bottom-left, so without this the floor renders upside down.
            // `wrapT` MUST be `.repeat`, not `.clamp`, for this trick to
            // work: scaling V by -1 sends it negative, and only `.repeat`
            // wraps a negative V back into [0,1] via modulo - `.clamp` pins
            // every sample to a single (transparent) edge row instead,
            // making the whole plane read as invisible.
            material.diffuse.contentsTransform = SCNMatrix4MakeScale(1, 1, 1)
            material.diffuse.wrapT = .repeat
            material.lightingModel = .constant
            material.isDoubleSided = true
            plane.materials = [material]

            let floorNode = SCNNode(geometry: plane)
            // A plane stands upright (spans X/Y) by default - tip it flat
            // onto the ground (spans X/Z) so it reads as a floor, not a wall.
            // No further rotation beyond this: the texture is an unmodified
            // render of the real 2D map, so it needs no orientation fix-up,
            // and neither does anything positioned against it below.
            floorNode.eulerAngles.x = -.pi / 2
            scene.rootNode.addChildNode(floorNode)
        }

        private func setupCameraAndLighting() {
            let trackSize = TrackMapView.trackSize
            let span = max(trackSize.width, trackSize.height) / Self.worldScale

            let cameraNode = SCNNode()
            let camera = SCNCamera()
            camera.fieldOfView = 50
            camera.zFar = Double(span * 10)
            cameraNode.camera = camera
            // A 3/4 overhead start, framing the whole track - the built-in
            // camera control (`allowsCameraControl`) takes over from here for
            // orbiting, tilting, and zooming.
            cameraNode.position = SCNVector3(0, span * 0.85, span * 0.85)
            cameraNode.look(at: SCNVector3Zero)
            scene.rootNode.addChildNode(cameraNode)
            self.cameraNode = cameraNode

            let controller = SCNCameraController()
            controller.pointOfView = cameraNode
            controller.interactionMode = .orbitTurntable
            controller.target = SCNVector3Zero
            self.cameraController = controller

            let omni = SCNNode()
            omni.light = SCNLight()
            omni.light?.type = .omni
            omni.light?.intensity = 1200
            omni.position = SCNVector3(0, span * 2, 0)
            scene.rootNode.addChildNode(omni)

            let ambient = SCNNode()
            ambient.light = SCNLight()
            ambient.light?.type = .ambient
            ambient.light?.intensity = 500
            scene.rootNode.addChildNode(ambient)
        }

        /// Unrestricted panning, orbiting, and horizontal/vertical rotation
        /// - one-finger drag orbits (and tilts, all the way past horizontal
        /// if the user keeps dragging - no pitch clamp), two-finger drag
        /// pans, pinch dollies in/out. Only the resulting camera *position*
        /// is ever corrected (see `clampCameraHeight`); its orientation from
        /// `SCNCameraController` is never touched, so the camera can end up
        /// looking from any angle, including straight down at the floor
        /// from just above it.
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
            // `.orbitTurntable` is what `beginInteraction`/`continueInteraction`
            // actually orbits by - set right before use since the pan
            // handler below temporarily switches this to `.truck`.
            controller.interactionMode = .orbitTurntable
            driveInteraction(controller, with: gr, in: view)
        }

        @objc private func handleTranslatePan(_ gr: UIPanGestureRecognizer) {
            guard let controller = cameraController, let view = gr.view else { return }
            // Moves the camera across the ground plane rather than rotating
            // it - the "drag to pan" half of the Sims/city-builder feel.
            controller.interactionMode = .truck
            driveInteraction(controller, with: gr, in: view)
        }

        /// Feeds one gesture's touch point through `SCNCameraController`'s
        /// own begin/continue/end interaction methods - the same,
        /// correctly-scaled API `allowsCameraControl` uses internally,
        /// rather than guessing at a sensitivity constant for `rotateBy`/
        /// `translateInCameraSpaceBy` by hand (which is what made the
        /// camera barely move at all before). No momentum on release
        /// (`velocity: .zero`) - inertia would keep moving the camera after
        /// this function returns, outside the one place its height ever
        /// gets corrected.
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

        /// The one and only place the camera's position is corrected -
        /// called synchronously, right after every gesture-driven camera
        /// move, so there is no frame where an over-the-floor position could
        /// ever actually render. Never touches rotation/pitch.
        private func clampCameraHeight() {
            guard let cameraNode else { return }
            if cameraNode.position.y < Self.minCameraHeight {
                cameraNode.position.y = Self.minCameraHeight
            }
        }

        /// The same mapping the floor's own texture uses (see the comment on
        /// `contentsTransform` above): the floor gets no rotation beyond the
        /// flat tilt, so a driver's world X/Z is a direct, unmirrored scale
        /// of their 2D canvas position - nothing here needs to compensate
        /// for anything the floor's rotation would otherwise do, because
        /// there isn't one.
        private static func worldPosition(for row: StandingRow, height: CGFloat) -> SCNVector3 {
            let point2D = TrackMapView.displayPoint(for: row)
            let trackSize = TrackMapView.trackSize
            return SCNVector3(
                (point2D.x - trackSize.width / 2) / worldScale,
                height,
                (point2D.y - trackSize.height / 2) / worldScale
            )
        }

        func update(rows: [StandingRow], selectedCode: String?, tickInterval: Double) {
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

                // Regenerate the puck/tag appearance only when what they
                // should LOOK like actually changed - not on every tick,
                // when only position moves.
                let visualKey = "\(row.driver.teamYear)|\(isSelected)|\(hasSelection)|\(isPitting)"
                if driverVisualKeys[code] != visualKey {
                    driverVisualKeys[code] = visualKey
                    puck.geometry = Self.makePuckGeometry(row: row, isSelected: isSelected, isPitting: isPitting)
                    tag.geometry = Self.makeTagGeometry(row: row, isPitting: isPitting)
                    tag.isHidden = hasSelection && !isSelected
                }

                let dotDiameter = Self.dotDiameter(isSelected: isSelected, isPitting: isPitting)
                let puckPosition = Self.worldPosition(for: row, height: Self.puckHeight)
                let tagPosition = Self.worldPosition(for: row, height: Self.puckHeight + Self.tagGap + dotDiameter / 4)

                // Matches `RaceStore.tickInterval` / the 2D map's own
                // tick-driven movement, so cars move at the same smoothness
                // in both views.
                SCNTransaction.begin()
                SCNTransaction.animationDuration = tickInterval
                SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .linear)
                puck.position = puckPosition
                tag.position = tagPosition
                SCNTransaction.commit()
            }

            // A driver who retires mid-replay disappears from `rows` (once
            // filtered above) exactly like the 2D map's own retired-driver
            // handling - drop their puck/tag rather than leave them stranded.
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
            // Always faces the camera, same as the tag - a flat glowing
            // circle rather than a solid puck reads correctly from any
            // orbit/tilt angle without needing its own 3D geometry.
            node.constraints = [SCNBillboardConstraint()]
            scene.rootNode.addChildNode(node)
            driverPucks[code] = node
            return node
        }

        private func tagNode(for code: String) -> SCNNode {
            if let existing = driverTags[code] { return existing }
            let node = SCNNode()
            // Always faces the camera, through any orbit/tilt, so the text
            // stays readable from any angle.
            node.constraints = [SCNBillboardConstraint()]
            scene.rootNode.addChildNode(node)
            driverTags[code] = node
            return node
        }

        /// Matches `DriverDot.dotSize` in `TrackMapView.swift` - the 2D
        /// map's own sizing rule for a driver's dot - converted to world
        /// units for the puck's diameter.
        private static func dotDiameter(isSelected: Bool, isPitting: Bool) -> CGFloat {
            (isPitting ? 6 : (isSelected ? 12 : 8)) / worldScale
        }

        /// A flat, always-camera-facing circle - team-colored, dimmed while
        /// pitting, ringed in white while selected - snapshotted the same
        /// way the tag is rather than built as solid 3D geometry. Rendered
        /// with a `.constant` lighting model (ignores scene lights
        /// entirely), the color comes through at full, flat intensity
        /// against the black background, reading as if it's glowing rather
        /// than lit.
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

        /// Snapshots a small SwiftUI label (team-neutral, matching the 2D
        /// map's own tag look) for this driver's floating tag.
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
            // A tag's own aspect ratio varies with its text ("PIT" vs a
            // 3-letter code), which `image.size` already reflects - build
            // the plane to match instead of a fixed square, or the text
            // would stretch.
            let aspect = image.size.width == 0 ? 1 : image.size.height / image.size.width
            let planeWidth: CGFloat = 3.2
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
