//
//  CircuitFeatureDetection.swift
//  FormulaGenie
//
//  Finds where kerbs and the pit lane belong by looking at the centerline's
//  own curvature, rather than hand-listing coordinates: corners (kerbs) are
//  contiguous runs where the track turns sharply, and the pit straight is
//  the single longest contiguous run where it barely turns at all. Producing
//  plain `[ClosedRange<Double>]`/`KerbSection` data (arc-length in meters)
//  keeps this swappable for a hand-authored list later without touching the
//  mesh-building code that consumes it.
//

import Foundation
import simd

struct KerbSection {
    enum Side { case left, right }
    let range: ClosedRange<Double>
    let side: Side
}

enum CircuitFeatureDetection {
    /// Degrees of direction change per sample spacing beyond which a stretch
    /// counts as "in a corner" rather than a straight - tuned against this
    /// circuit's own `CircuitCenterline.sampleSpacing`, not an absolute.
    private static let cornerTurnThresholdDegrees: Double = 3.0
    /// Short, noisy blips under this length aren't worth their own kerb
    /// segment.
    private static let minimumCornerLength: Double = 25

    /// One `KerbSection` per side for every corner found - kerbs on both
    /// edges is a reasonable default for a first pass; trimming to one side,
    /// or dropping a corner entirely, is just filtering this array before
    /// it reaches `TrackMeshFactory.makeKerbs`.
    static func detectKerbSections(samples: [CenterlineSample]) -> [KerbSection] {
        detectCorners(samples: samples).flatMap { range in
            [KerbSection(range: range, side: .left), KerbSection(range: range, side: .right)]
        }
    }

    /// The longest contiguous low-curvature stretch - a real pit lane runs
    /// beside the pit straight, so this is what `TrackMeshFactory.makePitLane`
    /// anchors to instead of a hand-picked coordinate.
    static func longestStraight(samples: [CenterlineSample]) -> ClosedRange<Double>? {
        guard samples.count > 2 else { return nil }
        let turnRates = turnRatesDegreesPerSample(samples: samples)

        var best: ClosedRange<Double>?
        var bestLength = 0.0
        var runStart: Double?
        for i in 0..<turnRates.count {
            let isStraight = turnRates[i] < cornerTurnThresholdDegrees
            if isStraight, runStart == nil {
                runStart = samples[i].distanceAlong
            } else if !isStraight, let start = runStart {
                let end = samples[i].distanceAlong
                if end - start > bestLength {
                    bestLength = end - start
                    best = start...end
                }
                runStart = nil
            }
        }
        if let start = runStart {
            let end = samples.last!.distanceAlong
            if end - start > bestLength {
                best = start...end
            }
        }
        return best
    }

    private static func detectCorners(samples: [CenterlineSample]) -> [ClosedRange<Double>] {
        guard samples.count > 2 else { return [] }
        let turnRates = turnRatesDegreesPerSample(samples: samples)

        var corners: [ClosedRange<Double>] = []
        var runStart: Double?
        for i in 0..<turnRates.count {
            let inCorner = turnRates[i] >= cornerTurnThresholdDegrees
            if inCorner, runStart == nil {
                runStart = samples[i].distanceAlong
            } else if !inCorner, let start = runStart {
                let end = samples[i].distanceAlong
                if end - start >= minimumCornerLength {
                    corners.append(start...end)
                }
                runStart = nil
            }
        }
        if let start = runStart {
            let end = samples.last!.distanceAlong
            if end - start >= minimumCornerLength {
                corners.append(start...end)
            }
        }
        return corners
    }

    private static func turnRatesDegreesPerSample(samples: [CenterlineSample]) -> [Double] {
        samples.indices.map { i in
            let next = samples[(i + 1) % samples.count]
            let cosAngle = simd_dot(samples[i].tangent, next.tangent)
            let angle = acos(min(max(cosAngle, -1), 1))
            return angle * 180 / .pi
        }
    }
}
