//
//  RaceData.swift
//  FormulaGenie
//
//  Decodes race.json - the app's entire knowledge of the real race.
//  This file is a pure mirror of the JSON contract in F1-Handoff.md. It never
//  computes anything; StrategySimulator does that.
//

import Foundation

struct LapRecord: Codable {
    let lap: Int
    let tyreLife: Int
    let compound: String
    let seconds: Double
}

struct RealStint: Codable {
    let compound: String
    let startLap: Int
    let endLap: Int
    let startAge: Int
    let endAge: Int
}

struct DriverEntry: Codable, Identifiable {
    var id: String { code }
    let code: String
    let teamYear: String
    let actualTotal: Double
    let actualPosition: Int
    let stints: [RealStint]
    let laps: [LapRecord]
}

struct RaceData: Codable {
    let circuit: String
    let year: Int
    let totalLaps: Int
    let airTemp: Double
    let trackTemp: Double
    let pitLoss: Double
    let pitLossIn: Double
    let pitLossOut: Double
    let maxTyreLife: [String: Int]
    let drivers: [DriverEntry]

    func driver(_ code: String) -> DriverEntry? {
        drivers.first { $0.code == code }
    }

    static func loadBundled() -> RaceData {
        guard let url = Bundle.main.url(forResource: "race", withExtension: "json") else {
            fatalError("race.json not found in bundle - check Target Membership")
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(RaceData.self, from: data)
        } catch {
            fatalError("race.json failed to decode: \(error)")
        }
    }
}
