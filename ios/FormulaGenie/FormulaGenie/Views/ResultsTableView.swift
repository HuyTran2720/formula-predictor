//
//  ResultsTableView.swift
//  FormulaGenie
//
//  The results table itself, shared by every phase of the replay - lap 1 looks
//  exactly like lap 66, just with smaller gaps and no points column yet.
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
            header
            ForEach(rows) { row in
                resultRow(row)
                    .contentShape(Rectangle())
                    .onTapGesture { onSelect(row.driver.code) }
                Divider()
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Pos").frame(width: 48, alignment: .leading)
            Text("Driver")
            Spacer()
            Text("Lap").frame(width: 40, alignment: .trailing)
            Text(showFinalColumns ? "Lap time / Gap" : "Lap time").frame(width: 130, alignment: .trailing)
            if showFinalColumns {
                Text("Pts").frame(width: 32, alignment: .trailing)
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.top, 6)
    }

    private func resultRow(_ row: StandingRow) -> some View {
        let isSelected = row.driver.code == selectedCode

        return HStack(alignment: .top) {
            HStack(spacing: 6) {
                Text("\(row.newPosition)")
                    .font(.system(.body, design: .monospaced))
                changeIndicator(row.positionChange)
            }
            .frame(width: 48, alignment: .leading)

            VStack(alignment: .leading, spacing: 1) {
                Text(DriverInfo.fullName(for: row.driver.code))
                    .fontWeight(isSelected ? .bold : .regular)
                    .lineLimit(1)
                Text(DriverInfo.team(fromTeamYear: row.driver.teamYear))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if let needed = row.neededCompoundWarning {
                    Label("Needs \(needed) stop", systemImage: "exclamationmark.triangle")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }

            Spacer()

            Text("\(row.lapNumber)")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)

            VStack(alignment: .trailing, spacing: 0) {
                Text(DriverInfo.formattedLapTime(row.lapElapsedSeconds))
                    .font(.system(.caption, design: .monospaced))
                if showFinalColumns {
                    Text(row.newPosition == 1 ? "Leader" : String(format: "+%.3f", row.gapToLeader))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 130, alignment: .trailing)

            if showFinalColumns {
                Text("\(DriverInfo.points(forPosition: row.newPosition))")
                    .font(.system(.body, design: .monospaced))
                    .frame(width: 32, alignment: .trailing)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func changeIndicator(_ change: Int) -> some View {
        if change > 0 {
            Image(systemName: "arrow.up").foregroundStyle(.green)
        } else if change < 0 {
            Image(systemName: "arrow.down").foregroundStyle(.red)
        } else {
            Image(systemName: "minus").foregroundStyle(.secondary)
        }
    }
}
