//
//  CircuitCenterline.swift
//  FormulaGenie
//
//  Turns the raw GeoJSON survey points (already flattened to local meters by
//  `LocalCoordinateSystem`) into a dense, evenly-spaced skeleton every other
//  part of the 3D environment builds against: a smooth curve through the
//  real points, resampled at a fixed spacing, each sample carrying its
//  direction of travel, its perpendicular (for track-width offsets), how far
//  along the lap it is, and an elevation. The GeoJSON itself is never
//  modified - this only derives a denser representation from it.
//

import Foundation
import simd

struct CenterlineSample {
    /// Meters, local coordinate system: x = east, y = elevation (up),
    /// z = south.
    let position: SIMD3<Double>
    /// Unit vector along the direction of travel, in the X/Z plane.
    let tangent: SIMD3<Double>
    /// Unit vector perpendicular to `tangent`, in the X/Z plane, pointing to
    /// the LEFT of the direction of travel - so `position + normal * (width/2)`
    /// is the track's left edge, `position - normal * (width/2)` its right.
    let normal: SIMD3<Double>
    /// Distance travelled along the whole centerline up to this sample, in
    /// meters - the "1D" coordinate elevation, kerb placement, and pit-lane
    /// placement all key off.
    let distanceAlong: Double
}

enum CircuitCenterline {
    /// How far apart resampled points are, in meters - dense enough for
    /// smooth curves and elevation changes, coarse enough to keep the mesh
    /// light (roughly 550-600 samples for this ~4.9 km lap).
    static let sampleSpacing: Double = 8

    /// Where a driver at `fraction` (0...1) through their current lap
    /// actually is - linearly interpolated between the two nearest
    /// `samples`, the exact same skeleton every mesh in `TrackMeshFactory`
    /// is built from, so a driver can never end up anywhere the real track
    /// doesn't go.
    static func position(atFraction fraction: Double, samples: [CenterlineSample]) -> SIMD3<Double> {
        guard let lapLength = samples.last?.distanceAlong, lapLength > 0 else {
            return samples.first?.position ?? .zero
        }
        let target = min(max(fraction, 0), 1) * lapLength

        var index = 0
        while index < samples.count - 1 && samples[index + 1].distanceAlong < target {
            index += 1
        }
        let a = samples[index]
        let b = samples[min(index + 1, samples.count - 1)]
        let span = b.distanceAlong - a.distanceAlong
        let t = span > 0 ? (target - a.distanceAlong) / span : 0
        return a.position + (b.position - a.position) * t
    }

    static func build(from geoData: CircuitGeoData = .loadBundled()) -> [CenterlineSample] {
        let flat = LocalCoordinateSystem.project(geoData.coordinates)
        // The GeoJSON is a closed lap - the last point is (very nearly) the
        // first. Catmull-Rom needs the loop made explicit so it can find a
        // "previous" and "next" point for every span, including the join.
        var loop = flat
        if let first = loop.first, let last = loop.last, first != last {
            loop.append(first)
        }

        let dense = catmullRomResample(loop, spacing: sampleSpacing)
        guard dense.count > 2 else { return [] }

        var cumulativeDistances: [Double] = [0]
        cumulativeDistances.reserveCapacity(dense.count)
        for i in 1..<dense.count {
            cumulativeDistances.append(cumulativeDistances[i - 1] + simd_distance(dense[i - 1], dense[i]))
        }
        let lapLength = cumulativeDistances.last! + simd_distance(dense.last!, dense[0])

        var samples: [CenterlineSample] = []
        samples.reserveCapacity(dense.count)
        for i in 0..<dense.count {
            let prev = dense[(i - 1 + dense.count) % dense.count]
            let next = dense[(i + 1) % dense.count]
            let direction = next - prev
            let length = simd_length(direction)
            let tangent2D = length > 0 ? direction / length : SIMD2(1, 0)
            // Rotate 90 degrees so the normal points to the left of travel.
            let normal2D = SIMD2(-tangent2D.y, tangent2D.x)

            let distance = cumulativeDistances[i]
            let fraction = lapLength > 0 ? distance / lapLength : 0
            let y = elevation(atFraction: fraction)

            samples.append(CenterlineSample(
                position: SIMD3(dense[i].x, y, dense[i].y),
                tangent: SIMD3(tangent2D.x, 0, tangent2D.y),
                normal: SIMD3(normal2D.x, 0, normal2D.y),
                distanceAlong: distance
            ))
        }
        return samples
    }

    /// Circuit de Barcelona-Catalunya's real elevation profile is gentle -
    /// nothing like a mountain circuit - so this approximates it as two low-
    /// frequency undulations over one lap rather than anything dramatic.
    /// Deliberately isolated to this one function, keyed only on
    /// `fraction` (0...1 around the lap): swapping in a real per-point
    /// survey later is just replacing this body with a lookup - nothing
    /// else in the pipeline (mesh generation, kerbs, pit lane) needs to
    /// change, since they all just read `CenterlineSample.position.y`.
    static func elevation(atFraction fraction: Double) -> Double {
        let t = fraction * 2 * .pi
        return sin(t) * 2.2 + sin(t * 3 + 1.0) * 0.8
    }

    /// Fits a smooth Catmull-Rom curve through the raw survey points and
    /// walks it at even `spacing` intervals. The raw points are unevenly
    /// spaced (dense through corners, sparse down straights) - resampling
    /// evenly avoids visibly sharp kinks in the final mesh wherever two long
    /// straight segments meet at a shallow angle in the raw data.
    private static func catmullRomResample(_ points: [SIMD2<Double>], spacing: Double) -> [SIMD2<Double>] {
        guard points.count > 3 else { return points }
        let segmentsPerSpan = 12
        let n = points.count - 1 // last point duplicates the first (closed loop)

        var curve: [SIMD2<Double>] = []
        curve.reserveCapacity(n * segmentsPerSpan)
        for i in 0..<n {
            let p0 = points[(i - 1 + n) % n]
            let p1 = points[i]
            let p2 = points[(i + 1) % n]
            let p3 = points[(i + 2) % n]
            for step in 0..<segmentsPerSpan {
                let t = Double(step) / Double(segmentsPerSpan)
                curve.append(catmullRom(p0, p1, p2, p3, t))
            }
        }

        // Re-walk the dense curve at even arc-length spacing.
        guard var previous = curve.first else { return curve }
        var resampled: [SIMD2<Double>] = [previous]
        var carry = 0.0
        for point in curve.dropFirst() {
            var segmentStart = previous
            var segmentLength = simd_distance(segmentStart, point)
            while carry + segmentLength >= spacing {
                let t = segmentLength > 0 ? (spacing - carry) / segmentLength : 0
                let placed = segmentStart + (point - segmentStart) * t
                resampled.append(placed)
                segmentStart = placed
                segmentLength = simd_distance(segmentStart, point)
                carry = 0
            }
            carry += segmentLength
            previous = point
        }
        return resampled
    }

    private static func catmullRom(_ p0: SIMD2<Double>, _ p1: SIMD2<Double>, _ p2: SIMD2<Double>, _ p3: SIMD2<Double>, _ t: Double) -> SIMD2<Double> {
        let t2: Double = t * t
        let t3: Double = t2 * t
        let term0: SIMD2<Double> = 2 * p1
        let term1: SIMD2<Double> = (-p0 + p2) * t
        let term2: SIMD2<Double> = (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2
        let term3: SIMD2<Double> = (-p0 + 3 * p1 - 3 * p2 + p3) * t3
        let sum: SIMD2<Double> = term0 + term1 + term2 + term3
        return sum * 0.5
    }
}
