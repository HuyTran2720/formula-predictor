//
//  TrackMeshFactory.swift
//  FormulaGenie
//
//  Builds each piece of the 3D circuit - track surface, runoff/grass, kerbs,
//  pit lane - as its own separate `SCNNode`/`SCNGeometry` from the shared
//  `CenterlineSample` skeleton, never fused into one mesh, so any one piece
//  can be swapped, hidden, or restyled independently later. Every shape here
//  is a ribbon or a set of quads built by offsetting sideways from the
//  centerline using each sample's own `normal` - never by touching the
//  GeoJSON-derived samples themselves.
//

import SceneKit
import simd

enum TrackMeshFactory {

    // MARK: - Track surface

    static func makeTrackSurface(samples: [CenterlineSample], width: Double) -> SCNNode {
        let geometry = ribbon(samples: samples, innerOffset: -width / 2, outerOffset: width / 2, verticalOffset: 0.06)
        geometry.firstMaterial = flatMaterial(color: UIColor(white: 0.16, alpha: 1), roughness: 0.9)
        let node = SCNNode(geometry: geometry)
        node.name = "trackSurface"
        return node
    }

    // MARK: - Runoff / grass

    /// A band on each side of the track, from its edge out to `runoffWidth`
    /// further - sitting at the same elevation as the track itself (offset
    /// only enough to avoid z-fighting), so the track reads as inset into a
    /// grass verge rather than floating above a flat green square.
    static func makeRunoff(samples: [CenterlineSample], trackWidth: Double, runoffWidth: Double) -> SCNNode {
        let halfTrack = trackWidth / 2
        let material = flatMaterial(color: UIColor(red: 0.16, green: 0.34, blue: 0.15, alpha: 1), roughness: 1)

        let left = ribbon(samples: samples, innerOffset: halfTrack, outerOffset: halfTrack + runoffWidth, verticalOffset: 0.02)
        left.firstMaterial = material
        let right = ribbon(samples: samples, innerOffset: -(halfTrack + runoffWidth), outerOffset: -halfTrack, verticalOffset: 0.02)
        right.firstMaterial = material

        let node = SCNNode()
        node.name = "runoff"
        node.addChildNode(SCNNode(geometry: left))
        node.addChildNode(SCNNode(geometry: right))
        return node
    }

    // MARK: - Surrounding terrain

    /// A coarse grid covering the circuit's bounding box plus a margin, with
    /// a gentle, independent undulation of its own - not a precise
    /// continuation of the track's elevation, just enough that the ground
    /// reads as real terrain rather than a perfectly flat sheet the track
    /// and runoff are pasted onto.
    static func makeTerrain(samples: [CenterlineSample], margin: Double, resolution: Int = 48) -> SCNNode {
        let xs = samples.map { $0.position.x }
        let zs = samples.map { $0.position.z }
        guard let minX = xs.min(), let maxX = xs.max(), let minZ = zs.min(), let maxZ = zs.max() else {
            return SCNNode()
        }
        let lowX = minX - margin, highX = maxX + margin
        let lowZ = minZ - margin, highZ = maxZ + margin
        // The track's own elevation varies by *arc-length fraction*, not by
        // raw (x, z) position, so an undulation keyed on (x, z) here (as
        // this used to be, centered on the track's *average* elevation) is
        // completely uncorrelated with the actual local track/runoff height
        // at any given point. With both wobbling by a similar few meters,
        // the terrain would rise above the track at some points along the
        // lap and visibly poke through it - reading as missing/disconnected
        // road. Anchoring to the track's lowest point anywhere, with a
        // small enough undulation that it can never climb back up to that
        // floor, guarantees the terrain always stays under the track and
        // runoff, everywhere, regardless of where either one happens to be
        // on a given lap.
        let minTrackElevation = samples.map(\.position.y).min() ?? 0
        let terrainBase = minTrackElevation - 1.0

        var vertices: [SCNVector3] = []
        var normals: [SCNVector3] = []
        vertices.reserveCapacity((resolution + 1) * (resolution + 1))
        for iz in 0...resolution {
            let z = lowZ + (highZ - lowZ) * Double(iz) / Double(resolution)
            for ix in 0...resolution {
                let x = lowX + (highX - lowX) * Double(ix) / Double(resolution)
                let y = terrainBase + terrainUndulation(x: x, z: z)
                vertices.append(SCNVector3(x, y, z))
                normals.append(SCNVector3(0, 1, 0))
            }
        }

        var indices: [Int32] = []
        let stride = resolution + 1
        for iz in 0..<resolution {
            for ix in 0..<resolution {
                let i0 = Int32(iz * stride + ix)
                let i1 = i0 + 1
                let i2 = Int32((iz + 1) * stride + ix)
                let i3 = i2 + 1
                indices.append(contentsOf: [i0, i2, i1, i1, i2, i3])
            }
        }

        let geometry = SCNGeometry(
            sources: [SCNGeometrySource(vertices: vertices), SCNGeometrySource(normals: normals)],
            elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)]
        )
        geometry.firstMaterial = flatMaterial(color: UIColor(red: 0.12, green: 0.26, blue: 0.12, alpha: 1), roughness: 1)
        let node = SCNNode(geometry: geometry)
        node.name = "terrain"
        return node
    }

    /// Amplitude kept well under `terrainBase`'s 1.0-meter buffer below the
    /// track's own lowest point above, so this can never lift the terrain
    /// back up to where it could occlude the track/runoff.
    private static func terrainUndulation(x: Double, z: Double) -> Double {
        sin(x * 0.01) * 0.3 + cos(z * 0.013 + 0.7) * 0.25
    }

    // MARK: - Kerbs

    /// Alternating red/white stripe quads (vertex-colored, not separate
    /// materials, so the whole system stays one draw call) along whichever
    /// `sections` are supplied - see `CircuitFeatureDetection` for the
    /// curvature-based default, which this only consumes, never computes
    /// itself, so a hand-authored section list can be substituted freely.
    static func makeKerbs(samples: [CenterlineSample], trackWidth: Double, kerbWidth: Double, kerbHeight: Double, stripeLength: Double, sections: [KerbSection]) -> SCNNode {
        let node = SCNNode()
        node.name = "kerbs"
        let halfTrack = trackWidth / 2

        for section in sections {
            let relevant = samples.filter { section.range.contains($0.distanceAlong) }
            guard relevant.count > 1 else { continue }

            let sideSign: Double = section.side == .left ? 1 : -1
            let innerOffset = sideSign * halfTrack
            let outerOffset = sideSign * (halfTrack + kerbWidth)

            var vertices: [SCNVector3] = []
            var colorComponents: [Float] = []
            var indices: [Int32] = []

            for i in 0..<(relevant.count - 1) {
                let a = relevant[i]
                let b = relevant[i + 1]
                let stripeIndex = Int(a.distanceAlong / stripeLength)
                let color: [Float] = stripeIndex % 2 == 0 ? [0.72, 0.08, 0.08, 1] : [0.92, 0.92, 0.9, 1]

                let aInner = offsetPoint(a, lateral: innerOffset, vertical: kerbHeight)
                let aOuter = offsetPoint(a, lateral: outerOffset, vertical: kerbHeight)
                let bInner = offsetPoint(b, lateral: innerOffset, vertical: kerbHeight)
                let bOuter = offsetPoint(b, lateral: outerOffset, vertical: kerbHeight)

                let base = Int32(vertices.count)
                vertices.append(contentsOf: [aInner, aOuter, bInner, bOuter])
                for _ in 0..<4 { colorComponents.append(contentsOf: color) }
                indices.append(contentsOf: [base, base + 2, base + 1, base + 1, base + 2, base + 3])
            }

            guard !vertices.isEmpty else { continue }
            let vertexSource = SCNGeometrySource(vertices: vertices)
            let colorData = Data(bytes: colorComponents, count: colorComponents.count * MemoryLayout<Float>.size)
            let colorSource = SCNGeometrySource(
                data: colorData,
                semantic: .color,
                vectorCount: vertices.count,
                usesFloatComponents: true,
                componentsPerVector: 4,
                bytesPerComponent: MemoryLayout<Float>.size,
                dataOffset: 0,
                dataStride: 4 * MemoryLayout<Float>.size
            )
            let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)
            let geometry = SCNGeometry(sources: [vertexSource, colorSource], elements: [element])
            let material = SCNMaterial()
            material.lightingModel = .lambert
            material.isDoubleSided = true
            geometry.firstMaterial = material
            node.addChildNode(SCNNode(geometry: geometry))
        }
        return node
    }

    // MARK: - Pit lane

    /// A simple parallel ribbon offset to one side of the given range -
    /// deliberately plain (no markings/boxes yet, see the conversation) so
    /// it stays easy to build on: its own separate mesh, ready for pit-box
    /// markings or buildings to be added without touching the main track.
    static func makePitLane(samples: [CenterlineSample], range: ClosedRange<Double>, trackWidth: Double, pitLaneWidth: Double, gap: Double) -> SCNNode? {
        let relevant = samples.filter { range.contains($0.distanceAlong) }
        guard relevant.count > 1 else { return nil }

        let innerOffset = trackWidth / 2 + gap
        let outerOffset = innerOffset + pitLaneWidth
        let geometry = ribbon(samples: relevant, innerOffset: innerOffset, outerOffset: outerOffset, verticalOffset: 0.04, closed: false)
        geometry.firstMaterial = flatMaterial(color: UIColor(white: 0.2, alpha: 1), roughness: 0.9)
        let node = SCNNode(geometry: geometry)
        node.name = "pitLane"
        return node
    }

    // MARK: - Shared helpers

    private static func offsetPoint(_ sample: CenterlineSample, lateral: Double, vertical: Double) -> SCNVector3 {
        SCNVector3(sample.position + sample.normal * lateral + SIMD3(0, vertical, 0))
    }

    /// The core primitive nearly everything above is built from: a
    /// triangulated strip between two offset curves derived from the same
    /// centerline. `innerOffset`/`outerOffset` are signed lateral distances
    /// from the centerline (positive = left, per `CenterlineSample.normal`).
    private static func ribbon(samples: [CenterlineSample], innerOffset: Double, outerOffset: Double, verticalOffset: Double, closed: Bool = true) -> SCNGeometry {
        var vertices: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var uvs: [CGPoint] = []
        vertices.reserveCapacity(samples.count * 2)

        for sample in samples {
            vertices.append(offsetPoint(sample, lateral: innerOffset, vertical: verticalOffset))
            vertices.append(offsetPoint(sample, lateral: outerOffset, vertical: verticalOffset))
            normals.append(SCNVector3(0, 1, 0))
            normals.append(SCNVector3(0, 1, 0))
            let v = Float(sample.distanceAlong / 4)
            uvs.append(CGPoint(x: 0, y: CGFloat(v)))
            uvs.append(CGPoint(x: 1, y: CGFloat(v)))
        }

        var indices: [Int32] = []
        let count = samples.count
        let last = closed ? count : count - 1
        for i in 0..<last {
            let next = (i + 1) % count
            let i0 = Int32(i * 2), i1 = Int32(i * 2 + 1)
            let n0 = Int32(next * 2), n1 = Int32(next * 2 + 1)
            indices.append(contentsOf: [i0, n0, i1, i1, n0, n1])
        }

        return SCNGeometry(
            sources: [SCNGeometrySource(vertices: vertices), SCNGeometrySource(normals: normals), SCNGeometrySource(textureCoordinates: uvs)],
            elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)]
        )
    }

    private static func flatMaterial(color: UIColor, roughness: CGFloat) -> SCNMaterial {
        let material = SCNMaterial()
        material.diffuse.contents = color
        material.roughness.contents = roughness
        material.lightingModel = .physicallyBased
        material.isDoubleSided = true
        return material
    }
}

private extension SCNVector3 {
    init(_ v: SIMD3<Double>) {
        self.init(Float(v.x), Float(v.y), Float(v.z))
    }
}
