//
//  ContentView.swift
//  FormulaGenie
//
//  Created by Huy Tran on 15/09/26.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var store = RaceStore()
    /// Which "tab" the leaderboard panel is showing right now - the live
    /// standings, or the selected driver's strategy editor in its place. Not a
    /// sheet: tapping a row swaps the panel's content in place, same as an F1
    /// Manager-style team screen, and a back button swaps it back.
    @State private var isShowingDriverPanel = false

    private var selectedDriver: DriverEntry? {
        store.selectedDriverCode.flatMap { store.race.driver($0) }
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            // No padding on this container at all - the race side and
            // leaderboard should occupy the full screen (safe area only),
            // same as the reference design.
            GeometryReader { geo in
                // The two explicit widths below already sum to the full
                // available width, so the HStack's own spacing was extra,
                // pushing the total past the container's right edge and
                // clipping the leaderboard short of it - work the spacing
                // into the split instead of adding it on top.
                let spacing: CGFloat = 10
                let usableWidth = geo.size.width - spacing

                HStack(alignment: .top, spacing: spacing) {
                    raceSide
                        .frame(width: usableWidth * 2 / 3, height: geo.size.height, alignment: .top)

                    leaderboardPanel
                        .frame(width: usableWidth / 3, height: geo.size.height, alignment: .top)
                }
            }
            // Only the trailing and bottom insets are extra chrome margin -
            // ignore just those two so the panels reach those edges. The
            // LEADING inset on a landscape iPhone is the actual Dynamic
            // Island cutout; ignoring it too (a plain `.ignoresSafeArea()`)
            // let the track render underneath it.
            .ignoresSafeArea(.container, edges: [.trailing, .bottom])
        }
        .preferredColorScheme(.dark)
        // A pending tyre-life decision takes over the panel regardless of what
        // the user was looking at - the race is already paused waiting for it.
        .onChange(of: store.pendingTyreDecisions) { _, pending in
            guard let code = pending.first else { return }
            store.selectedDriverCode = code
            isShowingDriverPanel = true
        }
    }

    // MARK: - Race side

    private var raceSide: some View {
        VStack(spacing: 8) {
            Text(store.isFinished ? "Final result" : "Lap \(leadLap) of \(store.race.totalLaps)")
                .font(.subheadline)
                .foregroundStyle(.white)

            TrackMapView(rows: store.standings, selectedCode: store.selectedDriverCode, tickInterval: store.tickInterval)

            // Pushes the control row all the way to the bottom of the race
            // side instead of letting it sit wherever the track's own height
            // happens to end.
            Spacer(minLength: 0)

            bottomControls
        }
    }

    /// Back-to-grid and skip-to-end flank the transport pill in one row,
    /// anchored to the bottom of the race side.
    private var bottomControls: some View {
        HStack {
            Button("Back to grid") { store.backToGrid() }

            Spacer()

            transportOverlay

            Spacer()

            Button("Skip to end") { store.skipToEnd() }
                .disabled(store.isFinished)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 20)
        .padding(.bottom, 10)
    }

    private var leadLap: Int {
        store.standings.first?.lapNumber ?? 0
    }

    private var transportOverlay: some View {
        let playDisabled = (store.speedMultiplier > 0 && store.isFinished)
            || (store.speedMultiplier < 0 && store.raceClockSeconds <= 0)

        return HStack(spacing: 28) {
            Button(action: store.decreaseSpeed) {
                Image(systemName: "chevron.left")
            }

            Button(action: { store.isPlaying ? store.pause() : store.play() }) {
                Image(systemName: store.isPlaying ? "pause.fill" : "play.fill")
            }
            .disabled(playDisabled)

            Text("\(store.speedMultiplier)X")
                .font(.system(.subheadline, design: .monospaced))
                .fontWeight(.semibold)
                .frame(minWidth: 30)

            Button(action: store.increaseSpeed) {
                Image(systemName: "chevron.right")
            }
        }
        .foregroundStyle(.white)
        .font(.title3)
        .padding(.vertical, 10)
        .padding(.horizontal, 24)
        .background(Theme.panel, in: Capsule())
    }

    // MARK: - Leaderboard panel

    private var leaderboardPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The title/clock belong to the standings view, not the driver
            // editor - it gets the panel's whole vertical space instead.
            if !isShowingDriverPanel {
                leaderboardHeader
            }

            if isShowingDriverPanel, let driver = selectedDriver {
                DriverEditPanel(store: store, driver: driver, onBack: {
                    isShowingDriverPanel = false
                    store.selectedDriverCode = nil
                })
            } else {
                ScrollView {
                    ResultsTableView(
                        rows: store.standings,
                        selectedCode: store.selectedDriverCode,
                        showFinalColumns: store.isFinished,
                        onSelect: { code in
                            store.selectedDriverCode = code
                            isShowingDriverPanel = true
                        }
                    )
                }
            }
        }
        .background(Theme.panel)
    }

    private var leaderboardHeader: some View {
        VStack(spacing: 2) {
            Text("2025 Spanish GP")
                .font(.headline)
                .foregroundStyle(.white)
            Text(DriverInfo.formattedRaceTime(store.raceClockSeconds))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }
}

#Preview {
    ContentView()
}
