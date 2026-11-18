import Foundation
import HealthKit
import SwiftData

/// A saved meal, kept on the phone (SwiftData) and mirrored to Apple Health.
@Model
final class Meal {
    var id: UUID = UUID()
    var date: Date = Date()
    var title: String = ""
    var calories: Double = 0
    var protein: Double = 0
    var carbs: Double = 0
    var fat: Double = 0
    /// JSON-encoded `[MealItem]`.
    var itemsData: Data = Data()
    /// Small JPEG of the photo.
    @Attribute(.externalStorage) var photo: Data?
    /// The Claude model that made the first estimate.
    var model: String = ""
    /// UUID of the food correlation in Apple Health, for deleting it later.
    var healthKitID: UUID?

    init(date: Date, title: String, items: [MealItem], photo: Data?, model: String) {
        self.date = date
        self.title = title
        self.photo = photo
        self.model = model
        self.items = items
    }

    var items: [MealItem] {
        get { (try? JSONDecoder().decode([MealItem].self, from: itemsData)) ?? [] }
        set {
            itemsData = (try? JSONEncoder().encode(newValue)) ?? Data()
            calories = newValue.reduce(0) { $0 + $1.calories }
            protein = newValue.reduce(0) { $0 + $1.protein }
            carbs = newValue.reduce(0) { $0 + $1.carbs }
            fat = newValue.reduce(0) { $0 + $1.fat }
        }
    }
}

/// Writes meals to Apple Health as one "food" entry with energy, protein, carbs
/// and fat, which is how nutrition apps show up in the Health app.
final class MealHealthWriter {
    static let shared = MealHealthWriter()
    private let store = HKHealthStore()
    private init() {}

    static let shareTypes: Set<HKSampleType> = [
        HKQuantityType(.dietaryEnergyConsumed),
        HKQuantityType(.dietaryProtein),
        HKQuantityType(.dietaryCarbohydrates),
        HKQuantityType(.dietaryFatTotal),
    ]

    /// Shows the Health sheet only if these types haven't been asked about yet.
    func requestAccess() async throws {
        try await store.requestAuthorization(toShare: Self.shareTypes, read: [])
    }

    /// Returns the UUID of the saved food entry.
    func save(meal: Meal) async throws -> UUID {
        try await requestAccess()
        let date = meal.date
        let metadata: [String: Any] = [HKMetadataKeyFoodType: meal.title]
        func sample(_ id: HKQuantityTypeIdentifier, _ unit: HKUnit, _ value: Double) -> HKQuantitySample {
            HKQuantitySample(type: HKQuantityType(id), quantity: HKQuantity(unit: unit, doubleValue: value),
                             start: date, end: date, metadata: metadata)
        }
        let samples: Set<HKSample> = [
            sample(.dietaryEnergyConsumed, .kilocalorie(), meal.calories),
            sample(.dietaryProtein, .gram(), meal.protein),
            sample(.dietaryCarbohydrates, .gram(), meal.carbs),
            sample(.dietaryFatTotal, .gram(), meal.fat),
        ]
        let food = HKCorrelation(type: HKCorrelationType(.food), start: date, end: date,
                                 objects: samples, metadata: metadata)
        try await store.save(food)
        return food.uuid
    }

    /// Removes the food entry and the values inside it.
    func delete(healthKitID: UUID) async throws {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.correlation(type: HKCorrelationType(.food),
                                      predicate: HKQuery.predicateForObject(with: healthKitID))],
            sortDescriptors: [])
        guard let food = try await descriptor.result(for: store).first else { return }
        try await store.delete(Array(food.objects) + [food])
    }
}

extension ModelContext {
    /// Saves the meal locally first, then to Apple Health. A failed Health write
    /// keeps the meal on the phone and is reported to the caller.
    @MainActor
    func addMeal(_ meal: Meal) async throws {
        insert(meal)
        try save()
        meal.healthKitID = try await MealHealthWriter.shared.save(meal: meal)
        try save()
    }

    @MainActor
    func removeMeal(_ meal: Meal) async {
        if let id = meal.healthKitID {
            try? await MealHealthWriter.shared.delete(healthKitID: id)
        }
        delete(meal)
        try? save()
    }
}
