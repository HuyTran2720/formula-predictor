import CoreML
import Foundation

enum LapTimeModel {

    static let model = try! LapPredictorLinear(configuration: MLModelConfiguration())

    /// Prints every input the model expects and its type. Run once; this is the
    /// contract. Do not guess these names from the CSV - Create ML can rename them.
    static func printInputs() {
        for (name, desc) in model.model.modelDescription.inputDescriptionsByName
                                 .sorted(by: { $0.key < $1.key }) {
            print(name, desc.type.rawValue)
        }
    }

    /// The Swift port of derive(). Every numeric input starts at zero, then only the
    /// handful that matter for a Barcelona lap are set. The three derived values are
    /// REBUILT here from compound and tyreLife - never passed in, never cached.
    static func features(lapNumber: Double, tyreLife: Double, compound: String,
                         driver: String, teamYear: String,
                         airTemp: Double, trackTemp: Double) -> [String: MLFeatureValue] {

        var f: [String: MLFeatureValue] = [:]
        for (name, desc) in model.model.modelDescription.inputDescriptionsByName
                where desc.type == .double {
            f[name] = MLFeatureValue(double: 0)
        }

        f["AirTemp"]   = MLFeatureValue(double: airTemp)
        f["TrackTemp"] = MLFeatureValue(double: trackTemp)

        f["age_Barcelona"]  = MLFeatureValue(double: tyreLife)
        f["age_demo_soft"]  = MLFeatureValue(double: compound == "SOFT"   ? tyreLife : 0)
        f["age_demo_med"]   = MLFeatureValue(double: compound == "MEDIUM" ? tyreLife : 0)
        f["fuel_Barcelona"] = MLFeatureValue(double: lapNumber)

        f["Compound"]  = MLFeatureValue(string: compound)
        f["Circuit"]   = MLFeatureValue(string: "Barcelona")
        f["Driver"]    = MLFeatureValue(string: driver)
        f["TeamYear"]  = MLFeatureValue(string: teamYear)

        return f
    }

    static func predict(_ f: [String: MLFeatureValue]) throws -> Double {
        let provider = try MLDictionaryFeatureProvider(dictionary: f)
        let out = try model.model.prediction(from: provider)
        return out.featureValue(for: "LapSeconds")!.doubleValue
    }

    /// One-off parity check. Paste the output of step 3's notebook cell in here,
    /// replacing this comment. Do NOT type values by hand and do NOT invent
    /// plausible-looking ones - two models predicting different laps will of course
    /// disagree, and it looks exactly like a real bug.
    static func parityCheck() {
        // HARD age  3 - Python: 78.6345
        print("CoreML:", try! predict(features(
            lapNumber: 32.0,
            tyreLife: 3.0,
            compound: "HARD",
            driver: "VER",
            teamYear: "Red Bull Racing_2025",
            airTemp: 28.9,
            trackTemp: 47.7)))

        // HARD age 23 - Python: 79.6761
        print("CoreML:", try! predict(features(
            lapNumber: 32.0,
            tyreLife: 23.0,
            compound: "HARD",
            driver: "VER",
            teamYear: "Red Bull Racing_2025",
            airTemp: 28.9,
            trackTemp: 47.7)))

        // Python HARD slope: +0.0521 s/lap

        // MEDIUM age  3 - Python: 78.6263
        print("CoreML:", try! predict(features(
            lapNumber: 32.0,
            tyreLife: 3.0,
            compound: "MEDIUM",
            driver: "VER",
            teamYear: "Red Bull Racing_2025",
            airTemp: 28.9,
            trackTemp: 47.7)))

        // MEDIUM age 23 - Python: 79.8768
        print("CoreML:", try! predict(features(
            lapNumber: 32.0,
            tyreLife: 23.0,
            compound: "MEDIUM",
            driver: "VER",
            teamYear: "Red Bull Racing_2025",
            airTemp: 28.9,
            trackTemp: 47.7)))

        // Python MEDIUM slope: +0.0625 s/lap

        // SOFT age  3 - Python: 78.7292
        print("CoreML:", try! predict(features(
            lapNumber: 32.0,
            tyreLife: 3.0,
            compound: "SOFT",
            driver: "VER",
            teamYear: "Red Bull Racing_2025",
            airTemp: 28.9,
            trackTemp: 47.7)))

        // SOFT age 23 - Python: 80.1350
        print("CoreML:", try! predict(features(
            lapNumber: 32.0,
            tyreLife: 23.0,
            compound: "SOFT",
            driver: "VER",
            teamYear: "Red Bull Racing_2025",
            airTemp: 28.9,
            trackTemp: 47.7)))

        // Python SOFT slope: +0.0703 s/lap
    }
}
