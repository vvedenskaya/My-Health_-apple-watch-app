import Combine
import Foundation

/// What the setup questionnaire collects. Stored in metric units; the views
/// convert for display.
struct UserProfile: Codable, Equatable {

    enum Sex: String, Codable, CaseIterable, Identifiable {
        case female, male, other
        var id: String { rawValue }
        var label: String {
            switch self {
            case .female: return "Female"
            case .male: return "Male"
            case .other: return "Other / prefer not to say"
            }
        }
    }

    enum Goal: String, Codable, CaseIterable, Identifiable {
        case lose, maintain, gain
        var id: String { rawValue }
        var label: String {
            switch self {
            case .lose: return "Lose weight"
            case .maintain: return "Maintain weight"
            case .gain: return "Gain weight"
            }
        }
    }

    enum ActivityLevel: String, Codable, CaseIterable, Identifiable {
        case sedentary, light, moderate, very
        var id: String { rawValue }
        var label: String {
            switch self {
            case .sedentary: return "Sedentary"
            case .light: return "Lightly active"
            case .moderate: return "Moderately active"
            case .very: return "Very active"
            }
        }
        var detail: String {
            switch self {
            case .sedentary: return "Desk job, little exercise"
            case .light: return "Exercise 1–3 days a week"
            case .moderate: return "Exercise 3–5 days a week"
            case .very: return "Exercise 6–7 days a week"
            }
        }
        /// The standard multipliers applied to BMR.
        var multiplier: Double {
            switch self {
            case .sedentary: return 1.2
            case .light: return 1.375
            case .moderate: return 1.55
            case .very: return 1.725
            }
        }
    }

    /// Weekly weight change the user aims for, in kg. Only used for lose and gain.
    enum Pace: String, Codable, CaseIterable, Identifiable {
        case slow, steady, fast
        var id: String { rawValue }
        var kgPerWeek: Double {
            switch self {
            case .slow: return 0.25
            case .steady: return 0.5
            case .fast: return 0.75
            }
        }
        func label(metric: Bool) -> String {
            let amount = metric
                ? String(format: "%.2g kg", kgPerWeek)
                : String(format: "%.2g lb", kgPerWeek * UnitConvert.lbPerKg)
            switch self {
            case .slow: return "Gentle · about \(amount) a week"
            case .steady: return "Steady · about \(amount) a week"
            case .fast: return "Faster · about \(amount) a week"
            }
        }
    }

    var sex: Sex = .female
    var birthDate: Date = Calendar.current.date(byAdding: .year, value: -30, to: Date()) ?? Date()
    var heightCm: Double = 165
    var weightKg: Double = 65
    var goal: Goal = .maintain
    var targetWeightKg: Double = 65
    var pace: Pace = .steady
    var activity: ActivityLevel = .light
    var usesMetric: Bool = Locale.current.measurementSystem == .metric

    var age: Int {
        Calendar.current.dateComponents([.year], from: birthDate, to: Date()).year ?? 30
    }
}

enum UnitConvert {
    static let lbPerKg = 2.20462262
    static let cmPerInch = 2.54

    static func weightText(kg: Double, metric: Bool) -> String {
        metric ? String(format: "%.1f kg", kg) : String(format: "%.1f lb", kg * lbPerKg)
    }

    static func feetInches(cm: Double) -> (feet: Int, inches: Int) {
        let total = Int((cm / cmPerInch).rounded())
        return (total / 12, total % 12)
    }
}

/// Holds the saved profile. `profile` is nil until the questionnaire is finished.
@MainActor
final class ProfileStore: ObservableObject {
    static let shared = ProfileStore()
    private static let key = "userProfile_v1"

    @Published private(set) var profile: UserProfile?

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode(UserProfile.self, from: data) {
            profile = saved
        }
    }

    func save(_ new: UserProfile) {
        profile = new
        if let data = try? JSONEncoder().encode(new) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    /// Called after a weight is logged, so the calorie target follows the scale.
    func updateWeight(kg: Double) {
        guard var current = profile else { return }
        current.weightKg = kg
        save(current)
    }
}
