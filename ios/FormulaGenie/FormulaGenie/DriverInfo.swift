//
//  DriverInfo.swift
//  FormulaGenie
//
//  race.json only carries 3-letter codes and "Team_Year" strings - the display
//  names a real results table needs aren't part of the model's data contract,
//  so they're looked up here rather than invented anywhere near the simulator.
//

import Foundation

enum DriverInfo {
    private static let fullNames: [String: String] = [
        "PIA": "Oscar Piastri",
        "NOR": "Lando Norris",
        "LEC": "Charles Leclerc",
        "RUS": "George Russell",
        "VER": "Max Verstappen",
        "HUL": "Nico Hülkenberg",
        "HAM": "Lewis Hamilton",
        "HAD": "Isack Hadjar",
        "GAS": "Pierre Gasly",
        "ALO": "Fernando Alonso",
        "LAW": "Liam Lawson",
        "BOR": "Gabriel Bortoleto",
        "BEA": "Oliver Bearman",
        "TSU": "Yuki Tsunoda",
        "SAI": "Carlos Sainz",
        "COL": "Franco Colapinto",
        "OCO": "Esteban Ocon",
    ]

    static func fullName(for code: String) -> String {
        fullNames[code] ?? code
    }

    /// "McLaren_2025" -> "McLaren"
    static func team(fromTeamYear teamYear: String) -> String {
        guard let underscore = teamYear.lastIndex(of: "_") else { return teamYear }
        return String(teamYear[teamYear.startIndex..<underscore])
    }

    /// Standard F1 points for a finishing position (1-10), 0 beyond.
    static func points(forPosition position: Int) -> Int {
        let table = [25, 18, 15, 12, 10, 8, 6, 4, 2, 1]
        guard position >= 1, position <= table.count else { return 0 }
        return table[position - 1]
    }

    /// 5577.375 -> "1:32:57.375". For a whole-race total (hours possible).
    static func formattedRaceTime(_ totalSeconds: Double) -> String {
        let hours = Int(totalSeconds) / 3600
        let minutes = (Int(totalSeconds) % 3600) / 60
        let seconds = totalSeconds - Double(hours * 3600 + minutes * 60)
        return String(format: "%d:%02d:%06.3f", hours, minutes, seconds)
    }

    /// 82.879 -> "01:22.879". For a single lap - never runs to an hour, so no hour field.
    static func formattedLapTime(_ totalSeconds: Double) -> String {
        let minutes = Int(totalSeconds) / 60
        let seconds = totalSeconds - Double(minutes * 60)
        return String(format: "%02d:%06.3f", minutes, seconds)
    }
}
