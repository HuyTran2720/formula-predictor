//
//  DriverInfo.swift
//  FormulaGenie
//
//  race.json only carries 3-letter codes and "Team_Year" strings - the display
//  names a real results table needs aren't part of the model's data contract,
//  so they're looked up here rather than invented anywhere near the simulator.
//

import SwiftUI

enum DriverInfo {
    /// 2025 constructor colors, for the track map's driver dots - approximate,
    /// not the official livery hex values, just enough to tell teammates' cars
    /// apart from the rest of the field at a glance.
    private static let teamColors: [String: Color] = [
        "McLaren": Color(red: 1.0, green: 0.55, blue: 0.0),
        "Ferrari": Color(red: 0.86, green: 0.09, blue: 0.13),
        "Red Bull Racing": Color(red: 0.10, green: 0.15, blue: 0.55),
        "Mercedes": Color(red: 0.0, green: 0.83, blue: 0.75),
        "Aston Martin": Color(red: 0.0, green: 0.44, blue: 0.35),
        "Alpine": Color(red: 0.0, green: 0.55, blue: 0.95),
        "Williams": Color(red: 0.0, green: 0.60, blue: 0.95),
        "Racing Bulls": Color(red: 0.25, green: 0.30, blue: 0.80),
        "Kick Sauber": Color(red: 0.0, green: 0.75, blue: 0.30),
        "Haas": Color(red: 0.55, green: 0.55, blue: 0.55),
        "Haas F1 Team": Color(red: 0.55, green: 0.55, blue: 0.55),
    ]

    static func color(forTeam team: String) -> Color {
        teamColors[team] ?? .gray
    }

    /// Team logo asset names, as imported into Assets.xcassets - named after
    /// each team's title sponsor where that's what got imported (Racing
    /// Bulls' asset is "cashapp", its title sponsor), not the constructor name.
    private static let logoAssetNames: [String: String] = [
        "McLaren": "mclaren",
        "Ferrari": "ferrari",
        "Red Bull Racing": "redbull",
        "Mercedes": "mercedes",
        "Aston Martin": "astonmartin",
        "Alpine": "alpine",
        "Williams": "williams",
        "Racing Bulls": "cashapp",
        "Kick Sauber": "kick",
        "Haas": "haas",
        "Haas F1 Team": "haas",
    ]

    static func logoAssetName(forTeam team: String) -> String? {
        logoAssetNames[team]
    }

    /// Standard F1 tyre-compound colors - red/soft, yellow/medium, white/hard.
    private static let tyreColors: [String: Color] = [
        "SOFT": Color(red: 0.9, green: 0.15, blue: 0.15),
        "MEDIUM": Color(red: 0.95, green: 0.8, blue: 0.1),
        "HARD": Color(white: 0.65),
    ]

    static func tyreColor(forCompound compound: String) -> Color {
        tyreColors[compound] ?? .gray
    }

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
