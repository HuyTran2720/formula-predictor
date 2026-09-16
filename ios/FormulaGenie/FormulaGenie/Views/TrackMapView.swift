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

    private let trackSize = CGSize(width: 360, height: 301.4)

    /// Closed loop, in the direction cars actually race (reversed from the raw
    /// GeoJSON trace order below, which ran the opposite way around the lap).
    private static let trackPoints: [CGPoint] = Array(rawTrackPoints.reversed())

    /// Points exactly as projected from the real survey coordinates (see
    /// header). Generated once from the GeoJSON trace, not hand-placed.
    private static let rawTrackPoints: [CGPoint] = [
        CGPoint(x: 162.9, y: 225.92),
        CGPoint(x: 216.66, y: 192.06),
        CGPoint(x: 246.8, y: 173.34),
        CGPoint(x: 277.54, y: 153.88),
        CGPoint(x: 310.29, y: 133.51),
        CGPoint(x: 321.34, y: 126.55),
        CGPoint(x: 323.83, y: 124.33),
        CGPoint(x: 325.58, y: 122.34),
        CGPoint(x: 326.37, y: 120.61),
        CGPoint(x: 326.76, y: 117.53),
        CGPoint(x: 326.58, y: 114.72),
        CGPoint(x: 326.04, y: 112.64),
        CGPoint(x: 324.95, y: 110.62),
        CGPoint(x: 320.46, y: 103.6),
        CGPoint(x: 319.46, y: 101.37),
        CGPoint(x: 318.59, y: 97.39),
        CGPoint(x: 318.59, y: 94.17),
        CGPoint(x: 319.59, y: 89.57),
        CGPoint(x: 321.22, y: 86.96),
        CGPoint(x: 335.79, y: 67.47),
        CGPoint(x: 337.15, y: 64.75),
        CGPoint(x: 338.18, y: 61.94),
        CGPoint(x: 339.45, y: 58.18),
        CGPoint(x: 340.0, y: 54.63),
        CGPoint(x: 340.0, y: 51.52),
        CGPoint(x: 339.82, y: 48.14),
        CGPoint(x: 339.33, y: 44.38),
        CGPoint(x: 338.15, y: 40.73),
        CGPoint(x: 335.97, y: 36.34),
        CGPoint(x: 334.31, y: 34.07),
        CGPoint(x: 332.49, y: 31.99),
        CGPoint(x: 330.79, y: 30.11),
        CGPoint(x: 324.25, y: 25.12),
        CGPoint(x: 319.19, y: 22.67),
        CGPoint(x: 313.56, y: 20.91),
        CGPoint(x: 309.59, y: 20.45),
        CGPoint(x: 304.87, y: 20.0),
        CGPoint(x: 299.87, y: 20.11),
        CGPoint(x: 294.57, y: 20.86),
        CGPoint(x: 286.15, y: 22.97),
        CGPoint(x: 279.36, y: 25.28),
        CGPoint(x: 274.03, y: 27.77),
        CGPoint(x: 269.82, y: 30.45),
        CGPoint(x: 215.97, y: 64.3),
        CGPoint(x: 214.06, y: 66.34),
        CGPoint(x: 212.39, y: 69.17),
        CGPoint(x: 211.09, y: 74.45),
        CGPoint(x: 211.49, y: 77.81),
        CGPoint(x: 212.3, y: 80.53),
        CGPoint(x: 214.06, y: 83.65),
        CGPoint(x: 216.91, y: 87.19),
        CGPoint(x: 219.48, y: 89.46),
        CGPoint(x: 224.93, y: 92.17),
        CGPoint(x: 229.05, y: 93.15),
        CGPoint(x: 235.44, y: 93.42),
        CGPoint(x: 239.26, y: 93.19),
        CGPoint(x: 243.56, y: 92.24),
        CGPoint(x: 247.77, y: 90.41),
        CGPoint(x: 254.28, y: 87.01),
        CGPoint(x: 292.72, y: 62.42),
        CGPoint(x: 295.32, y: 61.74),
        CGPoint(x: 297.6, y: 61.7),
        CGPoint(x: 300.32, y: 62.31),
        CGPoint(x: 302.2, y: 63.44),
        CGPoint(x: 303.77, y: 64.69),
        CGPoint(x: 305.14, y: 66.64),
        CGPoint(x: 305.99, y: 69.06),
        CGPoint(x: 306.32, y: 70.96),
        CGPoint(x: 305.71, y: 74.07),
        CGPoint(x: 305.14, y: 75.5),
        CGPoint(x: 288.42, y: 112.46),
        CGPoint(x: 285.24, y: 117.58),
        CGPoint(x: 281.33, y: 122.68),
        CGPoint(x: 276.48, y: 127.8),
        CGPoint(x: 272.09, y: 131.42),
        CGPoint(x: 249.01, y: 146.13),
        CGPoint(x: 245.56, y: 147.72),
        CGPoint(x: 243.17, y: 148.4),
        CGPoint(x: 239.38, y: 147.78),
        CGPoint(x: 235.99, y: 145.9),
        CGPoint(x: 233.29, y: 143.0),
        CGPoint(x: 229.33, y: 136.29),
        CGPoint(x: 226.36, y: 132.65),
        CGPoint(x: 224.09, y: 130.63),
        CGPoint(x: 221.18, y: 128.64),
        CGPoint(x: 219.21, y: 127.53),
        CGPoint(x: 197.16, y: 118.28),
        CGPoint(x: 172.32, y: 107.79),
        CGPoint(x: 168.05, y: 106.95),
        CGPoint(x: 163.69, y: 106.95),
        CGPoint(x: 160.33, y: 107.38),
        CGPoint(x: 157.09, y: 108.06),
        CGPoint(x: 153.33, y: 110.12),
        CGPoint(x: 150.79, y: 111.71),
        CGPoint(x: 147.06, y: 115.11),
        CGPoint(x: 144.43, y: 118.48),
        CGPoint(x: 84.09, y: 236.09),
        CGPoint(x: 81.76, y: 240.22),
        CGPoint(x: 79.46, y: 242.37),
        CGPoint(x: 77.25, y: 243.41),
        CGPoint(x: 74.58, y: 243.68),
        CGPoint(x: 71.61, y: 242.85),
        CGPoint(x: 69.25, y: 241.46),
        CGPoint(x: 67.31, y: 239.47),
        CGPoint(x: 65.1, y: 236.57),
        CGPoint(x: 63.04, y: 231.88),
        CGPoint(x: 62.34, y: 228.98),
        CGPoint(x: 61.8, y: 224.97),
        CGPoint(x: 61.65, y: 221.52),
        CGPoint(x: 61.86, y: 218.05),
        CGPoint(x: 62.83, y: 214.27),
        CGPoint(x: 65.37, y: 209.01),
        CGPoint(x: 67.46, y: 205.41),
        CGPoint(x: 71.88, y: 200.38),
        CGPoint(x: 75.46, y: 195.39),
        CGPoint(x: 77.0, y: 191.95),
        CGPoint(x: 77.4, y: 186.62),
        CGPoint(x: 76.7, y: 183.45),
        CGPoint(x: 74.76, y: 179.67),
        CGPoint(x: 72.22, y: 176.63),
        CGPoint(x: 69.25, y: 174.75),
        CGPoint(x: 65.92, y: 173.23),
        CGPoint(x: 62.25, y: 172.76),
        CGPoint(x: 60.53, y: 172.62),
        CGPoint(x: 55.68, y: 173.66),
        CGPoint(x: 52.23, y: 175.52),
        CGPoint(x: 49.41, y: 178.42),
        CGPoint(x: 26.33, y: 206.45),
        CGPoint(x: 24.0, y: 209.22),
        CGPoint(x: 21.94, y: 212.71),
        CGPoint(x: 20.82, y: 215.88),
        CGPoint(x: 20.12, y: 220.3),
        CGPoint(x: 20.0, y: 224.65),
        CGPoint(x: 20.82, y: 228.64),
        CGPoint(x: 22.21, y: 231.9),
        CGPoint(x: 26.42, y: 238.52),
        CGPoint(x: 31.18, y: 245.9),
        CGPoint(x: 35.6, y: 252.29),
        CGPoint(x: 37.99, y: 256.42),
        CGPoint(x: 46.84, y: 270.36),
        CGPoint(x: 49.2, y: 273.71),
        CGPoint(x: 51.44, y: 275.84),
        CGPoint(x: 54.04, y: 277.77),
        CGPoint(x: 57.04, y: 279.33),
        CGPoint(x: 61.04, y: 280.62),
        CGPoint(x: 64.77, y: 281.35),
        CGPoint(x: 70.13, y: 281.39),
        CGPoint(x: 74.94, y: 280.62),
        CGPoint(x: 82.61, y: 276.75)
    ]

    private static let totalLength: Double = {
        let pts = trackPoints + [trackPoints[0]]
        return zip(pts, pts.dropFirst()).reduce(0) { $0 + distance($1.0, $1.1) }
    }()

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> Double {
        Double(hypot(b.x - a.x, b.y - a.y))
    }

    /// Exact position at `fraction` (0...1) around the perimeter, interpolated
    /// linearly within whichever segment it falls in.
    private static func point(atFraction fraction: Double) -> CGPoint {
        let pts = trackPoints + [trackPoints[0]]
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

    /// Where the pit lane leaves the racing line and where it rejoins - right
    /// where the last corner ends and the main straight begins, through to
    /// three-quarters of the way down that straight (measured along the actual
    /// survey points, not guessed), matching where a real pit lane would run
    /// alongside it rather than the full length of the straight.
    private static let pitLaneEntryFraction = 0.7883
    private static let pitLaneExitFraction = 0.9471

    /// A straight line offset a fixed distance from the racing line between the
    /// entry and exit points - standing in for the pit lane itself (parallel to
    /// the main straight it runs beside), rather than a real pit-lane survey,
    /// since none was supplied.
    private static let pitLaneEntryPoint: CGPoint = offsetPoint(atFraction: pitLaneEntryFraction)
    private static let pitLaneExitPoint: CGPoint = offsetPoint(atFraction: pitLaneExitFraction)

    private static func offsetPoint(atFraction fraction: Double) -> CGPoint {
        let entry = point(atFraction: pitLaneEntryFraction)
        let exit = point(atFraction: pitLaneExitFraction)
        let dx = Double(exit.x - entry.x)
        let dy = Double(exit.y - entry.y)
        let length = max(hypot(dx, dy), 0.0001)
        // Rotated the other way (and pulled in closer) from the first pass -
        // that one drifted above the straight instead of running snugly
        // alongside it, making the deviation into it look like a jump rather
        // than a smooth peel-off.
        let normalX = dy / length
        let normalY = -dx / length
        let offset = 9.0
        let base = point(atFraction: fraction)
        return CGPoint(x: base.x + CGFloat(normalX * offset), y: base.y + CGFloat(normalY * offset))
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
    /// pit lap, three phases across the lap's elapsed time (`row.lapProgress`) -
    /// driving normally up to the pit entrance, dwelling in the pit lane for
    /// however much of the lap the stop actually cost (`row.pitMainPortion`),
    /// then driving normally again from the pit exit to the line. Without that
    /// third phase the dot would reach the exit and instantly jump to the
    /// start/finish point when the lap rolls over, skipping whatever track
    /// distance remains after the exit - this keeps it continuous. Purely a
    /// display choice; the timing behind it never changes.
    private static func displayPoint(for row: StandingRow) -> CGPoint {
        guard row.isPitLap else { return point(atFraction: row.lapProgress) }

        // "Distance units" of normal (non-pit-lane) driving this lap: the main
        // path before the entrance plus what's left of it after the exit.
        // `pitMainPortion` (a time fraction) is split across these two in the
        // same ratio, since both are driven at the same normal pace.
        let beforeEntry = pitLaneEntryFraction
        let afterExit = 1 - pitLaneExitFraction
        let normalDistanceUnits = max(beforeEntry + afterExit, 0.0001)

        let main = max(row.pitMainPortion, 0.0001)
        let t1 = main * (beforeEntry / normalDistanceUnits) // elapsed fraction at which the entrance is reached
        let dwell = max(1 - main, 0.0001)
        let t2 = t1 + dwell // elapsed fraction at which the exit is reached

        if row.lapProgress <= t1 {
            return point(atFraction: (row.lapProgress / max(t1, 0.0001)) * pitLaneEntryFraction)
        }
        if row.lapProgress <= t2 {
            return pitLanePoint(atFraction: (row.lapProgress - t1) / dwell)
        }
        let afterExitElapsed = max(1 - t2, 0.0001)
        let postT = (row.lapProgress - t2) / afterExitElapsed
        return point(atFraction: pitLaneExitFraction + postT * afterExit)
    }

    /// True while `displayPoint` would currently place this row's dot in the
    /// pit lane itself, rather than on the racing line before or after it.
    private static func isInPitLane(_ row: StandingRow) -> Bool {
        guard row.isPitLap else { return false }
        let beforeEntry = pitLaneEntryFraction
        let afterExit = 1 - pitLaneExitFraction
        let normalDistanceUnits = max(beforeEntry + afterExit, 0.0001)
        let main = max(row.pitMainPortion, 0.0001)
        let t1 = main * (beforeEntry / normalDistanceUnits)
        let t2 = t1 + max(1 - main, 0.0001)
        return row.lapProgress > t1 && row.lapProgress <= t2
    }

    var body: some View {
        GeometryReader { geo in
            let scale = min(geo.size.width / trackSize.width, geo.size.height / trackSize.height)

            ZStack {
                trackPath
                    .stroke(Color.gray.opacity(0.3), style: StrokeStyle(lineWidth: 12, lineCap: .round, lineJoin: .round))
                trackPath
                    .stroke(Color.primary.opacity(0.25), style: StrokeStyle(lineWidth: 1.2, dash: [4, 4]))

                pitLanePath
                    .stroke(Color.orange.opacity(0.5), style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [1, 5]))

                ForEach(sortedForDrawing) { row in
                    let inPitLane = Self.isInPitLane(row)
                    DriverDot(row: row, isSelected: row.driver.code == selectedCode, isPitting: inPitLane)
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
    /// True while this driver is in the pit-lane portion of a pit lap - shrinks
    /// and dims the dot to read as "slowing down / stopped" rather than at pace.
    let isPitting: Bool

    var body: some View {
        VStack(spacing: 1) {
            if isPitting {
                Text("PIT")
                    .font(.system(size: 6, weight: .bold))
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(.orange, in: Capsule())
                    .foregroundStyle(.white)
                    .fixedSize()
            } else {
                Text(row.driver.code)
                    .font(.system(size: 7, weight: .bold))
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(.thinMaterial, in: Capsule())
                    .fixedSize()
            }

            Circle()
                .fill(DriverInfo.color(forTeam: DriverInfo.team(fromTeamYear: row.driver.teamYear)))
                .opacity(isPitting ? 0.55 : 1)
                .frame(width: isPitting ? 6 : (isSelected ? 12 : 8), height: isPitting ? 6 : (isSelected ? 12 : 8))
                .overlay(Circle().stroke(.white, lineWidth: isSelected ? 1.5 : 0.5))
                .shadow(radius: isSelected ? 2 : 0)
        }
        .animation(.linear(duration: 0.1), value: row.lapProgress)
    }
}
