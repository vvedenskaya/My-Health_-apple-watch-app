import Foundation
import HealthKit

/// Today's numbers for the dashboard, read from Apple Health on the phone.
struct HealthSnapshot: Equatable {
    var steps: Double = 0
    var exerciseMinutes: Double = 0
    var activeCalories: Double = 0
    /// Seconds asleep since yesterday 18:00; nil when Health has no sleep data.
    var sleepSeconds: TimeInterval?
    /// Active calories per complete day over the last 14 days, days without data left out.
    var activeHistory: [Double] = []
}

struct WeightEntry: Identifiable, Equatable {
    let id: UUID
    let date: Date
    let kg: Double
}

/// Values the questionnaire can take over from Apple Health.
struct HealthPrefill {
    var sex: UserProfile.Sex?
    var birthDate: Date?
    var heightCm: Double?
    var weightKg: Double?
}

/// Reads for the dashboard and questionnaire, and the one write: body weight.
/// Kept apart from `HealthKitService`, which serves the server sync.
final class HealthSnapshotService {

    static let shared = HealthSnapshotService()
    private let store = HKHealthStore()
    private init() {}

    private let steps = HKQuantityType(.stepCount)
    private let exercise = HKQuantityType(.appleExerciseTime)
    private let activeEnergy = HKQuantityType(.activeEnergyBurned)
    private let bodyMass = HKQuantityType(.bodyMass)
    private let height = HKQuantityType(.height)
    private let sleep = HKCategoryType(.sleepAnalysis)

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Shows the Health permission sheet for what the dashboard needs. iOS shows
    /// it only for types it has not asked about before.
    func requestAccess() async throws {
        guard isAvailable else { throw HKError(.errorHealthDataUnavailable) }
        let read: Set<HKObjectType> = [
            steps, exercise, activeEnergy, bodyMass, height, sleep,
            HKCharacteristicType(.dateOfBirth),
            HKCharacteristicType(.biologicalSex),
        ]
        try await store.requestAuthorization(toShare: Set<HKSampleType>([bodyMass]).union(MealHealthWriter.shareTypes), read: read)
    }

    // MARK: - Questionnaire prefill

    func prefill() async -> HealthPrefill {
        var result = HealthPrefill()
        if let components = try? store.dateOfBirthComponents() {
            result.birthDate = Calendar.current.date(from: components)
        }
        if let sex = try? store.biologicalSex().biologicalSex {
            switch sex {
            case .female: result.sex = .female
            case .male: result.sex = .male
            case .other: result.sex = .other
            default: break
            }
        }
        if let sample = await latestSample(of: height) {
            result.heightCm = sample.quantity.doubleValue(for: .meterUnit(with: .centi))
        }
        if let sample = await latestSample(of: bodyMass) {
            result.weightKg = sample.quantity.doubleValue(for: .gramUnit(with: .kilo))
        }
        return result
    }

    private func latestSample(of type: HKQuantityType) async -> HKQuantitySample? {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: type)],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
            limit: 1)
        return (try? await descriptor.result(for: store))?.first
    }

    // MARK: - Dashboard

    func snapshot(now: Date = Date()) async -> HealthSnapshot {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: now)

        async let stepsToday = sum(steps, unit: .count(), from: startOfToday, to: now)
        async let exerciseToday = sum(exercise, unit: .minute(), from: startOfToday, to: now)
        async let activeToday = sum(activeEnergy, unit: .kilocalorie(), from: startOfToday, to: now)
        async let sleepLastNight = sleepSeconds(now: now)
        async let history = activeHistory(endingBefore: startOfToday)

        return HealthSnapshot(
            steps: await stepsToday,
            exerciseMinutes: await exerciseToday,
            activeCalories: await activeToday,
            sleepSeconds: await sleepLastNight,
            activeHistory: await history)
    }

    /// Zero when Health has no data or the read is refused; iOS does not tell an
    /// app which of the two it is.
    private func sum(_ type: HKQuantityType, unit: HKUnit, from start: Date, to end: Date) async -> Double {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: type, predicate: predicate),
            options: .cumulativeSum)
        let statistics = try? await descriptor.result(for: store)
        return statistics?.sumQuantity()?.doubleValue(for: unit) ?? 0
    }

    private func activeHistory(endingBefore startOfToday: Date) async -> [Double] {
        let calendar = Calendar.current
        guard let start = calendar.date(byAdding: .day, value: -14, to: startOfToday) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: startOfToday, options: .strictStartDate)
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: activeEnergy, predicate: predicate),
            options: .cumulativeSum,
            anchorDate: start,
            intervalComponents: DateComponents(day: 1))
        guard let collection = try? await descriptor.result(for: store) else { return [] }
        var days: [Double] = []
        collection.enumerateStatistics(from: start, to: startOfToday) { statistics, _ in
            guard statistics.startDate < startOfToday else { return }
            let kcal = statistics.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
            if kcal > 0 { days.append(kcal) }
        }
        return days
    }

    /// Time asleep since 18:00 yesterday. Watch and iPhone can both record the
    /// same night, so overlapping stretches are counted once.
    private func sleepSeconds(now: Date) async -> TimeInterval? {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: now)
        guard let windowStart = calendar.date(byAdding: .hour, value: -6, to: startOfToday) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: windowStart, end: now, options: [])
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: sleep, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .forward)])
        guard let samples = try? await descriptor.result(for: store) else { return nil }

        let asleep: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue,
        ]
        let intervals = samples
            .filter { asleep.contains($0.value) }
            .map { (start: max($0.startDate, windowStart), end: min($0.endDate, now)) }
            .filter { $0.end > $0.start }
        guard !intervals.isEmpty else { return nil }

        var total: TimeInterval = 0
        var currentStart = intervals[0].start
        var currentEnd = intervals[0].end
        for interval in intervals.dropFirst() {
            if interval.start <= currentEnd {
                currentEnd = max(currentEnd, interval.end)
            } else {
                total += currentEnd.timeIntervalSince(currentStart)
                currentStart = interval.start
                currentEnd = interval.end
            }
        }
        total += currentEnd.timeIntervalSince(currentStart)
        return total
    }

    // MARK: - Weight

    func weightHistory(days: Int = 90, now: Date = Date()) async -> [WeightEntry] {
        guard let start = Calendar.current.date(byAdding: .day, value: -days, to: now) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: now, options: [])
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: bodyMass, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .forward)])
        let samples = (try? await descriptor.result(for: store)) ?? []
        return samples.map {
            WeightEntry(id: $0.uuid, date: $0.startDate,
                        kg: $0.quantity.doubleValue(for: .gramUnit(with: .kilo)))
        }
    }

    /// Saves a weight to Apple Health, where the Health app and the server sync pick it up.
    func saveWeight(kg: Double, date: Date = Date()) async throws {
        let quantity = HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: kg)
        let sample = HKQuantitySample(type: bodyMass, quantity: quantity, start: date, end: date)
        try await store.save(sample)
    }
}
