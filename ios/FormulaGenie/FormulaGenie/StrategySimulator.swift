//
//  StrategySimulator.swift
//  FormulaGenie
//
//  The anchored-delta simulator, per F1-Handoff.md. No UI code lives here.
//
//  The model has a systematic bias on Barcelona 2025 (it's held out, and this tyre
//  generation appears nowhere in training). Summing raw predictions would accumulate
//  that bias into tens of seconds of nonsense. Every function below only ever
//  reports a DIFFERENCE between two predictions of the same lap - the bias is in
//  both terms, so it cancels. Never call LapTimeModel.predict() and show the raw
//  result as if it were a real lap time.
//
//  Every driver is in exactly one of two modes at any moment, decided purely by
//  whether their current plan still matches history (`plansMatch`):
//    - untouched: their plan is byte-for-byte their real one. Lap times are just
//      the real recorded seconds - the model is never even called, because every
//      prediction would cancel to zero delta against itself anyway.
//    - the SIMULATION MODEL: the instant a plan diverges from history - a live
//      pit, or a different starting compound - every lap time from that point on
//      is calculated by the ML model (anchored to the real recording, but no
//      longer identical to it). There's no third state and no partial version of
//      this: one changed stint puts the whole rest of that driver's race through
//      the model.
//

import Foundation

/// A user-editable stint. A `[PlanStint]`, in lap order, is "a strategy."
struct PlanStint: Identifiable, Equatable {
    let id = UUID()
    var compound: String
    var startLap: Int
    var endLap: Int

    var length: Int { endLap - startLap + 1 }
}

enum StrategySimulator {

    // MARK: - Plans

    static func tyreLife(ofLap lap: Int, in stint: PlanStint) -> Int {
        lap - stint.startLap + 1
    }

    /// The starting point for the editor: the driver's real plan, straight from race.json.
    static func realPlan(for driver: DriverEntry) -> [PlanStint] {
        driver.stints.map {
            PlanStint(compound: $0.compound, startLap: $0.startLap, endLap: $0.endLap)
        }
    }

    /// Structural equality ignoring `id` (every PlanStint gets a fresh UUID, so two
    /// stint lists describing the identical strategy are never `==`). This is what
    /// lets every hot path below skip the model entirely for a driver nobody has
    /// touched: their plan is byte-for-byte their real one, so every prediction
    /// would just cancel against itself anyway (new == realPred for every lap).
    static func plansMatch(_ a: [PlanStint], _ b: [PlanStint]) -> Bool {
        guard a.count == b.count else { return false }
        return zip(a, b).allSatisfy {
            $0.compound == $1.compound && $0.startLap == $1.startLap && $0.endLap == $1.endLap
        }
    }

    private static func stint(in plan: [PlanStint], containing lap: Int) -> PlanStint? {
        plan.first { lap >= $0.startLap && lap <= $0.endLap }
    }

    /// Where a stint would honestly be projected to end: never past the model's
    /// trained tyre-age limit for its compound, regardless of what `endLap` is
    /// actually stored as. A still-open stint (the last one in a live plan) is
    /// stored with `endLap == race.totalLaps` until something closes it - a live
    /// pit, or the hard cap firing - so left uncapped, anything reading it
    /// straight would show (and, worse, predict lap times for) laps the tyre will
    /// never actually reach. A closed stint's real endLap is already within the
    /// cap by construction, so this is a no-op for anything but the open one.
    static func projectedEndLap(_ stint: PlanStint, race: RaceData) -> Int {
        guard let maxLife = race.maxTyreLife[stint.compound] else { return stint.endLap }
        return min(stint.endLap, stint.startLap + maxLife - 1)
    }

    // MARK: - Prediction

    /// Every hypothetical lap in the app goes through this one function, which in turn
    /// goes through LapTimeModel.features(). Never build a feature dictionary any other
    /// way - see the header comment above and F1-Handoff.md's "prediction contract."
    static func predictedSeconds(plan: [PlanStint], lap: Int, driver: DriverEntry, race: RaceData) -> Double {
        guard let stint = stint(in: plan, containing: lap) else {
            fatalError("lap \(lap) is not covered by any stint - the live plan should always run start-to-finish")
        }
        let age = tyreLife(ofLap: lap, in: stint)
        let features = LapTimeModel.features(
            lapNumber: Double(lap),
            tyreLife: Double(age),
            compound: stint.compound,
            driver: driver.code,
            teamYear: driver.teamYear,
            airTemp: race.airTemp,
            trackTemp: race.trackTemp
        )
        return try! LapTimeModel.predict(features)
    }

    // MARK: - Anchored deltas

    static func stopsDelta(newPlan: [PlanStint], driver: DriverEntry) -> Int {
        (newPlan.count - 1) - (driver.stints.count - 1)
    }

    // MARK: - Lap-by-lap replay

    /// How many pit stops a plan has made by the end of `lap` (the first stint is a
    /// starting choice, not a stop, so it never counts).
    static func stopsSoFar(plan: [PlanStint], upToLap lap: Int) -> Int {
        let sorted = plan.sorted { $0.startLap < $1.startLap }
        guard sorted.count > 1 else { return 0 }
        return sorted.dropFirst().filter { $0.startLap <= lap }.count
    }

    /// Same anchored-delta idea as `simulatedTotal`, but truncated to laps raced so far -
    /// this is what makes a lap-by-lap replay possible without a second kind of arithmetic.
    /// A pit stop's cost is charged the moment it happens (its startLap), not spread out,
    /// which is also why this reduces to exactly `simulatedTotal` at `upToLap == totalLaps`:
    /// every lap has been summed and every stop this plan will ever make has happened.
    static func raceTimeAtLap(newPlan: [PlanStint], driver: DriverEntry, race: RaceData, upToLap lap: Int) -> Double {
        let real = realPlan(for: driver)

        // Untouched: every delta below would cancel to zero anyway (new == realPred
        // for identical stints), so skip the ~2 model calls per lap entirely. This
        // is the hot path - called for every driver on every tick - and most
        // drivers in a typical session are never touched at all.
        if plansMatch(newPlan, real) {
            return driver.laps.reduce(0.0) { $1.lap <= lap ? $0 + $1.seconds : $0 }
        }

        var actualSum = 0.0
        var deltaSum = 0.0
        for record in driver.laps where record.lap <= lap {
            let new = predictedSeconds(plan: newPlan, lap: record.lap, driver: driver, race: race)
            let realPred = predictedSeconds(plan: real, lap: record.lap, driver: driver, race: race)
            actualSum += record.seconds
            deltaSum += (new - realPred)
        }
        let extraStops = stopsSoFar(plan: newPlan, upToLap: lap) - stopsSoFar(plan: real, upToLap: lap)
        return actualSum + deltaSum + race.pitLoss * Double(extraStops)
    }

    // MARK: - Stint breakdown

    struct StintRow: Identifiable {
        let id = UUID()
        let stint: PlanStint
        let predictedSum: Double
        let deltaVsReal: Double
    }

    struct PitRow: Identifiable {
        let id = UUID()
        let signedPitLoss: Double
    }

    /// Per-stint delta rows plus one row per added/removed stop, so the rows reconcile
    /// exactly to `simulatedTotal - sumOfLaps`. If they don't, the arithmetic has
    /// drifted somewhere and the total is not to be trusted (handoff, "the stint breakdown").
    static func stintBreakdown(newPlan: [PlanStint], driver: DriverEntry, race: RaceData) -> (stints: [StintRow], pitRows: [PitRow]) {
        let real = realPlan(for: driver)
        let sorted = newPlan.sorted { $0.startLap < $1.startLap }
        let untouched = plansMatch(newPlan, real)

        let stintRows: [StintRow] = sorted.map { stint in
            // A still-open stint is stored as running to race.totalLaps - cap what
            // gets shown AND summed at the model's trained limit, so the range in
            // the row and the number next to it always describe the same laps,
            // and neither one is built on a prediction past what the tyre could
            // honestly reach.
            let displayEndLap = projectedEndLap(stint, race: race)
            let displayStint = PlanStint(compound: stint.compound, startLap: stint.startLap, endLap: displayEndLap)

            var predictedSum = 0.0
            var deltaSum = 0.0
            for lapRecord in driver.laps where lapRecord.lap >= stint.startLap && lapRecord.lap <= displayEndLap {
                if untouched {
                    // Delta is zero by construction; the "predicted" sum an
                    // untouched driver would show is just their real lap time.
                    predictedSum += lapRecord.seconds
                } else {
                    let new = predictedSeconds(plan: newPlan, lap: lapRecord.lap, driver: driver, race: race)
                    let realSeconds = predictedSeconds(plan: real, lap: lapRecord.lap, driver: driver, race: race)
                    predictedSum += new
                    deltaSum += (new - realSeconds)
                }
            }
            return StintRow(stint: displayStint, predictedSum: predictedSum, deltaVsReal: deltaSum)
        }

        let stops = stopsDelta(newPlan: newPlan, driver: driver)
        let pitRows: [PitRow] = stops == 0 ? [] : Array(repeating: PitRow(signedPitLoss: stops > 0 ? race.pitLoss : -race.pitLoss), count: abs(stops))

        return (stintRows, pitRows)
    }
}
