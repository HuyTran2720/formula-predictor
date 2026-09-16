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
            VStack(spacing: 0) {
                clockHeader
                    .padding(.horizontal)
                    .padding(.top, 8)

                // Landscape split: the race side (just the track) takes the
                // left two-thirds, the leaderboard (controls + standings)
                // takes the right third, so the transport buttons sit beside
                // the track instead of on top of it. Starting compounds are
                // picked from the same driver card the live pit control lives
                // in (tap a row), not a separate pre-race screen - this is the
                // only screen there is.
                GeometryReader { geo in
                    HStack(alignment: .top, spacing: 12) {
                        TrackMapView(rows: store.standings, selectedCode: store.selectedDriverCode)
                            .padding(.leading, 8)
                            .frame(width: geo.size.width * 2 / 3, height: geo.size.height, alignment: .top)

                        VStack(spacing: 8) {
                            transportOverlay
                            secondaryControls

                            Divider()

                            // Only the leaderboard scrolls - the track stays pinned.
                            ScrollView {
                                ResultsTableView(
                                    rows: store.standings,
                                    selectedCode: store.selectedDriverCode,
                                    showFinalColumns: store.isFinished,
                                    onSelect: { code in
                                        store.selectedDriverCode = code
                                        isShowingDriverCard = true
                                    }
                                )
                                .padding(.vertical)
                            }
                            .frame(maxHeight: .infinity)
                        }
                        .frame(width: geo.size.width / 3, height: geo.size.height, alignment: .top)
                        .padding(.trailing, 8)
                    }
                }
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

    // MARK: - Race controls

    private var clockHeader: some View {
        let leadLap = store.standings.first?.lapNumber ?? 0
        return HStack {
            Text(DriverInfo.formattedRaceTime(store.raceClockSeconds))
                .font(.system(.headline, design: .monospaced))
            Text(store.isFinished ? "Final result" : "Lap \(leadLap) of \(store.race.totalLaps)")
                .font(.headline)
        }
    }

    private var transportOverlay: some View {
        let playDisabled = (store.speedMultiplier > 0 && store.isFinished)
            || (store.speedMultiplier < 0 && store.raceClockSeconds <= 0)

        return VStack(spacing: 6) {
            Text("\(store.speedMultiplier)x")
                .font(.system(.caption, design: .monospaced))
                .fontWeight(.semibold)

            HStack(spacing: 22) {
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
            .font(.title3)
            .buttonStyle(.borderedProminent)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var secondaryControls: some View {
        HStack(spacing: 12) {
            Button("Skip to end") { store.skipToEnd() }
                .buttonStyle(.bordered)
                .disabled(store.isFinished)

            Button("Back to grid") { store.backToGrid() }
                .buttonStyle(.bordered)
        }
    }
}

#Preview {
    ContentView()
}
