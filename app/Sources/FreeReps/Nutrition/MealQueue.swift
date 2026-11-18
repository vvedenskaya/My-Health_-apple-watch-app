import Foundation
import Network
import SwiftData
import UIKit

/// A meal photo taken without signal. It is analysed once the phone is online,
/// then waits on Today for the user to review and save it.
@Model
final class PendingMeal {
    var id: UUID = UUID()
    /// When the photo was taken; becomes the meal time.
    var createdAt: Date = Date()
    @Attribute(.externalStorage) var photo: Data = Data()
    var hint: String = ""
    /// JSON-encoded `MealEstimate` once Claude has answered.
    var estimateData: Data?
    /// Why the last attempt failed, when it wasn't just missing signal.
    var errorText: String?

    init(photo: Data, hint: String, createdAt: Date = Date()) {
        self.photo = photo
        self.hint = hint
        self.createdAt = createdAt
    }

    var estimate: MealEstimate? {
        estimateData.flatMap { try? JSONDecoder().decode(MealEstimate.self, from: $0) }
    }
}

/// Watches the network and analyses waiting photos when it comes back.
@MainActor
final class MealQueue: ObservableObject {
    static let shared = MealQueue()

    @Published private(set) var isOnline = true
    @Published private(set) var isProcessing = false

    private let monitor = NWPathMonitor()

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in self?.isOnline = online }
        }
        monitor.start(queue: DispatchQueue(label: "personal.myhealth.network"))
    }

    func enqueue(image: UIImage, hint: String, takenAt: Date, in context: ModelContext) {
        guard let jpeg = image.resized(maxSide: 1568).jpegData(compressionQuality: 0.8) else { return }
        context.insert(PendingMeal(photo: jpeg, hint: hint, createdAt: takenAt))
        try? context.save()
    }

    /// Analyses every waiting photo that has no estimate yet. Stops at the first
    /// offline error; other errors are kept on the item so the user can retry.
    func process(in context: ModelContext) async {
        guard isOnline, !isProcessing else { return }
        let descriptor = FetchDescriptor<PendingMeal>(sortBy: [SortDescriptor(\.createdAt)])
        let waiting = ((try? context.fetch(descriptor)) ?? []).filter { $0.estimateData == nil && $0.errorText == nil }
        guard !waiting.isEmpty else { return }
        isProcessing = true
        defer { isProcessing = false }
        for pending in waiting {
            guard let image = UIImage(data: pending.photo) else {
                pending.errorText = MealAnalyzerError.badImage.localizedDescription
                continue
            }
            do {
                let estimate = try await MealAnalyzer.analyze(image: image, hint: pending.hint)
                pending.estimateData = try JSONEncoder().encode(estimate)
            } catch MealAnalyzerError.offline {
                break
            } catch {
                pending.errorText = error.localizedDescription
            }
            try? context.save()
        }
    }

    /// Clears the error so `process` tries the photo again.
    func retry(_ pending: PendingMeal, in context: ModelContext) async {
        pending.errorText = nil
        try? context.save()
        await process(in: context)
    }
}
