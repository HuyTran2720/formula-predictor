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
        HStack(spacing: 4) {
            Text("Pos").frame(width: 26, alignment: .leading)
            Text("Drv")
            Spacer()
            Text("Lap").frame(width: 22, alignment: .trailing)
            Text(showFinalColumns ? "Time / Gap" : "Time").frame(width: 64, alignment: .trailing)
            Text("Tyre").frame(width: 30, alignment: .center).fixedSize()
            if showFinalColumns {
                Text("Pts").frame(width: 24, alignment: .trailing)
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.top, 6)
    }

    private func resultRow(_ row: StandingRow) -> some View {
        let isSelected = row.driver.code == selectedCode

        return HStack(alignment: .top, spacing: 4) {
            Group {
                if let change = row.recentPositionChange {
                    changeIndicator(change)
                } else {
                    Text("\(row.newPosition)")
                        .font(.system(.caption, design: .monospaced))
                }
            }
            .frame(width: 26, alignment: .leading)

            VStack(alignment: .leading, spacing: 1) {
                Text(row.driver.code)
                    .font(.caption)
                    .fontWeight(isSelected ? .bold : .regular)
                    .lineLimit(1)
                if let needed = row.neededCompoundWarning {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .help("Needs \(needed) stop")
                }
            }

            Spacer(minLength: 0)

            Text("\(row.lapNumber)")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 22, alignment: .trailing)

            VStack(alignment: .trailing, spacing: 0) {
                Text(DriverInfo.formattedLapTime(row.lapElapsedSeconds))
                    .font(.system(.caption2, design: .monospaced))
                if showFinalColumns {
                    Text(row.newPosition == 1 ? "Leader" : String(format: "+%.1f", row.gapToLeader))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 64, alignment: .trailing)

            tyreBadge(for: row.currentCompound)
                .frame(width: 30, alignment: .center)

            if showFinalColumns {
                Text("\(DriverInfo.points(forPosition: row.newPosition))")
                    .font(.system(.caption, design: .monospaced))
                    .frame(width: 24, alignment: .trailing)
            }
        }
        .padding(.vertical, 4)
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
