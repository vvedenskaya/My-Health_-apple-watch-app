import Foundation

/// The daily calorie target, and how it was reached.
///
/// Hybrid method: until the Watch has recorded enough days, maintenance is
/// BMR × the activity level from the questionnaire. After that it is BMR plus the
/// average active calories the Watch measured over the last 14 days, so the target
/// stays the same through a day but follows real activity over time.
struct CalorieTarget: Equatable {
    enum Method: Equatable {
        case activityLevel
        case watchAverage(days: Int)
    }

    let bmr: Double
    let maintenance: Double
    let target: Double
    let method: Method
    /// True when the goal asked for less than the minimum and the minimum was used.
    let raisedToMinimum: Bool
    /// The active calories per day that maintenance already assumes.
    let assumedActive: Double

    let proteinGrams: Double
    let fatGrams: Double
    let carbGrams: Double
}

enum CalorieCalculator {

    /// Days with Watch data, out of the last 14, needed before the measured
    /// average replaces the questionnaire answer.
    static let daysNeededForWatchAverage = 10

    static let kcalPerKg = 7700.0

    /// Mifflin-St Jeor. For `.other` the constant is the midpoint of the two.
    static func bmr(sex: UserProfile.Sex, weightKg: Double, heightCm: Double, age: Int) -> Double {
        let base = 10 * weightKg + 6.25 * heightCm - 5 * Double(age)
        switch sex {
        case .male: return base + 5
        case .female: return base - 161
        case .other: return base - 78
        }
    }

    /// Commonly used lower bounds for a self-directed plan.
    static func minimum(for sex: UserProfile.Sex) -> Double {
        switch sex {
        case .male: return 1500
        case .female: return 1200
        case .other: return 1350
        }
    }

    /// - Parameter activeHistory: active calories per complete day over the last
    ///   14 days (today excluded); days without Watch data are left out.
    static func target(profile: UserProfile, activeHistory: [Double]) -> CalorieTarget {
        let bmr = bmr(sex: profile.sex, weightKg: profile.weightKg,
                      heightCm: profile.heightCm, age: profile.age)

        let method: CalorieTarget.Method
        let assumedActive: Double
        if activeHistory.count >= daysNeededForWatchAverage {
            assumedActive = activeHistory.reduce(0, +) / Double(activeHistory.count)
            method = .watchAverage(days: activeHistory.count)
        } else {
            assumedActive = bmr * (profile.activity.multiplier - 1)
            method = .activityLevel
        }
        let maintenance = bmr + assumedActive

        let dailyChange = profile.pace.kgPerWeek * kcalPerKg / 7
        var wanted: Double
        switch profile.goal {
        case .maintain: wanted = maintenance
        case .lose: wanted = maintenance - dailyChange
        case .gain: wanted = maintenance + dailyChange
        }

        let floor = minimum(for: profile.sex)
        let raised = wanted < floor
        if raised { wanted = floor }
        let target = (wanted / 10).rounded() * 10

        // Protein from body weight, fat as a quarter of calories, carbs the rest.
        let protein = 1.6 * profile.weightKg
        let fat = target * 0.25 / 9
        let carbs = max(0, (target - protein * 4 - fat * 9) / 4)

        return CalorieTarget(bmr: bmr, maintenance: maintenance, target: target,
                             method: method, raisedToMinimum: raised,
                             assumedActive: assumedActive,
                             proteinGrams: protein, fatGrams: fat, carbGrams: carbs)
    }

    static func bmi(weightKg: Double, heightCm: Double) -> Double {
        let m = heightCm / 100
        return m > 0 ? weightKg / (m * m) : 0
    }
}
