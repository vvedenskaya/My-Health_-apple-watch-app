import HealthKit
import UIKit

/// Optional background sync. FreeReps left this out by design (their DECISIONS.md,
/// 2026-09-25); My Health adds it back with two guards: it never runs while the
/// phone is locked (HealthKit can't be read then) and at most every 30 minutes.
///
/// HealthKit background delivery wakes the app when one of `watchedTypes` gets new
/// data, at most about hourly. The observer queries must be registered on every
/// launch, including background launches, so `start()` runs from the app delegate.
@MainActor
final class BackgroundSync {
    static let shared = BackgroundSync()

    static let enabledKey = "backgroundSyncEnabled"
    private static let lastRunKey = "backgroundSyncLastRun"
    private static let minimumInterval: TimeInterval = 30 * 60

    var isEnabled: Bool { UserDefaults.standard.bool(forKey: Self.enabledKey) }

    var lastRun: Date? { UserDefaults.standard.object(forKey: Self.lastRunKey) as? Date }

    private let store = HKHealthStore()
    private var queries: [HKObserverQuery] = []

    /// A few types that change through the day; any of them waking the app runs a
    /// normal incremental sync, which sends every category.
    private let watchedTypes: [HKSampleType] = [
        HKQuantityType(.stepCount),
        HKQuantityType(.activeEnergyBurned),
        HKQuantityType(.heartRate),
        HKQuantityType(.bodyMass),
        HKQuantityType(.dietaryEnergyConsumed),
        HKCategoryType(.sleepAnalysis),
    ]

    private init() {}

    func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
        if enabled { start() } else { stop() }
    }

    func start() {
        guard isEnabled, HKHealthStore.isHealthDataAvailable(), queries.isEmpty else { return }
        for type in watchedTypes {
            let query = HKObserverQuery(sampleType: type, predicate: nil) { _, completion, error in
                guard error == nil else { completion(); return }
                Task { @MainActor in
                    await BackgroundSync.shared.handleUpdate()
                    completion()
                }
            }
            store.execute(query)
            queries.append(query)
            store.enableBackgroundDelivery(for: type, frequency: .hourly) { _, _ in }
        }
    }

    func stop() {
        queries.forEach(store.stop)
        queries.removeAll()
        store.disableAllBackgroundDelivery { _, _ in }
    }

    private func handleUpdate() async {
        let app = UIApplication.shared
        // Locked: every HealthKit read would fail. The next wake after unlock syncs.
        guard app.isProtectedDataAvailable else { return }
        if let lastRun, Date().timeIntervalSince(lastRun) < Self.minimumInterval { return }
        let vm = SyncViewModel.shared
        guard !vm.isAnySyncRunning else { return }

        UserDefaults.standard.set(Date(), forKey: Self.lastRunKey)
        // Asks iOS for extra time in case the app is sent to the background mid-sync.
        var taskID = UIBackgroundTaskIdentifier.invalid
        taskID = app.beginBackgroundTask(withName: "HealthSync") {
            vm.cancelSync()
            app.endBackgroundTask(taskID)
            taskID = .invalid
        }
        _ = await vm.runSync()
        if taskID != .invalid { app.endBackgroundTask(taskID) }
    }
}

/// Registers the HealthKit observers at launch, which background wakes require.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        MainActor.assumeIsolated { BackgroundSync.shared.start() }
        return true
    }
}
