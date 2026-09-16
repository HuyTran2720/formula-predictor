//
//  ScenarioTests.swift
//  FormulaGenieTests
//
//  A permanent way to run "what if" strategy scenarios and inspect the result
//  without touching the UI. `runScenario` is the reusable primitive - it takes
//  a scripted sequence of pit stops (driver, lap, compound) and a list of laps
//  to check in on, and reports position/gap/tyre age at each one, using
//  RaceStore.debugAdvance to jump straight there instead of playing it out.
//
//  Add a new test method per scenario you want on record; call `runScenario`
//  directly (or drive RaceStore's public API yourself) for anything ad hoc.
//

import XCTest
@testable import FormulaGenie

@MainActor
final class ScenarioTests: XCTestCase {

    struct PitCall {
        let driver: String
        let atCompletedLaps: Int
        let compound: String
    }

    struct Checkpoint {
        let lap: Int
        let position: Int
        let gapToLeader: Double
        let lapTimeSeconds: Double
        let tyreCompound: String?
        let tyreAge: Int?
    }

    /// Runs `driver`'s race with `pitCalls` applied at the specified lap counts
    /// (in order), then reports their standing at every lap in `checkpoints`.
    /// Every other driver is left untouched (their real historical strategy).
    @discardableResult
    func runScenario(driver: String, pitCalls: [PitCall], checkpoints: [Int]) -> [Checkpoint] {
        let store = RaceStore()
        store.beginRace()

        for call in pitCalls {
            XCTAssertTrue(
                store.debugAdvance(call.driver, toCompletedLaps: call.atCompletedLaps),
                "couldn't advance \(call.driver) to lap \(call.atCompletedLaps)"
            )
            store.pit(call.driver, newCompound: call.compound)
        }

        var results: [Checkpoint] = []
        for lap in checkpoints {
            XCTAssertTrue(store.debugAdvance(driver, toCompletedLaps: lap), "couldn't advance to lap \(lap)")
            guard let row = store.standings.first(where: { $0.driver.code == driver }) else {
                XCTFail("no standings row for \(driver)")
                continue
            }
            let tyre = store.currentTyreAge(for: driver)
            results.append(Checkpoint(
                lap: lap,
                position: row.newPosition,
                gapToLeader: row.gapToLeader,
                lapTimeSeconds: row.lapElapsedSeconds,
                tyreCompound: tyre?.compound,
                tyreAge: tyre?.age
            ))
        }
        return results
    }

    /// Same idea, but runs to the actual end of the race and returns the final row.
    func runScenarioToFinish(driver: String, pitCalls: [PitCall]) -> StandingRow? {
        let store = RaceStore()
        store.beginRace()
        for call in pitCalls {
            store.debugAdvance(call.driver, toCompletedLaps: call.atCompletedLaps)
            store.pit(call.driver, newCompound: call.compound)
        }
        store.skipToEnd()
        return store.standings.first { $0.driver.code == driver }
    }

    private func printReport(_ label: String, _ checkpoints: [Checkpoint]) {
        print("\n--- \(label) ---")
        print("lap  pos  gap      lapTime  tyre")
        for c in checkpoints {
            let tyre = c.tyreCompound.map { "\($0) age \(c.tyreAge ?? -1)" } ?? "-"
            print(String(format: "%3d  %3d  %+7.2f  %7.3f  %@", c.lap, c.position, c.gapToLeader, c.lapTimeSeconds, tyre))
        }
    }

    // MARK: - Starting grid

    /// Picking a different starting compound must discard the driver's real
    /// strategy entirely - the whole plan collapses to one open stint, same shape
    /// as an early live pit - and put them in the simulation model (their times
    /// are now calculated by the model, not replayed from the recording). Picking
    /// the SAME compound they already had must be a no-op.
    func testChangingStartingCompoundEntersSimulationModel() {
        let store = RaceStore()
        guard let driver = store.race.driver("PIA") else { return XCTFail("no PIA in race.json") }
        let real = StrategySimulator.realPlan(for: driver)
        let sameCompound = real.first!.compound
        let otherCompound = sameCompound == "SOFT" ? "MEDIUM" : "SOFT"

        store.setStartingCompound("PIA", compound: sameCompound)
        XCTAssertTrue(StrategySimulator.plansMatch(store.currentPlan(for: "PIA"), real), "re-picking the same compound must stay untouched")

        store.setStartingCompound("PIA", compound: otherCompound)
        let plan = store.currentPlan(for: "PIA")
        XCTAssertFalse(StrategySimulator.plansMatch(plan, real), "expected this driver to now be in the simulation model")
        XCTAssertEqual(plan.count, 1, "expected the real multi-stint plan to collapse to a single stint")
        XCTAssertEqual(plan.first?.compound, otherCompound)
        XCTAssertEqual(plan.first?.startLap, 1)
        XCTAssertEqual(plan.first?.endLap, store.race.totalLaps)
    }

    /// The user's exact report: change PIA's starting compound, start the race,
    /// play through - does the hard cap actually still fire, given the plan came
    /// from `setStartingCompound` rather than a live `pit()`? `enforceMaxTyreLife`
    /// doesn't care how a plan got to be what it is, only what it currently is, so
    /// this should already work - this test is here specifically to CONFIRM that
    /// rather than assume it.
    func testStartingCompoundChangeStillTriggersTyreCapDuringLivePlay() async throws {
        let store = RaceStore()
        guard let driver = store.race.driver("PIA") else { return XCTFail("no PIA in race.json") }
        let realFirst = StrategySimulator.realPlan(for: driver).first!.compound
        let newCompound = realFirst == "SOFT" ? "MEDIUM" : "SOFT"
        let maxLife = store.race.maxTyreLife[newCompound] ?? 27

        store.setStartingCompound("PIA", compound: newCompound)
        store.beginRace()

        // Setup only: jump to one lap before the cap, then play for real across it.
        store.debugAdvance("PIA", toCompletedLaps: maxLife - 1)
        XCTAssertTrue(store.pendingTyreDecisions.isEmpty, "shouldn't be pending yet, one lap early")

        for _ in 0..<12 { store.increaseSpeed() } // 60x, so the wait is short
        store.play()

        let deadline = Date().addingTimeInterval(5)
        while store.pendingTyreDecisions.isEmpty && Date() < deadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        XCTAssertEqual(store.pendingTyreDecisions, ["PIA"], "expected the cap to fire even for a plan that started from setStartingCompound")
        XCTAssertFalse(store.isPlaying, "play() should have paused for the decision")
        if let tyre = store.currentTyreAge(for: "PIA") {
            XCTAssertEqual(tyre.compound, newCompound)
            XCTAssertLessThanOrEqual(tyre.age, maxLife, "the cap must hold exactly, not just eventually")
        } else {
            XCTFail("expected tyre info for PIA")
        }
    }

    /// The display half of the same report: right after changing the starting
    /// compound (before any laps happen), the stint breakdown must show the open
    /// stint ending at the model's trained limit for that compound - not
    /// `race.totalLaps`, which is just how an "open, not yet closed by anything"
    /// stint happens to be stored internally. Showing the raw stored value reads
    /// as "the model thinks this tyre lasts the whole race," which isn't true.
    func testOpenStintDisplaysProjectedEndLapNotRaceLength() {
        let store = RaceStore()
        guard let driver = store.race.driver("PIA") else { return XCTFail("no PIA in race.json") }
        let realFirst = StrategySimulator.realPlan(for: driver).first!.compound
        let newCompound = realFirst == "SOFT" ? "MEDIUM" : "SOFT"
        let maxLife = store.race.maxTyreLife[newCompound] ?? 27

        store.setStartingCompound("PIA", compound: newCompound)
        XCTAssertEqual(store.currentPlan(for: "PIA").first?.endLap, store.race.totalLaps, "the STORED plan should still be open-ended - only the display is capped")

        let breakdown = StrategySimulator.stintBreakdown(newPlan: store.currentPlan(for: "PIA"), driver: driver, race: store.race)
        XCTAssertEqual(breakdown.stints.count, 1)
        XCTAssertEqual(breakdown.stints.first?.stint.startLap, 1)
        XCTAssertEqual(breakdown.stints.first?.stint.endLap, maxLife, "expected the displayed range to end at the trained limit, not race length")
    }

    // MARK: - Recorded scenarios

    /// Piastri's real strategy is a 3-stop (SOFT 1-22, MEDIUM 23-49, SOFT 50-55,
    /// SOFT 56-66). This tries an unorthodox 2-stop instead, with both stops
    /// stacked early (lap 8 and lap 16) and no third stop - so the final stint
    /// runs SOFT from lap 17 - with no third stop, that tyre would otherwise run
    /// to lap 66: 50 laps on one set, against a trained maximum of 27
    /// (race.json's maxTyreLife). This is the scenario that originally surfaced
    /// the tyre-degradation extrapolation cliff (Piastri ran as high as P1 around
    /// half-distance, then collapsed as the linear model's constant degradation
    /// rate kept compounding past any range it was trained on) - which is exactly
    /// why RaceStore now force-pits a driver the instant their tyre would exceed
    /// maxTyreLife. This test now asserts THAT: the cap holds, so the fabricated
    /// collapse can no longer happen even under this deliberately unorthodox
    /// strategy, and the auto-pit lands the driver on a plausible final result.
    func testPiastriUnorthodoxTwoStopBothStopsEarly() {
        let checkpoints = runScenario(
            driver: "PIA",
            pitCalls: [
                PitCall(driver: "PIA", atCompletedLaps: 8, compound: "MEDIUM"),
                PitCall(driver: "PIA", atCompletedLaps: 16, compound: "SOFT"),
            ],
            checkpoints: [20, 30, 40, 45, 50, 55, 60, 65, 66]
        )
        printReport("PIA 2-stop, both stops early (hard cap enforced)", checkpoints)

        // The hard cap must hold at every checkpoint - the whole point of it.
        for c in checkpoints {
            guard let age = c.tyreAge, let compound = c.tyreCompound,
                  let maxLife = RaceData.loadBundled().maxTyreLife[compound] else { continue }
            XCTAssertLessThanOrEqual(age, maxLife, "lap \(c.lap): \(compound) age \(age) exceeded the cap of \(maxLife)")
        }

        // And with the fabricated cliff removed, no wild swing to the back either.
        let worstPosition = checkpoints.map(\.position).max() ?? 99
        XCTAssertLessThanOrEqual(worstPosition, 5, "expected no catastrophic late collapse now the cap is enforced")
    }

    /// Confirms the tyre-cap enforcement's INTERACTIVE path specifically - i.e. what
    /// actually happens during live play(), not a scripted debugAdvance jump. The
    /// app must pause and queue a decision for the user rather than silently
    /// picking a compound, and the tyre's age must never be allowed past the cap
    /// while it waits.
    func testTyreCapPausesForDecisionDuringLivePlay() async throws {
        let store = RaceStore()
        store.beginRace()

        // Get PIA to one lap before their SOFT cap via a scripted jump (setup, not
        // what's under test), then switch to real play() for the actual approach.
        let maxSoft = store.race.maxTyreLife["SOFT"] ?? 27
        store.debugAdvance("PIA", toCompletedLaps: 0)
        store.pit("PIA", newCompound: "SOFT") // single SOFT stint, no more stops planned
        store.debugAdvance("PIA", toCompletedLaps: maxSoft - 1)
        XCTAssertTrue(store.pendingTyreDecisions.isEmpty, "shouldn't be pending yet, one lap early")

        for _ in 0..<12 { store.increaseSpeed() } // max out at 60x so the wait is short
        store.play()

        let deadline = Date().addingTimeInterval(5)
        while store.pendingTyreDecisions.isEmpty && Date() < deadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        XCTAssertEqual(store.pendingTyreDecisions, ["PIA"], "expected PIA queued for a forced decision")
        XCTAssertFalse(store.isPlaying, "play() should have paused itself for the decision")

        // The cap held exactly - never exceeded, not even transiently.
        if let tyre = store.currentTyreAge(for: "PIA") {
            XCTAssertEqual(tyre.compound, "SOFT")
            XCTAssertLessThanOrEqual(tyre.age, maxSoft)
        } else {
            XCTFail("expected tyre info for PIA")
        }

        // Resolving it (what the forced card's PitControlView does) clears the queue.
        store.pit("PIA", newCompound: "MEDIUM")
        XCTAssertTrue(store.pendingTyreDecisions.isEmpty)
        XCTAssertEqual(store.currentTyreAge(for: "PIA")?.compound, "MEDIUM")
    }

    /// Confirms the two-compound rule specifically - unlike the tyre-cap rule, this
    /// one still auto-resolves even during live play, because "which compound"
    /// isn't a judgment call here: there's exactly one still-legal answer (whatever
    /// they haven't used yet). Keeps PIA on SOFT the whole race, re-pitting onto
    /// SOFT again every 20 laps purely to keep tyre age low - so the tyre-cap rule
    /// never fires, and only the compound rule is under test. With 2 laps to go
    /// they must still be single-compound; with exactly 1 lap remaining the forced
    /// stop must have already happened, and it must cover only that last lap.
    func testMandatoryCompoundRuleAutoBoxesWithOneLapRemaining() {
        let store = RaceStore()
        store.beginRace()

        store.debugAdvance("PIA", toCompletedLaps: 0)
        store.pit("PIA", newCompound: "SOFT")
        for lap in stride(from: 20, to: 60, by: 20) {
            store.debugAdvance("PIA", toCompletedLaps: lap)
            store.pit("PIA", newCompound: "SOFT")
        }

        let totalLaps = store.race.totalLaps

        store.debugAdvance("PIA", toCompletedLaps: totalLaps - 2)
        XCTAssertEqual(Set(store.currentPlan(for: "PIA").map(\.compound)), ["SOFT"], "shouldn't be forced yet, 2 laps early")

        store.debugAdvance("PIA", toCompletedLaps: totalLaps - 1)
        let finalPlan = store.currentPlan(for: "PIA").sorted { $0.startLap < $1.startLap }
        XCTAssertEqual(Set(finalPlan.map(\.compound)), ["SOFT", "MEDIUM"], "expected the mandatory stop with exactly 1 lap remaining")
        XCTAssertEqual(finalPlan.last?.compound, "MEDIUM")
        XCTAssertEqual(finalPlan.last?.startLap, totalLaps, "the forced stop should cover only the final lap")
        XCTAssertEqual(finalPlan.last?.endLap, totalLaps)
        XCTAssertTrue(store.pendingTyreDecisions.isEmpty, "the compound rule must not go through the interactive queue")
    }

    /// Baseline sanity check the other scenario compares against: an UNTOUCHED
    /// driver must reproduce the real result exactly (the anchored-delta design's
    /// core guarantee). If this ever fails, something in RaceStore's schedule or
    /// standings math has regressed.
    func testUntouchedDriverMatchesRealResultExactly() {
        let store = RaceStore()
        store.beginRace()
        store.skipToEnd()
        for driver in store.race.drivers {
            guard let row = store.standings.first(where: { $0.driver.code == driver.code }) else {
                XCTFail("missing row for \(driver.code)")
                continue
            }
            XCTAssertEqual(row.simulatedTotal, driver.actualTotal, accuracy: 0.001, "\(driver.code) total drifted from reality")
            XCTAssertEqual(row.newPosition, driver.actualPosition, "\(driver.code) position drifted from reality")
        }
    }
}
