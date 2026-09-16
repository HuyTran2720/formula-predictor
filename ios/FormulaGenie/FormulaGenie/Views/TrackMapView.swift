//
//  TrackMapView.swift
//  FormulaGenie
//
//  The real Circuit de Barcelona-Catalunya outline - projected from actual
//  survey coordinates (a GeoJSON trace of the circuit, the "es-1991" record),
//  not hand-guessed. Longitude is compressed by cos(latitude) before scaling to
//  screen points, since a degree of longitude covers less real ground than a
//  degree of latitude this far from the equator - skipping that would stretch
//  the shape noticeably sideways. This is the one piece of real track geometry
//  in the project; everything else about the model (lap times, tyre wear) is
//  still built from data that carries no positional information at all.
//
//  What's simulated on top of this real shape is each driver's position along
//  it: `row.lapProgress` (0...1 through their current lap) places their dot, so
//  relative spacing on the track reflects actual pace and gaps.
//
//  The outline is a plain polyline (straight segments only, no arcs or curves)
//  and `point(atFraction:)` walks that exact same point list to place a dot -
//  deliberately not using SwiftUI's `Path.trimmedPath`, whose length-proportional
//  guarantee isn't reliable exactly where a line meets a curve. Same geometry
//  for both the drawing and the math means a dot can never drift off the line.
//

import SwiftUI

struct TrackMapView: View {
    let rows: [StandingRow]
    let selectedCode: String?
    /// Matched to `RaceStore.tickInterval` - see its doc comment. Passed down
    /// to each `DriverDot` as its position-animation duration so the dot is
    /// always moving, never reaching a tick's position early and sitting
    /// frozen until the next tick arrives.
    let tickInterval: Double

    private let trackSize = CGSize(width: 380, height: 137.3)

    /// Closed loop, in the direction cars actually race, rotated so the main
    /// straight runs horizontally along the bottom with the rest of the lap
    /// above it - projected from the real survey coordinates (see header), then
    /// levelled by the angle of a least-squares fit through the straight's own
    /// points (not just its two endpoints, which a small kink near turn 1 could
    /// skew) and re-fit to the canvas. Generated once, not hand-placed.
    private static let trackPoints: [CGPoint] = [
        CGPoint(x: 43.31, y: 119.11),
        CGPoint(x: 35.35, y: 118.35),
        CGPoint(x: 31.18, y: 116.57),
        CGPoint(x: 26.98, y: 113.88),
        CGPoint(x: 24.41, y: 111.46),
        CGPoint(x: 21.9, y: 108.46),
        CGPoint(x: 20.31, y: 105.74),
        CGPoint(x: 19.22, y: 102.93),
        CGPoint(x: 18.51, y: 100.15),
        CGPoint(x: 18.32, y: 96.34),
        CGPoint(x: 18.26, y: 80.98),
        CGPoint(x: 18.43, y: 76.54),
        CGPoint(x: 18.12, y: 69.32),
        CGPoint(x: 18.03, y: 61.15),
        CGPoint(x: 18.0, y: 53.85),
        CGPoint(x: 18.52, y: 50.59),
        CGPoint(x: 19.86, y: 47.04),
        CGPoint(x: 22.11, y: 43.68),
        CGPoint(x: 24.85, y: 40.54),
        CGPoint(x: 27.31, y: 38.6),
        CGPoint(x: 30.66, y: 36.88),
        CGPoint(x: 33.87, y: 35.85),
        CGPoint(x: 65.94, y: 25.23),
        CGPoint(x: 69.6, y: 24.35),
        CGPoint(x: 73.23, y: 24.6),
        CGPoint(x: 77.57, y: 26.18),
        CGPoint(x: 78.85, y: 27.15),
        CGPoint(x: 81.51, y: 29.34),
        CGPoint(x: 83.38, y: 32.18),
        CGPoint(x: 84.78, y: 35.14),
        CGPoint(x: 85.27, y: 38.79),
        CGPoint(x: 84.93, y: 42.73),
        CGPoint(x: 83.91, y: 45.57),
        CGPoint(x: 80.95, y: 49.57),
        CGPoint(x: 78.03, y: 51.51),
        CGPoint(x: 72.74, y: 53.67),
        CGPoint(x: 66.76, y: 55.43),
        CGPoint(x: 63.33, y: 57.23),
        CGPoint(x: 58.72, y: 60.11),
        CGPoint(x: 56.08, y: 62.61),
        CGPoint(x: 54.2, y: 65.24),
        CGPoint(x: 52.6, y: 68.03),
        CGPoint(x: 51.04, y: 71.45),
        CGPoint(x: 50.15, y: 74.08),
        CGPoint(x: 49.45, y: 78.79),
        CGPoint(x: 49.75, y: 82.17),
        CGPoint(x: 50.29, y: 84.7),
        CGPoint(x: 51.46, y: 86.97),
        CGPoint(x: 53.39, y: 89.09),
        CGPoint(x: 55.62, y: 90.21),
        CGPoint(x: 57.88, y: 90.48),
        CGPoint(x: 60.75, y: 89.93),
        CGPoint(x: 64.64, y: 87.83),
        CGPoint(x: 170.47, y: 25.17),
        CGPoint(x: 174.21, y: 23.82),
        CGPoint(x: 178.84, y: 23.0),
        CGPoint(x: 181.62, y: 23.0),
        CGPoint(x: 185.61, y: 23.25),
        CGPoint(x: 188.49, y: 24.32),
        CGPoint(x: 191.35, y: 25.65),
        CGPoint(x: 194.78, y: 27.81),
        CGPoint(x: 197.73, y: 30.59),
        CGPoint(x: 212.08, y: 51.17),
        CGPoint(x: 224.85, y: 69.39),
        CGPoint(x: 225.85, y: 71.24),
        CGPoint(x: 227.16, y: 74.25),
        CGPoint(x: 227.94, y: 76.96),
        CGPoint(x: 228.48, y: 81.3),
        CGPoint(x: 228.27, y: 88.55),
        CGPoint(x: 228.95, y: 92.17),
        CGPoint(x: 230.69, y: 95.33),
        CGPoint(x: 233.36, y: 97.7),
        CGPoint(x: 235.58, y: 98.35),
        CGPoint(x: 239.09, y: 98.81),
        CGPoint(x: 264.55, y: 98.67),
        CGPoint(x: 269.81, y: 98.0),
        CGPoint(x: 276.16, y: 96.38),
        CGPoint(x: 281.77, y: 94.3),
        CGPoint(x: 286.81, y: 91.85),
        CGPoint(x: 318.31, y: 71.04),
        CGPoint(x: 319.46, y: 70.2),
        CGPoint(x: 321.49, y: 68.05),
        CGPoint(x: 322.17, y: 66.39),
        CGPoint(x: 322.7, y: 64.07),
        CGPoint(x: 322.59, y: 61.85),
        CGPoint(x: 321.97, y: 60.09),
        CGPoint(x: 321.05, y: 58.27),
        CGPoint(x: 319.22, y: 56.44),
        CGPoint(x: 317.4, y: 55.34),
        CGPoint(x: 315.02, y: 54.59),
        CGPoint(x: 272.56, y: 54.88),
        CGPoint(x: 265.75, y: 54.33),
        CGPoint(x: 261.53, y: 53.68),
        CGPoint(x: 257.67, y: 52.29),
        CGPoint(x: 254.55, y: 50.58),
        CGPoint(x: 249.65, y: 47.2),
        CGPoint(x: 246.89, y: 44.38),
        CGPoint(x: 243.95, y: 39.55),
        CGPoint(x: 243.05, y: 36.49),
        CGPoint(x: 242.56, y: 32.29),
        CGPoint(x: 242.72, y: 28.96),
        CGPoint(x: 243.43, y: 26.41),
        CGPoint(x: 244.79, y: 23.57),
        CGPoint(x: 248.43, y: 20.06),
        CGPoint(x: 251.15, y: 18.66),
        CGPoint(x: 253.66, y: 18.0),
        CGPoint(x: 312.84, y: 18.06),
        CGPoint(x: 317.49, y: 18.04),
        CGPoint(x: 322.92, y: 18.72),
        CGPoint(x: 329.41, y: 20.27),
        CGPoint(x: 337.09, y: 22.78),
        CGPoint(x: 341.63, y: 24.82),
        CGPoint(x: 345.62, y: 27.22),
        CGPoint(x: 349.11, y: 29.91),
        CGPoint(x: 352.01, y: 32.24),
        CGPoint(x: 355.57, y: 36.42),
        CGPoint(x: 358.34, y: 40.86),
        CGPoint(x: 361.01, y: 48.03),
        CGPoint(x: 361.42, y: 50.35),
        CGPoint(x: 361.82, y: 52.89),
        CGPoint(x: 362.0, y: 55.5),
        CGPoint(x: 361.54, y: 60.04),
        CGPoint(x: 360.66, y: 63.5),
        CGPoint(x: 359.18, y: 66.7),
        CGPoint(x: 357.64, y: 69.45),
        CGPoint(x: 356.1, y: 71.9),
        CGPoint(x: 353.91, y: 74.42),
        CGPoint(x: 351.04, y: 76.75),
        CGPoint(x: 348.84, y: 78.46),
        CGPoint(x: 346.42, y: 79.92),
        CGPoint(x: 325.28, y: 88.04),
        CGPoint(x: 322.7, y: 89.29),
        CGPoint(x: 319.64, y: 92.41),
        CGPoint(x: 318.04, y: 94.95),
        CGPoint(x: 316.75, y: 98.51),
        CGPoint(x: 316.43, y: 100.76),
        CGPoint(x: 316.48, y: 108.52),
        CGPoint(x: 316.34, y: 110.65),
        CGPoint(x: 315.73, y: 112.55),
        CGPoint(x: 314.48, y: 114.85),
        CGPoint(x: 312.65, y: 117.08),
        CGPoint(x: 311.17, y: 118.05),
        CGPoint(x: 308.8, y: 118.75),
        CGPoint(x: 305.74, y: 119.27),
        CGPoint(x: 293.59, y: 119.27),
        CGPoint(x: 257.71, y: 119.06),
        CGPoint(x: 223.85, y: 119.13),
        CGPoint(x: 190.84, y: 118.92),
        CGPoint(x: 131.72, y: 118.92),
    ]

    /// `trackPoints` with the closing segment back to the start appended, so
    /// perimeter math can walk one flat list - computed once and shared by
    /// `totalLength` and `point(atFraction:)` rather than rebuilt on every call.
    private static let closedTrackPoints: [CGPoint] = trackPoints + [trackPoints[0]]

    private static let totalLength: Double = {
        zip(closedTrackPoints, closedTrackPoints.dropFirst()).reduce(0) { $0 + distance($1.0, $1.1) }
    }()

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> Double {
        Double(hypot(b.x - a.x, b.y - a.y))
    }

    /// Exact position at `fraction` (0...1) around the perimeter, interpolated
    /// linearly within whichever segment it falls in.
    private static func point(atFraction fraction: Double) -> CGPoint {
        let pts = closedTrackPoints
        let target = totalLength * min(max(fraction, 0), 1)
        var walked = 0.0
        for i in 0..<(pts.count - 1) {
            let segmentLength = distance(pts[i], pts[i + 1])
            if walked + segmentLength >= target || i == pts.count - 2 {
                let t = segmentLength > 0 ? (target - walked) / segmentLength : 0
                return CGPoint(
                    x: pts[i].x + (pts[i + 1].x - pts[i].x) * CGFloat(t),
                    y: pts[i].y + (pts[i + 1].y - pts[i].y) * CGFloat(t)
                )
            }
            walked += segmentLength
        }
        return pts[0]
    }

    private var trackPath: Path {
        Path { path in
            path.move(to: Self.trackPoints[0])
            for p in Self.trackPoints.dropFirst() { path.addLine(to: p) }
            path.closeSubpath()
        }
    }

    /// A short line across the track's width at fraction 0 (the start/finish
    /// point every dot's lap wraps through) - perpendicular to the local
    /// track direction there, not just assumed-horizontal, so it still reads
    /// correctly if the survey geometry ever changes.
    private var startFinishPath: Path {
        let p0 = Self.trackPoints[0]
        let p1 = Self.trackPoints[1]
        let dx = Double(p1.x - p0.x)
        let dy = Double(p1.y - p0.y)
        let length = max(hypot(dx, dy), 0.0001)
        let nx = -dy / length
        let ny = dx / length
        let halfWidth = 8.0
        let a = CGPoint(x: p0.x + CGFloat(nx * halfWidth), y: p0.y + CGFloat(ny * halfWidth))
        let b = CGPoint(x: p0.x - CGFloat(nx * halfWidth), y: p0.y - CGFloat(ny * halfWidth))
        return Path { path in
            path.move(to: a)
            path.addLine(to: b)
        }
    }

    /// Where the pit lane leaves the racing line and where it rejoins - right
    /// where the last corner ends and the main straight begins, through to the
    /// start/finish line itself (measured along the actual survey points, not
    /// guessed) rather than stopping short of it on the straight.
    private static let pitLaneEntryFraction = 0.7883
    /// == fraction 0, the same closed-loop point - matches `RaceStore`'s copy
    /// of this constant exactly (see its doc comment for why they must agree).
    private static let pitLaneExitFraction = 1.0

    /// A straight line offset a fixed distance from the racing line between the
    /// entry and exit points - standing in for the pit lane itself (parallel to
    /// the main straight it runs beside), rather than a real pit-lane survey,
    /// since none was supplied.
    private static let pitLaneEntryPoint: CGPoint = offsetPoint(atFraction: pitLaneEntryFraction)
    private static let pitLaneExitPoint: CGPoint = offsetPoint(atFraction: pitLaneExitFraction)

    /// The main straight is levelled near-perfectly horizontal by the track's
    /// own rotation (see its header), sitting near the BOTTOM of the canvas
    /// with the rest of the lap above it (smaller y). So "outside the
    /// straight, away from the infield" is simply "larger y" here - a plain
    /// downward push, rather than a perpendicular-to-segment computation
    /// whose sign kept coming out wrong (the straight's two ends aren't
    /// ordered left-to-right the way that math assumed).
    /// Vertical distance from the racing line to the pit lane - this is the
    /// one number to change for "a bit more up/down" (positive = further
    /// down/south, away from the infield).
    private static let pitLaneVerticalOffset: CGFloat = 7

    private static func offsetPoint(atFraction fraction: Double) -> CGPoint {
        let base = point(atFraction: fraction)
        return CGPoint(x: base.x, y: base.y + pitLaneVerticalOffset)
    }

    /// Straight-line position `fraction` (0...1) of the way along the pit lane,
    /// from its entry to its exit.
    private static func pitLanePoint(atFraction fraction: Double) -> CGPoint {
        let t = min(max(fraction, 0), 1)
        return CGPoint(
            x: pitLaneEntryPoint.x + (pitLaneExitPoint.x - pitLaneEntryPoint.x) * CGFloat(t),
            y: pitLaneEntryPoint.y + (pitLaneExitPoint.y - pitLaneEntryPoint.y) * CGFloat(t)
        )
    }

    private var pitLanePath: Path {
        Path { path in
            path.move(to: Self.pitLaneEntryPoint)
            path.addLine(to: Self.pitLaneExitPoint)
        }
    }

    /// Where a driver's dot actually sits: the racing line normally, but for a
    /// pit lap, two phases across the lap's elapsed time (`row.lapProgress`) -
    /// driving normally up to the pit entrance (`row.pitEntryProgress` - not
    /// always the fixed geometric entrance; see its doc comment), then
    /// dwelling in the pit lane (starting from `row.pitLaneStartT` along the
    /// drawn line rather than always its very start) the rest of the way to
    /// the end of the lap - the pit lane's exit IS the start/finish line, so
    /// there's no "driving normally again" phase left once the dwell ends.
    ///
    /// Phase 1 reduces algebraically to exactly
    /// `point(atFraction: elapsedInLap / normalSeconds)` - the same formula
    /// used for every non-pit lap - so it lines up exactly with wherever the
    /// dot already was the instant before a live "Box now" tap, even though
    /// that tap immediately inflates the lap's total duration (`lapProgress`'s
    /// denominator) by `race.pitLoss`.
    private static func displayPoint(for row: StandingRow) -> CGPoint {
        guard row.isPitLap else { return point(atFraction: row.lapProgress) }

        let m = max(row.pitMainPortion, 0.0001)
        let b1 = row.pitEntryProgress
        let p = row.lapProgress

        if p <= b1 {
            return point(atFraction: p / m) // == elapsedInLap / normalSeconds
        }
        let dwellT = (p - b1) / max(1 - b1, 0.0001)
        return pitLanePoint(atFraction: row.pitLaneStartT + dwellT * (1 - row.pitLaneStartT))
    }

    var body: some View {
        GeometryReader { geo in
            let scale = min(geo.size.width / trackSize.width, geo.size.height / trackSize.height)

            ZStack {
                trackPath
                    .stroke(Color(white: 0.38), style: StrokeStyle(lineWidth: 12, lineCap: .round, lineJoin: .round))

                startFinishPath
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 3, dash: [3, 2.5]))

                pitLanePath
                    .stroke(Color.red, style: StrokeStyle(lineWidth: 3, lineCap: .round))

                // A retired driver's car is off track (in the garage), same
                // as a real broadcast, once the replay actually reaches the
                // lap they retired on.
                //
                // Two passes, not one: every LABEL first, then every CIRCLE -
                // so a wide tag from one driver can never end up drawn on top
                // of (and hiding) a different driver's circle, which is what
                // happened when a bunched-up pack's tags overlapped each
                // other's dots. Circles are always the topmost layer; the tag
                // toggle below still only ever affects the label.
                ForEach(sortedForDrawing.filter { !$0.hasRetiredYet }) { row in
                    DriverDot(row: row, isSelected: row.driver.code == selectedCode, hasSelection: selectedCode != nil, isPitting: row.isCurrentlyPitting, tickInterval: tickInterval, layer: .label)
                        .position(Self.displayPoint(for: row))
                }
                ForEach(sortedForDrawing.filter { !$0.hasRetiredYet }) { row in
                    DriverDot(row: row, isSelected: row.driver.code == selectedCode, hasSelection: selectedCode != nil, isPitting: row.isCurrentlyPitting, tickInterval: tickInterval, layer: .circle)
                        .position(Self.displayPoint(for: row))
                }
            }
            .frame(width: trackSize.width, height: trackSize.height)
            .scaleEffect(scale)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
    }

    /// Draw the leader last (on top) so a bunched-up pack at the front doesn't
    /// bury the car that matters most under everyone behind it.
    private var sortedForDrawing: [StandingRow] {
        rows.sorted { $0.newPosition > $1.newPosition }
    }
}

private struct DriverDot: View {
    let row: StandingRow
    let isSelected: Bool
    /// True while ANY driver is selected - gates the TAG only (see `layer`);
    /// every non-selected driver's tag hides while one is selected, and every
    /// tag comes back once nothing is.
    let hasSelection: Bool
    /// True while this driver is in the pit-lane portion of a pit lap - shrinks
    /// and dims the dot to read as "slowing down / stopped" rather than at pace.
    let isPitting: Bool
    /// Matched to the actual tick rate (`RaceStore.tickInterval`) - a shorter
    /// duration than the interval between position updates leaves the dot
    /// sitting frozen for the remainder of each tick once it arrives early; a
    /// longer one piles pending retargets on top of each other at a high
    /// speed multiplier's faster tick rate. Either mismatch reads as stutter.
    let tickInterval: Double
    /// Which piece THIS instance actually draws. `TrackMapView.body` renders
    /// every driver's `.label` pass before any `.circle` pass, so a wide tag
    /// can never end up drawn on top of (and hiding) a different driver's
    /// circle - circles are always the topmost layer, unconditionally. Both
    /// passes still go through the exact same frame/offset math below so
    /// they land in the exact same place as when they were one view.
    enum Layer { case label, circle }
    let layer: Layer

    private var dotSize: CGFloat { isPitting ? 6 : (isSelected ? 12 : 8) }

    var body: some View {
        // The CIRCLE is the view `.position()` centers from outside - it must
        // stay the root/base view so its frame is exactly what gets placed on
        // the track point. The label used to be stacked above it in a VStack,
        // which centered the whole label+circle GROUP on that point instead,
        // shifting the circle itself away from the real track position by
        // roughly half the group's height - on a curving track that made the
        // dot visibly hug whichever edge the label-side offset happened to
        // land on, and swap sides as the local track direction changed.
        // An overlay, not a sibling, keeps the circle's frame (and center)
        // untouched by the label's own size. The offset is a flat constant
        // rather than an `.alignmentGuide` keyed off the label's measured
        // height - the guide-based version silently stopped moving the label
        // at all once the label and circle became two separate view
        // instances (see `TrackMapView.body`'s two-pass ForEach) instead of
        // one shared overlay, for reasons not fully understood; a plain
        // `.offset` reliably reproduces the same small gap above the circle.
        // On the `.label` pass the circle itself is invisible (opacity 0) but
        // still occupies its real frame, so the label's position - anchored
        // off that frame - is identical to the `.circle` pass's.
        Circle()
            .fill(DriverInfo.color(forTeam: DriverInfo.team(fromTeamYear: row.driver.teamYear)))
            .opacity(layer == .label ? 0 : (isPitting ? 0.55 : 1))
            .frame(width: dotSize, height: dotSize)
            .overlay(Circle().stroke(.white, lineWidth: isSelected ? 1.5 : 0.5).opacity(layer == .label ? 0 : 1))
            .shadow(radius: layer == .circle && isSelected ? 2 : 0)
            .overlay(alignment: .top) {
                if layer == .label, !hasSelection || isSelected {
                    label
                        .fixedSize()
                        .offset(y: -13)
                }
            }
            .animation(.linear(duration: tickInterval), value: row.lapProgress)
    }

    @ViewBuilder
    private var label: some View {
        if isPitting {
            Text("PIT")
                .font(.system(size: 6, weight: .bold))
                .padding(.horizontal, 3)
                .padding(.vertical, 1)
                .background(.orange, in: Capsule())
                .foregroundStyle(.white)
        } else {
            Text(row.driver.code)
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(.black)
                .padding(.horizontal, 3)
                .padding(.vertical, 1)
                .background(Color.white.opacity(0.9), in: Capsule())
        }
    }
}
