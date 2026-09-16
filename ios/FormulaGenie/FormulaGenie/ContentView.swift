//
//  ContentView.swift
//  FormulaGenie
//
//  Created by Huy Tran on 15/09/26.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var store = RaceStore()
    @State private var isShowingDriverCard = false

    private var selectedDriver: DriverEntry? {
        store.selectedDriverCode.flatMap { store.race.driver($0) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if store.raceConfigured {
                        raceControls
                        ResultsTableView(
                            rows: store.standings,
                            selectedCode: store.selectedDriverCode,
                            showFinalColumns: store.isFinished,
                            onSelect: { code in
                                store.selectedDriverCode = code
                                isShowingDriverCard = true
                            }
                        )
                    } else {
                        startingGrid
                    }
                }
                .padding()
            }
            .navigationTitle("2025 Spanish GP")
            .sheet(isPresented: $isShowingDriverCard) {
                if let driver = selectedDriver {
                    DriverDetailCard(store: store, driver: driver)
                }
            }
            // A pending tyre-life decision takes over the card regardless of what
            // the user was looking at - the race is already paused waiting for it.
            .onChange(of: store.pendingTyreDecisions) { _, pending in
                guard let code = pending.first else { return }
                store.selectedDriverCode = code
                isShowingDriverCard = true
            }
        }
    }

    // MARK: - Pre-race

    private var startingGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Starting grid")
                .font(.headline)
            Text("Pick each driver's starting compound before the lights go out.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(store.race.drivers) { driver in
                StartingGridRow(store: store, driver: driver)
                Divider()
            }

            Button("Start race") { store.beginRace() }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
        }
    }

    // MARK: - Race controls

    private var raceControls: some View {
        let leadLap = store.standings.first?.lapNumber ?? 0
        let playDisabled = (store.speedMultiplier > 0 && store.isFinished)
            || (store.speedMultiplier < 0 && store.raceClockSeconds <= 0)

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(DriverInfo.formattedRaceTime(store.raceClockSeconds))
                    .font(.system(.headline, design: .monospaced))
                Text(store.isFinished ? "Final result" : "Lap \(leadLap) of \(store.race.totalLaps)")
                    .font(.headline)
            }

            ProgressView(value: Double(leadLap), total: Double(store.race.totalLaps))

            Text("\(store.speedMultiplier)x")
                .font(.system(.title3, design: .monospaced))
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)

            HStack(spacing: 28) {
                Button(action: store.decreaseSpeed) {
                    Image(systemName: "backward.fill")
                }
                Button(action: { store.isPlaying ? store.pause() : store.play() }) {
                    Image(systemName: store.isPlaying ? "pause.fill" : "play.fill")
                }
                .disabled(playDisabled)
                Button(action: store.increaseSpeed) {
                    Image(systemName: "forward.fill")
                }
            }
            .font(.title2)
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)

            HStack(spacing: 12) {
                Button("Skip to end") { store.skipToEnd() }
                    .buttonStyle(.bordered)
                    .disabled(store.isFinished)

                Button("Back to grid") { store.backToGrid() }
                    .buttonStyle(.bordered)
            }
        }
    }
}

private struct StartingGridRow: View {
    @ObservedObject var store: RaceStore
    let driver: DriverEntry

    private var compoundBinding: Binding<String> {
        Binding(
            get: { store.currentPlan(for: driver.code).first?.compound ?? "MEDIUM" },
            set: { store.setStartingCompound(driver.code, compound: $0) }
        )
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(DriverInfo.fullName(for: driver.code))
                Text(DriverInfo.team(fromTeamYear: driver.teamYear))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("Compound", selection: compoundBinding) {
                Text("SOFT").tag("SOFT")
                Text("MEDIUM").tag("MEDIUM")
            }
            .pickerStyle(.segmented)
            .frame(width: 160)
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    ContentView()
}
