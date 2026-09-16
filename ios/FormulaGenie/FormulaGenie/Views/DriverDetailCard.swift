//
//  DriverDetailCard.swift
//  FormulaGenie
//
//  The selected driver's pit control and stint breakdown, as a pop-up card
//  (a sheet) rather than buried at the bottom of the main scroll - tapping a
//  row in the results table opens this straight away.
//

import SwiftUI

struct DriverDetailCard: View {
    @ObservedObject var store: RaceStore
    let driver: DriverEntry
    @Environment(\.dismiss) private var dismiss

    /// True while this specific driver's tyre has reached the model's data limit
    /// and the race is paused waiting for a compound choice. The card can't be
    /// swiped or "Done"-ed away in this state - a strategic choice has to actually
    /// be made, not skipped past.
    private var isMandatoryPitPending: Bool {
        store.pendingTyreDecisions.contains(driver.code)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if isMandatoryPitPending {
                        Label(
                            "Mandatory pit stop - this tyre has reached the model's data limit. Choose a compound to continue.",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                        .padding()
                        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                    }
                    if !store.isFinished {
                        PitControlView(store: store, driver: driver)
                    }
                    StintBreakdownView(
                        driver: driver,
                        newPlan: store.currentPlan(for: driver.code),
                        race: store.race
                    )
                }
                .padding()
            }
            .navigationTitle(DriverInfo.fullName(for: driver.code))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    if !isMandatoryPitPending {
                        Button("Done") { dismiss() }
                    }
                }
            }
        }
        .interactiveDismissDisabled(isMandatoryPitPending)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
