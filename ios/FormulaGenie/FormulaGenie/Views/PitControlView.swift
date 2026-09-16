//
//  PitControlView.swift
//  FormulaGenie
//
//  The strategy call for this driver - before lights out, that's picking a
//  starting compound (there is no separate pre-race screen for it any more);
//  once the race clock has moved, it's the live "box this lap" decision. Same
//  card either way, just a different action depending on `raceClockSeconds`.
//

import SwiftUI

struct PitControlView: View {
    @ObservedObject var store: RaceStore
    let driver: DriverEntry

    @State private var compound: String

    private var isPreRace: Bool { store.raceClockSeconds <= 0 }

    init(store: RaceStore, driver: DriverEntry) {
        self.store = store
        self.driver = driver
        _compound = State(initialValue: store.currentPlan(for: driver.code).last?.compound ?? "MEDIUM")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(isPreRace ? "Starting compound" : "Box \(driver.code) this lap")
                .font(.headline)

            Picker("Compound", selection: $compound) {
                Text("SOFT").tag("SOFT")
                Text("MEDIUM").tag("MEDIUM")
            }
            .pickerStyle(.segmented)

            if isPreRace {
                Button("Set") {
                    store.setStartingCompound(driver.code, compound: compound)
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.currentPlan(for: driver.code).first?.compound == compound)
            } else {
                Button("Box now") {
                    store.pit(driver.code, newCompound: compound)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!store.canPit(driver.code))

                if !store.canPit(driver.code) && !store.isFinished {
                    Text("Already pitted this lap - wait for the next one.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let notice = tyreLifeNotice {
                Label(notice, systemImage: "clock.arrow.circlepath")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    /// The model has no data past `maxTyreLife` for this compound - real
    /// strategists always pit before reaching it, so the app force-pits the
    /// driver there too rather than trust an unconstrained extrapolation. This is
    /// just a heads-up that it's coming, not a warning the user needs to act on.
    private var tyreLifeNotice: String? {
        guard let stint = store.currentPlan(for: driver.code).last else { return nil }
        let age = store.completedLaps(for: driver.code) - stint.startLap + 1
        guard let maxLife = store.race.maxTyreLife[stint.compound] else { return nil }
        let remaining = maxLife - age
        guard remaining <= 5 else { return nil }
        if remaining <= 0 {
            return "\(stint.compound) has reached the model's data limit - being auto-pitted."
        }
        return "\(stint.compound) will be auto-pitted in \(remaining) lap\(remaining == 1 ? "" : "s") (model's data limit)."
    }
}
