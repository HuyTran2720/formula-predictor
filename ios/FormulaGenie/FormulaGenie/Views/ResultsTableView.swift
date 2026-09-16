//
//  ResultsTableView.swift
//  FormulaGenie
//
//  The results table itself, shared by every phase of the replay - lap 1 looks
//  exactly like lap 66, just with smaller gaps and no points column yet. No
//  column headers - the F1-Manager-inspired leaderboard reads fine without
//  them, and the leader's row is highlighted instead of the header row doing
//  any work.
//

import SwiftUI

struct ResultsTableView: View {
    let rows: [StandingRow]
    let selectedCode: String?
    /// Points only mean something once the replay has actually reached the last lap.
    let showFinalColumns: Bool
    let onSelect: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(rows) { row in
                resultRow(row)
                    .contentShape(Rectangle())
                    .onTapGesture { onSelect(row.driver.code) }
            }
        }
        .padding(.vertical, 4)
    }

    private func resultRow(_ row: StandingRow) -> some View {
        let isSelected = row.driver.code == selectedCode
        let isLeader = row.newPosition == 1
        let textColor: Color = isLeader ? .black : .white
        let secondaryColor: Color = isLeader ? .black.opacity(0.55) : .secondary

        return HStack(alignment: .center, spacing: 4) {
            Group {
                if let change = row.recentPositionChange {
                    changeIndicator(change)
                } else {
                    Text("\(row.newPosition)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(textColor)
                }
            }
            .frame(width: 22, alignment: .leading)

            let team = DriverInfo.team(fromTeamYear: row.driver.teamYear)
            Rectangle()
                .fill(DriverInfo.color(forTeam: team))
                .frame(width: 3, height: 24)
                .clipShape(RoundedRectangle(cornerRadius: 1.5))

            teamLogo(forTeam: team)
                .frame(width: 20, height: 20)

            HStack(spacing: 3) {
                Text(row.driver.code)
                    .font(.caption)
                    .fontWeight(isSelected ? .bold : .semibold)
                    .foregroundStyle(textColor)
                    .lineLimit(1)
                if let needed = row.neededCompoundWarning {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 8))
                        .foregroundStyle(.orange)
                        .help("Needs \(needed) stop")
                }
            }

            Spacer(minLength: 0)

            Text("\(row.lapNumber)")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(secondaryColor)
                .frame(width: 20, alignment: .trailing)

            if row.hasRetiredYet {
                Text("DNF")
                    .font(.system(.caption2, design: .monospaced))
                    .fontWeight(.semibold)
                    .foregroundStyle(.red)
                    .frame(width: 74, alignment: .trailing)
            } else if row.isCurrentlyPitting {
                Text("PIT")
                    .font(.system(.caption2, design: .monospaced))
                    .fontWeight(.semibold)
                    .foregroundStyle(.orange)
                    .frame(width: 74, alignment: .trailing)
            } else {
                VStack(alignment: .trailing, spacing: 0) {
                    Text(DriverInfo.formattedLapTime(row.lapElapsedSeconds))
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(textColor)
                        .lineLimit(1)
                        .fixedSize()
                    if showFinalColumns {
                        Text(isLeader ? "Leader" : String(format: "+%.1f", row.gapToLeader))
                            .font(.caption2)
                            .foregroundStyle(secondaryColor)
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
                .frame(width: 74, alignment: .trailing)
            }

            tyreBadge(for: row.currentCompound)
                .frame(width: 20, alignment: .center)

            if showFinalColumns {
                Text("\(DriverInfo.points(forPosition: row.newPosition))")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(textColor)
                    .frame(width: 22, alignment: .trailing)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Full-bleed, square-cornered highlight for the leader's row (not a
        // rounded pill) - the panel around it is rounded, this row isn't.
        .background(isLeader ? Theme.leaderRow : Color.clear)
        .overlay(alignment: .bottom) {
            if !isLeader {
                Rectangle().fill(Color.white.opacity(0.06)).frame(height: 0.5)
            }
        }
    }

    @ViewBuilder
    private func teamLogo(forTeam team: String) -> some View {
        if let asset = DriverInfo.logoAssetName(forTeam: team) {
            Image(asset)
                .resizable()
                .scaledToFit()
        } else {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.white.opacity(0.08))
        }
    }

    private func tyreBadge(for compound: String) -> some View {
        Text(String(compound.prefix(1)))
            .font(.system(.caption, design: .monospaced))
            .fontWeight(.bold)
            .foregroundStyle(DriverInfo.tyreColor(forCompound: compound))
    }

    @ViewBuilder
    private func changeIndicator(_ change: Int) -> some View {
        if change > 0 {
            Image(systemName: "arrow.up").foregroundStyle(.green)
        } else {
            Image(systemName: "arrow.down").foregroundStyle(.red)
        }
    }
}
