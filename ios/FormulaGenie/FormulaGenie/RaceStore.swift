//
//  RaceStore.swift
//  FormulaGenie
//
//  Drives the race off ONE continuously-ticking clock, `raceClockSeconds`, which
//  advances in real scaled time (real seconds * speed) - not lap by lap. Every
//  driver has their own schedule (a running total of how long each of their own
//  laps takes, under their current plan), so each driver's row derives its own
//  live "how far into this lap" timer from the same shared clock - that's what
//  makes it a genuinely live per-driver stopwatch instead of one shared number,
//  and what makes a speed change visibly change the ticking rate immediately.
//
//  Every driver defaults to their REAL multi-stint plan from race.json, so a
//  driver nobody touches reproduces the real result exactly - the same "untouched
//  = zero delta" guarantee the original anchored-delta design relies on. Changing
//  the starting compound only edits the first stint; pitting live truncates
//  whatever plan is current at the lap it happens and replaces everything after
//  it, so history plays out exactly as it did until the user actually intervenes.
//

import Combine
import Foundation
import SwiftUI

struct StandingRow: Identifiable {
    var id: String { driver.code }
    let driver: DriverEntry
    let simulatedTotal: Double
    let newPosition: Int
    /// simulatedTotal minus the leader's simulatedTotal - the classic "+1.234s" gap
    /// shown on a real timing screen. Only meaningful once the race has finished.
    let gapToLeader: Double
    /// Non-nil (naming the compound still needed) if this driver's current plan
    /// hasn't used two distinct compounds yet and the race isn't finished. Cleared
    /// the moment they pit for it - manually, or automatically on the last lap.
    let neededCompoundWarning: String?
    /// The lap this driver is CURRENTLY on (their own pace, not a shared field lap).
    let lapNumber: Int
    /// Live seconds elapsed into `lapNumber`, ticking from 0 up to that lap's own
    /// duration and back to 0 the instant it's complete. Frozen at that lap's full
    /// duration once the driver has finished the race.
    let lapElapsedSeconds: Double
    /// 0...1 fraction of `lapNumber` completed so far - this driver's own pace,
    /// so it's what actually moves them around the track map at the right speed
    /// relative to everyone else, rather than everyone sharing one position.
    let lapProgress: Double
    /// +1/-1 while this driver's position changed within the last 5 sim-seconds,
    /// nil once that flash window has elapsed (or nothing has changed yet).
    let recentPositionChange: Int?
    /// True if `lapNumber` is the lap on which this driver's plan actually pits -
    /// purely a display hint (the track map uses it to route the dot through the
    /// pit lane instead of the racing line); the underlying timing is unaffected.
    let isPitLap: Bool
    /// Fraction (0...1) of THIS lap's TOTAL (inflated) duration spent driving
    /// normally before reaching the pit entrance, when `isPitLap` is true -
    /// the rest is the pit-lane dwell (stopping, being serviced, rejoining).
    /// Derived from how much longer this lap took than a normal one
    /// (`race.pitLoss`). Meaningless when `isPitLap` is false.
    let pitMainPortion: Double
    /// `pitMainPortion`'s counterpart in *distance*: the lap-progress value at
    /// which the dwell actually starts. Ordinarily this is just the fixed
    /// geometric entrance's own time-equivalent, but if the pit was a live
    /// decision made AFTER that point (a "Box now" tap late in the lap), it's
    /// pinned to wherever the driver physically was at that moment instead -
    /// otherwise the dot would have to snap backward to the entrance on the
    /// exact tap that starts the stop. See `RaceStore.pitDecisionElapsed`.
    let pitEntryProgress: Double
    /// Where along the drawn pit-lane line (0 = its start, at the fixed
    /// geometric entrance; 1 = its end, at the fixed exit) the dwell actually
    /// begins - normally 0, but pushed forward for a late live pit exactly as
    /// far as `pitEntryProgress` was, so the dot still ends up somewhere ON
    /// the drawn line rather than snapping to its very start.
    let pitLaneStartT: Double
    /// The compound this driver is actually on for `lapNumber` right now - the
    /// stint covering their CURRENT lap, not just whichever stint is last in
    /// their plan (wrong while they're still early in a multi-stint plan).
    let currentCompound: String
    /// True once the race clock has actually reached this driver's real
    /// retirement point (false for the whole race if they finished, and false
    /// for a retiree until the replay actually gets there) - the track map
    /// uses this to pull their car off track, same as a real broadcast would.
    let hasRetiredYet: Bool
    /// True for the exact window of `isPitLap` when this driver is actually
    /// in the pit lane itself (not just driving normally toward or away from
    /// it) - the same boundaries the track map's pit-lane detour uses, so the
    /// leaderboard's "pitting" indicator lines up with the dot leaving the
    /// racing line.
    let isCurrentlyPitting: Bool
}

@MainActor
final class RaceStore: ObservableObject {
    /// Where the pit lane leaves/rejoins the racing line, as a fraction of the
    /// lap - must match `TrackMapView`'s `pitLaneEntryFraction`/
    /// `pitLaneExitFraction` exactly, since this is what decides whether a
    /// pitting driver's row gets the leaderboard's "pitting" indicator at the
    /// same moment their dot is actually shown leaving the racing line.
    private static let pitLaneEntryFraction = 0.7883
    /// Reaches the start/finish point (fraction 1.0 == fraction 0, the same
    /// closed-loop point) rather than stopping short of it on the straight.
    private static let pitLaneExitFraction = 1.0

    @Published var race: RaceData
    @Published private(set) var editedPlans: [String: [PlanStint]] = [:]
    @Published var selectedDriverCode: String?
    /// Cached result of `computeStandings()` - see that function's doc for why
    /// this isn't just a computed property. Refreshed explicitly by
    /// `refreshStandings()` wherever anything it depends on changes.
    @Published private(set) var standings: [StandingRow] = []

    /// How often `play()`'s loop ticks, in seconds - stepped up in three tiers
    /// as the speed multiplier climbs, since a faster multiplier covers more
    /// race-time (and so more track distance) per tick; too slow a tick rate
    /// at a high multiplier made the dot's straight-line position animation
    /// visibly cut across corners between updates, or jump in big steps down
    /// the straights. 10fps already looks smooth at 1x-9x, where each tick's
    /// own distance is small, and running faster there is needless main-thread
    /// work; 30fps covers 10x-29x; 60x and 120x - where a 30fps tick would
    /// still cover ~2-4 race-seconds per step - get 60fps. The single source
    /// of truth for both the tick loop itself AND the driver dot's animation
    /// duration (TrackMapView reads this) - those two have to match, or the
    /// dot reaches wherever this tick sent it and then visibly sits frozen
    /// until the next one arrives, instead of moving continuously.
    var tickInterval: Double {
        switch abs(speedMultiplier) {
        case ..<10: return 0.1     // 10fps
        case ..<30: return 0.033   // 30fps
        default: return 0.0167     // 60fps
        }
    }

    /// Always true - there is only one screen now. Kept as the gate `canPit`,
    /// `play`, and `debugAdvance` already relied on, rather than ripping it out
    /// of every guard for no behavioral change.
    @Published private(set) var raceConfigured = true
    @Published private(set) var isPlaying = false
    /// Shared, signed playback rate: +N means N race-seconds pass per real second
    /// (2x = 2 race-seconds per real second, exactly), -N reverses time at the same
    /// rate. One value drives both the forward and reverse transport buttons, since
    /// they're incrementing/decrementing the same thing, not two separate controls.
    /// Steps through a small fixed set of useful rates (each way) rather than
    /// every integer - skips 0 rather than stopping there; Play/Pause is the
    /// actual stop control.
    @Published private(set) var speedMultiplier = 1

    /// 1,5,10,30,60,120, mirrored negative, in ascending order. increaseSpeed/
    /// decreaseSpeed just step through this list, which is what makes -1 -> 1
    /// (skip zero) fall out for free.
    private static let speedSteps: [Int] = {
        let magnitudes = [1, 5, 10, 30, 60, 120]
        return magnitudes.reversed().map { -$0 } + magnitudes
    }()
    /// Total accumulated race time (this is THE clock - advances or reverses at
    /// `speedMultiplier` race-seconds per real second, read fresh every tick so a
    /// change is visible within a fraction of a second). Everything - lap progress,
    /// the on-screen clock - reads this one value.
    @Published private(set) var raceClockSeconds: Double = 0

    /// Per-driver cumulative lap-time schedule: `schedule[code][n]` is how long it
    /// takes that driver (under their CURRENT plan) to complete their first `n`
    /// laps; `schedule[code][0] == 0`. Rebuilt only when a plan actually changes
    /// (starting grid pick, or a live pit stop) - never on every tick, since each
    /// entry costs a Core ML call.
    private var schedules: [String: [Double]] = [:]

    var isFinished: Bool {
        guard raceConfigured else { return false }
        return finishTime > 0 && raceClockSeconds >= finishTime
    }

    init() {
        let race = RaceData.loadBundled()
        self.race = race
        self.selectedDriverCode = race.drivers.first?.code
        seedStartingGrid()
        resetPositionChangeTracking()
    }

    /// Every lap on which `applyPit` actually created a new stint for this driver -
    /// tracked as explicit events rather than inferred from plan structure, because
    /// pitting on lap 0 (before any lap is complete) leaves nothing to keep before
    /// it, collapsing the plan to a single stint that looks structurally identical
    /// to a starting-grid compound pick. The event record is what still charges
    /// that pit its pitLoss even though the resulting plan has no visible seam.
    private var pitEventLaps: [String: Set<Int>] = [:]

    /// Where (in elapsed seconds into the lap) this driver actually was the
    /// moment their CURRENT pit lap was decided - `lap` pins it to the lap it
    /// applies to, since a driver can pit more than once across a race and an
    /// earlier stop's decision point must never leak into a later one's.
    /// Unset (nil) for a pit lap that isn't a live/auto decision at all - a
    /// driver's own real, untouched multi-stint plan - which is exactly the
    /// case that should use the fixed geometric entrance, same as before.
    private var pitDecisionElapsed: [String: (lap: Int, seconds: Double)] = [:]

    /// Each driver's position as of the last tick - compared against the newly
    /// computed position every tick to detect an actual change event, rather than
    /// a constant comparison against their real-race finishing spot.
    private var lastPosition: [String: Int] = [:]
    /// +1 (moved up) or -1 (moved down) for a driver whose position just changed,
    /// kept only until `positionFlashUntil` - the row briefly shows the arrow in
    /// place of the position number, then reverts.
    private var positionFlashDirection: [String: Int] = [:]
    /// Race-clock time (in sim-seconds, not wall time) at which a position-change
    /// flash should stop - so the 5-second display duration tracks the replay
    /// clock and speeds up/slows down with the playback rate, same as everything
    /// else in the sim.
    private var positionFlashUntil: [String: Double] = [:]

    /// Call after `raceClockSeconds` (or a plan) changes and standings may have
    /// reordered - diffs the new positions against `lastPosition` and starts a
    /// flash for anyone who moved, then refreshes the cached `standings` so
    /// views pick up both the new order AND the flash just started.
    private func updatePositionChangeTracking() {
        let fresh = computeStandings()
        for row in fresh {
            let code = row.driver.code
            if let previous = lastPosition[code], previous != row.newPosition {
                positionFlashDirection[code] = previous > row.newPosition ? 1 : -1
                positionFlashUntil[code] = raceClockSeconds + 5
            }
            lastPosition[code] = row.newPosition
        }
        standings = fresh
    }

    /// Resets position tracking to the current standings with no active flashes -
    /// used whenever the race (re)starts fresh so the starting grid order never
    /// itself counts as a "change".
    private func resetPositionChangeTracking() {
        positionFlashDirection.removeAll()
        positionFlashUntil.removeAll()
        lastPosition.removeAll()
        let fresh = computeStandings()
        for row in fresh {
            lastPosition[row.driver.code] = row.newPosition
        }
        standings = fresh
    }

    /// Recomputes and republishes `standings` - call after anything it
    /// depends on changes (a plan, the race clock) OUTSIDE the tick loop's
    /// own `updatePositionChangeTracking`, which already refreshes it once
    /// per tick.
    private func refreshStandings() {
        standings = computeStandings()
    }

    private func seedStartingGrid() {
        var plans: [String: [PlanStint]] = [:]
        for driver in race.drivers {
            plans[driver.code] = StrategySimulator.realPlan(for: driver)
        }
        editedPlans = plans
        lastUserPitLap = [:]
        pitEventLaps = [:]
        pitDecisionElapsed = [:]
        pendingTyreDecisions = []
        for driver in race.drivers {
            rebuildSchedule(for: driver.code)
        }
    }

    func currentPlan(for code: String) -> [PlanStint] {
        editedPlans[code] ?? []
    }

    /// This driver's own time for `lap`, anchored to their real recorded lap the same
    /// way every other number in the app is: actual seconds + (this plan's prediction
    /// minus the real plan's prediction) for that one lap. Falls back to a raw
    /// prediction if `lap` has no recorded time at all - not expected for any real
    /// lap in the current race.json, which records every lap including lap 1.
    ///
    /// `untouched` (the caller already knows whether this plan matches reality, so
    /// it isn't re-derived per lap) skips both model calls entirely - they'd only
    /// cancel to zero delta anyway - which is what keeps rebuilding a driver nobody
    /// has pitted from costing anything beyond a dictionary lookup per lap.
    private func lapSeconds(plan: [PlanStint], driver: DriverEntry, atLap lap: Int, untouched: Bool) -> Double {
        guard let record = driver.laps.first(where: { $0.lap == lap }) else {
            return StrategySimulator.predictedSeconds(plan: plan, lap: lap, driver: driver, race: race)
        }
        if untouched { return record.seconds }
        let real = StrategySimulator.realPlan(for: driver)
        let new = StrategySimulator.predictedSeconds(plan: plan, lap: lap, driver: driver, race: race)
        let realPred = StrategySimulator.predictedSeconds(plan: real, lap: lap, driver: driver, race: race)
        return record.seconds + (new - realPred)
    }

    /// Rebuilt whenever a plan changes. A pit stop's cost is charged HERE, on the
    /// exact lap the new stint begins - not deferred to the final total - so it
    /// immediately shows up in this driver's live position the moment the stop
    /// happens, the same way it would in a real race.
    ///
    /// It's charged only for the DIFFERENCE from what really happened: `actual`
    /// lap times already have the driver's real pit stops baked in (they're raw,
    /// unfiltered recordings), so re-adding pitLoss at every stop would double
    /// count it for an untouched driver. Every genuine pit event (`pitEventLaps`)
    /// costs +pitLoss at that lap, unconditionally; a real stop that this plan no
    /// longer makes saves -pitLoss at that lap. Net-zero for anyone untouched,
    /// which is what keeps this schedule's final total identical to
    /// `raceTimeAtLap`'s.
    private func rebuildSchedule(for code: String) {
        guard let driver = race.driver(code) else { return }
        let plan = currentPlan(for: code)
        let real = StrategySimulator.realPlan(for: driver)
        let untouched = StrategySimulator.plansMatch(plan, real)
        let events = pitEventLaps[code] ?? []
        let planStops = Set(plan.sorted { $0.startLap < $1.startLap }.dropFirst().map(\.startLap))
        let realStops = Set(real.sorted { $0.startLap < $1.startLap }.dropFirst().map(\.startLap))
        // A retired driver's real data (laps/stints) never goes past the lap
        // they retired on, and their strategy can never be edited (always
        // `untouched`) - so their schedule just stops advancing there instead
        // of falling through to a model prediction for laps that never
        // happened.
        let lastRealLap = driver.isRetired ? driver.lapsCompleted : race.totalLaps

        var cumulative: [Double] = [0]
        var running = 0.0
        for lap in 1...race.totalLaps {
            guard lap <= lastRealLap else {
                cumulative.append(running)
                continue
            }
            var seconds = lapSeconds(plan: plan, driver: driver, atLap: lap, untouched: untouched)
            if events.contains(lap) {
                seconds += race.pitLoss
            } else if realStops.contains(lap) && !planStops.contains(lap) {
                seconds -= race.pitLoss
            }
            running += seconds
            cumulative.append(running)
        }
        schedules[code] = cumulative
    }

    /// This driver's live status at the current race clock: which lap they're on,
    /// how far into it (for the on-screen timer), how much of it is LEFT (for
    /// ordering - see below), plus their anchored cumulative time through the laps
    /// they've actually completed (for the final result).
    ///
    /// `remainingInLap` rather than `elapsedInLap` is what decides who's ahead
    /// between two drivers on the same lap number: raw elapsed time since the lap
    /// started is only comparable when every driver's version of that lap takes the
    /// same time. It doesn't once a pit stop (or just a slower compound) makes one
    /// driver's current lap longer than another's - elapsed time alone would say
    /// they're "even" right up until the pitted driver's much-longer lap finishes,
    /// which is exactly the bug where a pit stop didn't cost any visible position.
    private func liveStatus(for code: String) -> (lapNumber: Int, elapsedInLap: Double, remainingInLap: Double, completedLaps: Int, cumulativeSeconds: Double) {
        guard let schedule = schedules[code], let driver = race.driver(code) else { return (1, 0, 0, 0, 0) }
        let t = raceClockSeconds
        // Once the clock reaches a retired driver's own retirement time, they
        // freeze there (their DNF lap) - the generic "ran out of laps, so show
        // the last one" fallback below would otherwise report them still
        // running the full race distance.
        if driver.isRetired, t >= schedule[driver.lapsCompleted] {
            let lap = driver.lapsCompleted
            return (lap, schedule[lap] - schedule[max(lap - 1, 0)], 0, lap, schedule[lap])
        }
        for lap in 1...race.totalLaps where t < schedule[lap] {
            return (lap, t - schedule[lap - 1], schedule[lap] - t, lap - 1, schedule[lap - 1])
        }
        let lastLap = race.totalLaps
        return (lastLap, schedule[lastLap] - schedule[lastLap - 1], 0, lastLap, schedule[lastLap])
    }

    // MARK: - Starting grid (pre-race only)

    /// Picking a different starting compound is the same kind of decision as a
    /// live pit, just made before lights out instead of mid-race: it throws away
    /// this driver's real strategy entirely, not just their first stint's
    /// compound. The whole plan collapses to one open-ended stint on the new
    /// compound (same shape a lap-0 pit produces), and the user is now on the
    /// hook for every pit stop from here, live - nothing about how reality
    /// actually played out is inherited. A no-op if it's the same compound they
    /// were already on, so re-tapping the current selection doesn't reset anyone
    /// who hasn't actually changed anything.
    func setStartingCompound(_ code: String, compound: String) {
        guard race.driver(code)?.isRetired != true,
              raceClockSeconds <= 0, currentPlan(for: code).first?.compound != compound else { return }
        editedPlans[code] = [PlanStint(compound: compound, startLap: 1, endLap: race.totalLaps)]
        pitEventLaps[code] = [] // no pit HAS happened yet - this is a starting choice, not a stop
        rebuildSchedule(for: code)
        refreshStandings()
    }

    func beginRace() {
        raceConfigured = true
        resetPositionChangeTracking()
    }

    // MARK: - Speed

    /// The forward transport button: steps to the next value in `speedSteps`
    /// (1x -> 2x -> ... -> 10x -> 20x -> ... -> 60x, capped there).
    func increaseSpeed() {
        guard let index = Self.speedSteps.firstIndex(of: speedMultiplier) else { return }
        speedMultiplier = Self.speedSteps[min(index + 1, Self.speedSteps.count - 1)]
    }

    /// The reverse transport button: steps to the previous value in `speedSteps`
    /// (1x -> -1x -> -2x -> ... -> -10x -> -20x -> ... -> -60x, capped there).
    func decreaseSpeed() {
        guard let index = Self.speedSteps.firstIndex(of: speedMultiplier) else { return }
        speedMultiplier = Self.speedSteps[max(index - 1, 0)]
    }

    // MARK: - Live strategy

    /// How many laps this driver has actually completed, at the current race clock -
    /// their own pace, not a shared field lap. Used both to gate/inform pitting and
    /// to display "Lap N" per row.
    func completedLaps(for code: String) -> Int {
        liveStatus(for: code).completedLaps
    }

    /// The set of compounds this driver's CURRENT plan has actually used.
    private func compoundsUsed(_ code: String) -> Set<String> {
        Set(currentPlan(for: code).map(\.compound))
    }

    /// Non-nil (the compound to switch to) if this driver's plan hasn't satisfied
    /// the two-compound rule yet.
    private func neededCompound(for code: String) -> String? {
        let used = compoundsUsed(code)
        guard used.count < 2 else { return nil }
        return (used.first ?? "MEDIUM") == "SOFT" ? "MEDIUM" : "SOFT"
    }

    /// Which lap (this driver's own completed-laps count) they were last manually
    /// pitted on - so a second tap in the same lap is a no-op. Only tracks
    /// user-initiated stops; the mandatory-compound auto-pit bypasses this via
    /// `applyPit` directly, since it's a rule the app enforces, not a repeated
    /// user action.
    private var lastUserPitLap: [String: Int] = [:]

    /// Why `pit(code, ...)` wouldn't currently do anything, in priority order -
    /// nil if it would. Two DIFFERENT reasons look the same from `canPit`
    /// alone (both just "can't pit right now"), so this is what the UI reads
    /// to show the right one instead of always blaming "already pitted".
    enum PitBlockReason {
        /// Already used this lap's one pit - the ordinary once-per-lap rule.
        case alreadyPittedThisLap
        /// This driver's dot has actually passed the pit lane's entrance for
        /// the lap they're on - physically there's nowhere left to divert to.
        /// Resets itself every lap: the instant they cross the start/finish
        /// line, they're back before the entrance again.
        /// `elapsedInLap / totalLapDuration` is exactly the same fraction the
        /// track map places their (non-pitting) dot at, so this lines up with
        /// what's actually on screen.
        case pastPitEntrance
    }

    func pitBlockReason(_ code: String) -> PitBlockReason? {
        guard raceConfigured, !isFinished, raceClockSeconds > 0, race.driver(code)?.isRetired != true else { return nil }
        guard lastUserPitLap[code] != completedLaps(for: code) else { return .alreadyPittedThisLap }
        let status = liveStatus(for: code)
        let totalLapDuration = status.elapsedInLap + status.remainingInLap
        guard totalLapDuration > 0, status.elapsedInLap / totalLapDuration >= Self.pitLaneEntryFraction else { return nil }
        return .pastPitEntrance
    }

    /// Whether `pit(code, ...)` would currently do anything - exposed so the UI
    /// can disable the control instead of silently swallowing the tap.
    func canPit(_ code: String) -> Bool {
        guard raceConfigured, !isFinished, raceClockSeconds > 0, race.driver(code)?.isRetired != true else { return false }
        return pitBlockReason(code) == nil
    }

    /// Driver codes waiting on a forced pit decision - `maxTyreLife` has been
    /// reached for their current tyre and the race is paused until they choose a
    /// compound. Which compound to switch to is a strategic choice, not a rule
    /// with one right answer (unlike the two-compound rule), so the app doesn't
    /// guess on the user's behalf here; it stops and waits. ContentView watches
    /// this and presents that driver's card, undismissable until they pit.
    @Published private(set) var pendingTyreDecisions: [String] = []

    /// Keeps every stint (or part of a stint) this driver has actually completed
    /// untouched, then replaces everything from here on with a single new stint on
    /// `newCompound`. A driver never pitted this way just keeps playing out their
    /// real remaining stints, which is what makes "never intervene" reproduce
    /// the real result exactly. Can be called the instant the race starts (lap 0
    /// completed) - reacting to the very first lap shouldn't be blocked. At most
    /// once per lap - a pit stop takes the whole lap, there's no boxing twice
    /// before the next one starts.
    func pit(_ code: String, newCompound: String) {
        guard canPit(code) else { return }
        applyPit(code, newCompound: newCompound)
        lastUserPitLap[code] = completedLaps(for: code)
        pendingTyreDecisions.removeAll { $0 == code }
        refreshStandings()
    }

    /// The actual trim-and-replace, with none of `pit()`'s user-facing guards -
    /// used by the mandatory-compound-rule enforcement, which must still be able to
    /// act exactly at the moment the race (or a skip-to-end) finishes.
    private func applyPit(_ code: String, newCompound: String) {
        guard let plan = editedPlans[code] else { return }
        // Clamped so the new trailing stint always has room for at least the last
        // lap, even if this fires exactly as a driver crosses the finish line.
        let lap = min(completedLaps(for: code), race.totalLaps - 1)
        // Wherever this driver physically is on the lap they're about to pit
        // on, RIGHT NOW, before anything about their plan/schedule changes -
        // the track map's pit-lane visual anchors to this instead of the
        // pit lane's fixed geometric entrance, so a stop called for late in a
        // lap (after that fixed point) doesn't snap the dot backward to it.
        // Read back via `pitLaneTiming(for:pitLoss:decision:)` into
        // `StandingRow.pitEntryProgress`/`pitLaneStartT`.
        pitDecisionElapsed[code] = (lap: lap + 1, seconds: liveStatus(for: code).elapsedInLap)
        let sorted = plan.sorted { $0.startLap < $1.startLap }

        var kept: [PlanStint] = []
        for stint in sorted {
            guard stint.startLap <= lap else { break }
            if stint.endLap <= lap {
                kept.append(stint)
            } else {
                var trimmed = stint
                trimmed.endLap = lap
                kept.append(trimmed)
                break
            }
        }
        kept.append(PlanStint(compound: newCompound, startLap: lap + 1, endLap: race.totalLaps))
        editedPlans[code] = kept
        pitEventLaps[code, default: []].insert(lap + 1)
        rebuildSchedule(for: code)
    }

    // MARK: - Playback

    private var finishTime: Double {
        schedules.values.compactMap(\.last).max() ?? 0
    }

    /// Bumped by every pause() and play(), so a loop from a previous play() call
    /// recognises it's been superseded and stops - relying on `isPlaying` alone isn't
    /// enough, since a pause() immediately followed by a play() flips it back to true
    /// before the old (still-sleeping) loop wakes up to check it.
    private var playbackGeneration = 0

    func play() {
        guard raceConfigured, !isPlaying else { return }
        // Nothing to do if already sitting at the boundary in the direction we'd move.
        if speedMultiplier > 0 && isFinished { return }
        if speedMultiplier < 0 && raceClockSeconds <= 0 { return }

        isPlaying = true
        playbackGeneration += 1
        let generation = playbackGeneration
        Task {
            var lastTick = Date()
            while isPlaying && playbackGeneration == generation {
                try? await Task.sleep(nanoseconds: UInt64(tickInterval * 1_000_000_000))
                guard isPlaying, playbackGeneration == generation else { return }

                let now = Date()
                let wallDelta = now.timeIntervalSince(lastTick)
                lastTick = now

                raceClockSeconds += wallDelta * Double(speedMultiplier) // read fresh every tick
                enforceHardCaps(interactive: true)
                updatePositionChangeTracking()

                if raceClockSeconds <= 0 {
                    raceClockSeconds = 0
                    break
                }
                let finish = finishTime
                if finish > 0 && raceClockSeconds >= finish {
                    raceClockSeconds = finish
                    break
                }
            }
            if playbackGeneration == generation {
                isPlaying = false
            }
        }
    }

    func pause() {
        isPlaying = false
        playbackGeneration += 1
    }

    /// F1 requires two distinct dry compounds. A driver who reaches their final lap
    /// still on one compound (because the user pitted them onto the same tyre twice,
    /// or never pitted a driver whose starting-grid pick got changed to just one)
    /// gets boxed for whatever they're missing automatically, so the result never
    /// reports an illegal one-compound strategy.
    private func enforceMandatoryCompoundRule() {
        for driver in race.drivers {
            guard !driver.isRetired,
                  completedLaps(for: driver.code) >= race.totalLaps - 1,
                  let needed = neededCompound(for: driver.code) else { continue }
            applyPit(driver.code, newCompound: needed)
        }
    }

    /// `maxTyreLife` isn't a modelling choice - it's the oldest tyre age any driver
    /// ever ran at Barcelona, because real strategists always pit before the wear
    /// gets that bad. Past it, the model has zero examples to have learned from, so
    /// its (linear) prediction is a straight line drawn through data that doesn't
    /// exist - not degradation, just an unconstrained guess. A strategy is never
    /// allowed to exceed that age; which compound to switch to afterwards is a
    /// judgment call, though, so this only queues the decision - `pause()` and
    /// `pendingTyreDecisions` - rather than picking one, in the interactive path.
    /// The non-interactive path (skip-to-end, scripted jumps) has no one present to
    /// ask, so it still resolves automatically there.
    private func enforceMaxTyreLife(interactive: Bool) {
        for driver in race.drivers {
            guard !driver.isRetired, let stint = currentPlan(for: driver.code).last else { continue }
            let age = completedLaps(for: driver.code) - stint.startLap + 1
            guard let maxLife = race.maxTyreLife[stint.compound], age >= maxLife else { continue }

            if interactive {
                guard !pendingTyreDecisions.contains(driver.code) else { continue }
                pendingTyreDecisions.append(driver.code)
            } else {
                let alternate = stint.compound == "SOFT" ? "MEDIUM" : "SOFT"
                applyPit(driver.code, newCompound: alternate)
            }
        }
        if interactive && !pendingTyreDecisions.isEmpty {
            pause()
        }
    }

    private func enforceHardCaps(interactive: Bool) {
        enforceMandatoryCompoundRule()
        enforceMaxTyreLife(interactive: interactive)
    }

    func skipToEnd() {
        pause()
        raceClockSeconds = finishTime
        enforceHardCaps(interactive: false)
        refreshStandings()
    }

    /// Resets to the pre-lights-out state: clears every live decision and
    /// re-seeds default starting compounds, so the user can plan a fresh run -
    /// same screen throughout, just rewound to before the green flag.
    func backToGrid() {
        pause()
        raceClockSeconds = 0
        speedMultiplier = 1
        seedStartingGrid()
        resetPositionChangeTracking()
    }

    // MARK: - Scenario testing

    /// Jumps the race clock directly to the instant `code` has completed exactly
    /// `lap` laps under their CURRENT plan - skips the real-time wait entirely, so
    /// a reproducible "what-if" scenario (a scripted sequence of pits at specific
    /// lap numbers) can be run and inspected in milliseconds instead of by playing
    /// the race out and watching. Runs the same hard-cap enforcement `play()`
    /// would along the way - a scripted scenario can't accidentally exceed the
    /// caps just because it skips ahead in one jump instead of ticking through.
    @discardableResult
    func debugAdvance(_ code: String, toCompletedLaps lap: Int) -> Bool {
        guard raceConfigured, let schedule = schedules[code], lap >= 0, lap <= race.totalLaps else { return false }
        pause()
        raceClockSeconds = min(schedule[lap] + 0.001, finishTime)
        enforceHardCaps(interactive: false)
        refreshStandings()
        return true
    }

    /// This driver's tyre age (laps on the current set) at the current race clock -
    /// the same number `PitControlView`'s tyre-life warning is based on, exposed so
    /// a scenario script can report it at each checkpoint without duplicating the
    /// warning's logic.
    func currentTyreAge(for code: String) -> (compound: String, age: Int)? {
        guard let stint = currentPlan(for: code).last else { return nil }
        return (stint.compound, completedLaps(for: code) - stint.startLap + 1)
    }

    // MARK: - Standings

    private struct StandingsEntry {
        let driver: DriverEntry
        let lapNumber: Int
        let elapsedInLap: Double
        let remainingInLap: Double
        let completedLaps: Int
        let simulatedTotal: Double
        let currentCompound: String
        let isPitLap: Bool
    }

    /// Recomputed and cached into `standings` explicitly, rather than left as
    /// a plain computed property - every view that used to read `standings`
    /// (the track map, the leaderboard, the lap counter) triggered its OWN
    /// full recomputation, so a single SwiftUI render pass was silently
    /// redoing this same per-driver work 3-4 times over, on top of once more
    /// inside the tick loop's own position-change bookkeeping. At the higher
    /// tick rate a fast multiplier uses, that redundancy was enough main-
    /// thread work to visibly stutter - not just the track dots, but simple
    /// text like the clock, since everything shares the same thread.
    private func computeStandings() -> [StandingRow] {
        let entries: [StandingsEntry] = race.drivers.map { driver in
            let plan = currentPlan(for: driver.code)
            let status = liveStatus(for: driver.code)
            let total = StrategySimulator.raceTimeAtLap(newPlan: plan, driver: driver, race: race, upToLap: status.completedLaps)
            // The stint actually covering the lap they're on right now - not just
            // the plan's last stint, which would be wrong for anyone still early
            // in a multi-stint plan (their real one, untouched, included).
            let compound = plan.first { $0.startLap <= status.lapNumber && status.lapNumber <= $0.endLap }?.compound
                ?? plan.last?.compound ?? "MEDIUM"
            // A stint literally starting on this lap IS a pit lap - whether it
            // came from a live pit, a hard-cap auto-pit, or simply from this
            // driver's own real, untouched multi-stint plan (the pit-lane
            // visual shouldn't only play for drivers the user has personally
            // intervened on). Lap 1 needs an extra check: a stint starting
            // there is structurally IDENTICAL whether it's a genuine live pit
            // taken during lap 1, or just a pre-race starting-compound pick
            // (no pit at all) - `pitEventLaps` is what actually happened
            // (applyPit records it; a starting-compound pick explicitly
            // clears it), so it's what disambiguates the two. Getting this
            // wrong for lap 1 specifically used to send a lap-1 live pit down
            // the plain (non-pit-lane) position formula, which - since that
            // formula divides by the lap's now-inflated total duration -
            // reintroduced the exact backward-snap the pit-lane math exists
            // to prevent.
            let isPitLap = plan.contains { stint in
                stint.startLap == status.lapNumber
                    && (stint.startLap > 1 || pitEventLaps[driver.code]?.contains(stint.startLap) == true)
            }
            return StandingsEntry(driver: driver, lapNumber: status.lapNumber, elapsedInLap: status.elapsedInLap, remainingInLap: status.remainingInLap, completedLaps: status.completedLaps, simulatedTotal: total, currentCompound: compound, isPitLap: isPitLap)
        }

        // Further along wins: more completed laps first; once everyone has finished
        // every lap, the anchored total decides; otherwise, whoever needs LESS time
        // left to finish the lap they're both on is ahead - not whoever has more
        // raw elapsed time in it, which breaks down the moment one of them is on a
        // longer lap than the other (a pit stop, a slower compound).
        let sorted = entries.sorted { a, b in
            if a.completedLaps != b.completedLaps { return a.completedLaps > b.completedLaps }
            if a.completedLaps >= race.totalLaps { return a.simulatedTotal < b.simulatedTotal }
            return a.remainingInLap < b.remainingInLap
        }
        let leaderTotal = sorted.first?.simulatedTotal ?? 0

        return sorted.enumerated().map { index, entry in
            // Everything pit-lane-related for this row, computed once so the
            // pieces (`pitMainPortion`, `pitEntryProgress`, `pitLaneStartT`,
            // `isCurrentlyPitting`) can't drift out of sync with each other.
            let pit = Self.pitLaneTiming(
                for: entry,
                pitLoss: race.pitLoss,
                decision: pitDecisionElapsed[entry.driver.code]
            )

            return StandingRow(
                driver: entry.driver,
                simulatedTotal: entry.simulatedTotal,
                newPosition: index + 1,
                gapToLeader: entry.simulatedTotal - leaderTotal,
                neededCompoundWarning: (isFinished || entry.driver.isRetired) ? nil : neededCompound(for: entry.driver.code),
                lapNumber: entry.lapNumber,
                lapElapsedSeconds: entry.elapsedInLap,
                lapProgress: min(max(entry.elapsedInLap / max(entry.elapsedInLap + entry.remainingInLap, 0.0001), 0), 1),
                recentPositionChange: (positionFlashUntil[entry.driver.code].map { $0 > raceClockSeconds } == true)
                    ? positionFlashDirection[entry.driver.code]
                    : nil,
                isPitLap: entry.isPitLap,
                pitMainPortion: pit.mainPortion,
                pitEntryProgress: pit.entryProgress,
                pitLaneStartT: pit.laneStartT,
                currentCompound: entry.currentCompound,
                hasRetiredYet: entry.driver.isRetired && entry.completedLaps >= entry.driver.lapsCompleted,
                isCurrentlyPitting: pit.isCurrentlyPitting
            )
        }
    }

    private struct PitTiming {
        let mainPortion: Double
        let entryProgress: Double
        let laneStartT: Double
        let isCurrentlyPitting: Bool
    }

    /// Works out, for one pit lap, everything the track map and leaderboard
    /// need to place a driver relative to the pit lane - anchored to where
    /// they actually were the moment the stop was decided (`decision`) rather
    /// than always the fixed geometric entrance, so a stop called for late in
    /// the lap doesn't have to snap the dot backward to reach it. A real,
    /// untouched multi-stint driver has no `decision` at all (their stop was
    /// never "called" mid-lap - it's just how the lap starts), so they always
    /// get the fixed entrance, same as before this existed.
    ///
    /// Only two phases, not three: normal driving up to the pit entrance,
    /// then the pit lane the rest of the way to the end of the lap. There
    /// used to be a third "driving normally again, from the pit exit back to
    /// the line" phase, left over from when the drawn pit lane stopped short
    /// of the start/finish line - now that its exit IS that line, that phase
    /// would have zero track distance to cover but still a real chunk of time
    /// (`normalSeconds` doesn't know or care how the lap's distance is split
    /// between "before the entrance" and "after the exit"), so the dot would
    /// reach the line and then just sit frozen there until the leftover time
    /// ran out. Folding that leftover time into the dwell instead means the
    /// stop takes visibly longer (a real pit lane isn't a quick in-and-out
    /// either) and the dot is still moving, all the way to the line.
    private static func pitLaneTiming(
        for entry: StandingsEntry,
        pitLoss: Double,
        decision: (lap: Int, seconds: Double)?
    ) -> PitTiming {
        guard entry.isPitLap else { return PitTiming(mainPortion: 1.0, entryProgress: 1.0, laneStartT: 0, isCurrentlyPitting: false) }

        let totalLapDuration = entry.elapsedInLap + entry.remainingInLap
        guard totalLapDuration > 0 else { return PitTiming(mainPortion: 1.0, entryProgress: 1.0, laneStartT: 0, isCurrentlyPitting: false) }

        let m = min(max((totalLapDuration - pitLoss) / totalLapDuration, 0.0001), 0.999)
        let normalSeconds = max(totalLapDuration - pitLoss, 0.0001)

        let geometricEntrySeconds = pitLaneEntryFraction * normalSeconds
        let decisionSeconds = (decision?.lap == entry.lapNumber) ? decision!.seconds : 0
        // Must leave at least a sliver of dwell time even for a click called
        // right as the lap ends.
        let effectiveEntrySeconds = min(max(geometricEntrySeconds, decisionSeconds), totalLapDuration - 0.001)

        let entryProgress = effectiveEntrySeconds / totalLapDuration
        let effectiveEntryFraction = effectiveEntrySeconds / normalSeconds
        let span = max(pitLaneExitFraction - pitLaneEntryFraction, 0.0001)
        let laneStartT = min(max((effectiveEntryFraction - pitLaneEntryFraction) / span, 0), 1)

        let lapProgress = min(max(entry.elapsedInLap / totalLapDuration, 0), 1)
        let isCurrentlyPitting = lapProgress > entryProgress

        return PitTiming(mainPortion: m, entryProgress: entryProgress, laneStartT: laneStartT, isCurrentlyPitting: isCurrentlyPitting)
    }
}
