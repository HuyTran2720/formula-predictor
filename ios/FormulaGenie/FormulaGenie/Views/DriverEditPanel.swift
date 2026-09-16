//
//  DriverEditPanel.swift
//  FormulaGenie
//
//  The selected driver's pit control and stint breakdown, shown IN PLACE of
//  the leaderboard list (an F1-Manager-style "tab" swap) rather than as a
//  sheet - tapping a row swaps the leaderboard panel's content to this; the
//  back button swaps it back.
//

import SwiftUI

struct DriverEditPanel: View {
    @ObservedObject var store: RaceStore
    let driver: DriverEntry
    let onBack: () -> Void

    /// True while this specific driver's tyre has reached the model's data limit
    /// and the race is paused waiting for a compound choice. Back is disabled in
    /// this state - a strategic choice has to actually be made, not skipped past.
    private var isMandatoryPitPending: Bool {
        store.pendingTyreDecisions.contains(driver.code)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Button(action: onBack) {
                        Label("Back", systemImage: "chevron.left")
                            .font(.subheadline)
                    }
                    .disabled(isMandatoryPitPending)
                    .opacity(isMandatoryPitPending ? 0.4 : 1)

                    Spacer()
                }

                Text(DriverInfo.fullName(for: driver.code))
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)

                if isMandatoryPitPending {
                    Label(
                        "Mandatory pit stop - this tyre has reached the model's data limit. Choose a compound to continue.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding()
                    .background(.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
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
    }
}
