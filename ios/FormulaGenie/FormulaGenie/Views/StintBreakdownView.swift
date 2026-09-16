//
//  StintBreakdownView.swift
//  FormulaGenie
//
//  Per stint of the new plan, plus one row per added/removed pit stop. These rows
//  must reconcile to the headline total delta - if they don't, the arithmetic has
//  drifted somewhere and the total is not to be trusted (F1-Handoff.md).
//

import SwiftUI

struct StintBreakdownView: View {
    let driver: DriverEntry
    let newPlan: [PlanStint]
    let race: RaceData

    private var breakdown: (stints: [StrategySimulator.StintRow], pitRows: [StrategySimulator.PitRow]) {
        StrategySimulator.stintBreakdown(newPlan: newPlan, driver: driver, race: race)
    }

    private var reconciledTotal: Double {
        breakdown.stints.reduce(0) { $0 + $1.deltaVsReal } + breakdown.pitRows.reduce(0) { $0 + $1.signedPitLoss }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Stint breakdown")
                .font(.headline)

            ForEach(breakdown.stints) { row in
                VStack(alignment: .leading, spacing: 1) {
                    HStack {
                        Text(row.stint.compound)
                        Spacer()
                        Text(String(format: "%+.2fs", row.deltaVsReal))
                            .font(.system(.subheadline, design: .monospaced))
                    }
                    Text("laps \(row.stint.startLap)-\(row.stint.endLap)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline)
            }

            ForEach(breakdown.pitRows) { row in
                HStack {
                    Text(row.signedPitLoss > 0 ? "Extra pit stop" : "Removed pit stop")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "%+.2fs", row.signedPitLoss))
                        .font(.system(.subheadline, design: .monospaced))
                }
                .font(.subheadline)
            }

            Divider()
            HStack {
                Text("Total")
                    .fontWeight(.semibold)
                Spacer()
                Text(String(format: "%+.2fs", reconciledTotal))
                    .font(.system(.subheadline, design: .monospaced))
                    .fontWeight(.semibold)
            }
        }
    }
}
