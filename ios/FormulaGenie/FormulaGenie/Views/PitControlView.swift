//
//  PitControlView.swift
//  FormulaGenie
//
//  The live strategy call: box the selected driver this lap onto a new compound.
//  This is the only way a plan changes once the race is running - there is no
//  pre-race stint editor any more.
//

import SwiftUI

struct PitControlView: View {
    @ObservedObject var store: RaceStore
    let driver: DriverEntry

    @State private var compound: String

    init(store: RaceStore, driver: DriverEntry) {
        self.store = store
        self.driver = driver
        _compound = State(initialValue: store.currentPlan(for: driver.code).last?.compound ?? "MEDIUM")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Box \(driver.code) this lap")
                .font(.headline)

            Picker("Compound", selection: $compound) {
                Text("SOFT").tag("SOFT")
                Text("MEDIUM").tag("MEDIUM")
            }
            .pickerStyle(.segmented)

            Button("Box now") {
                store.pit(driver.code, newCompound: compound)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!store.canPit(driver.code))

            if !store.canPit(driver.code) && store.raceClockSeconds > 0 && !store.isFinished {
                Text("Already pitted this lap - wait for the next one.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
