import Charts
import SwiftData
import SwiftUI

/// The first tab: today's calorie target, activity and sleep from Apple Health,
/// and the weight log. Everything here is read on the phone; no server is needed.
struct TodayView: View {
    @ObservedObject private var store = ProfileStore.shared
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var context
    @Query(sort: \Meal.date, order: .reverse) private var allMeals: [Meal]
    @Query(sort: \PendingMeal.createdAt) private var pendingMeals: [PendingMeal]
    @ObservedObject private var queue = MealQueue.shared
    @State private var reviewing: PendingMeal?

    @State private var snapshot = HealthSnapshot()
    @State private var weights: [WeightEntry] = []
    @State private var showGoals = false
    @State private var showWeightEntry = false
    @State private var hasLoaded = false
    @State private var showMealLog = false

    private var todaysMeals: [Meal] {
        let start = Calendar.current.startOfDay(for: Date())
        return allMeals.filter { $0.date >= start }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    if let profile = store.profile {
                        let target = CalorieCalculator.target(profile: profile, activeHistory: snapshot.activeHistory)
                        targetCard(target)
                        mealsCard
                        activityGrid
                        weightCard(profile)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Today")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit goals") { showGoals = true }
                }
            }
            .refreshable { await reload() }
            // Runs on first appearance and again when the questionnaire is saved.
            .task(id: store.profile) { await reload() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    Task {
                        await reload()
                        await queue.process(in: context)
                    }
                }
            }
            .sheet(isPresented: $showGoals, onDismiss: { Task { await reload() } }) {
                OnboardingView(isEditing: true)
            }
            .sheet(isPresented: $showMealLog) {
                MealLogSheet()
            }
            .sheet(item: $reviewing) { pending in
                MealLogSheet(pending: pending)
            }
            .task(id: queue.isOnline) { await queue.process(in: context) }
            .sheet(isPresented: $showWeightEntry) {
                WeightEntrySheet(usesMetric: store.profile?.usesMetric ?? true,
                                 lastKg: weights.last?.kg ?? store.profile?.weightKg) { kg in
                    try await HealthSnapshotService.shared.saveWeight(kg: kg)
                    store.updateWeight(kg: kg)
                    await reload()
                }
                .presentationDetents([.medium])
            }
        }
    }

    private func reload() async {
        let health = HealthSnapshotService.shared
        async let newSnapshot = health.snapshot()
        async let newWeights = health.weightHistory()
        snapshot = await newSnapshot
        weights = await newWeights
        hasLoaded = true
    }

    // MARK: - Calorie target

    private func targetCard(_ target: CalorieTarget) -> some View {
        let earned = max(0, snapshot.activeCalories - target.assumedActive)
        return VStack(alignment: .leading, spacing: 8) {
            Text("Daily calorie target")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(Int(target.target))")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(Color("Brand"))
                Text("kcal").foregroundStyle(.secondary)
            }
            if earned >= 50 {
                Label("+\(Int(earned.rounded())) more active than usual today", systemImage: "flame.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
            eatenBar(eaten: todaysMeals.reduce(0) { $0 + $1.calories }, target: target.target)
            HStack(spacing: 16) {
                macro("Protein", eaten: todaysMeals.reduce(0) { $0 + $1.protein }, grams: target.proteinGrams)
                macro("Carbs", eaten: todaysMeals.reduce(0) { $0 + $1.carbs }, grams: target.carbGrams)
                macro("Fat", eaten: todaysMeals.reduce(0) { $0 + $1.fat }, grams: target.fatGrams)
            }
            Text(methodText(target))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func eatenBar(eaten: Double, target: Double) -> some View {
        let left = target - eaten
        return VStack(alignment: .leading, spacing: 4) {
            ProgressView(value: min(eaten, target), total: max(target, 1))
                .tint(left < 0 ? .orange : Color("Brand"))
            Text(left >= 0
                 ? "\(Int(eaten.rounded())) eaten · \(Int(left.rounded())) left"
                 : "\(Int(eaten.rounded())) eaten · \(Int((-left).rounded())) over")
                .font(.footnote)
                .foregroundStyle(left < 0 ? .orange : .secondary)
        }
    }

    private func macro(_ name: String, eaten: Double, grams: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(Int(eaten.rounded()))").font(.headline)
                Text("/ \(Int(grams.rounded())) g").font(.subheadline).foregroundStyle(.secondary)
            }
            Text(name).font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: - Meals

    private var mealsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Meals today").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Button {
                    showMealLog = true
                } label: {
                    Label("Log meal", systemImage: "camera")
                }
                .buttonStyle(.borderedProminent)
            }
            ForEach(pendingMeals) { pending in
                pendingRow(pending)
                    .contextMenu {
                        Button("Delete photo", systemImage: "trash", role: .destructive) {
                            context.delete(pending)
                            try? context.save()
                        }
                    }
            }
            if todaysMeals.isEmpty && pendingMeals.isEmpty {
                Text("Take a photo of your food and Claude will estimate it.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(todaysMeals) { meal in
                    mealRow(meal)
                        .contextMenu {
                            Button("Delete meal", systemImage: "trash", role: .destructive) {
                                Task { await context.removeMeal(meal) }
                            }
                        }
                }
                Text("Touch and hold a meal to delete it.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func pendingRow(_ pending: PendingMeal) -> some View {
        let ready = pending.estimate != nil
        let status: String
        if ready {
            status = "Ready to check · tap to review"
        } else if let error = pending.errorText {
            status = error
        } else if queue.isProcessing {
            status = "Analysing…"
        } else {
            status = queue.isOnline ? "Waiting to analyse" : "Waiting for a connection"
        }
        return Button {
            if ready || pending.errorText != nil { reviewing = pending }
        } label: {
            HStack(spacing: 12) {
                if let image = UIImage(data: pending.photo) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(pending.estimate?.title ?? "Saved photo")
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    Text("\(pending.createdAt.formatted(date: .abbreviated, time: .shortened)) · \(status)")
                        .font(.caption)
                        .foregroundStyle(pending.errorText != nil ? .orange : .secondary)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: ready ? "chevron.right" : (pending.errorText != nil ? "exclamationmark.circle" : "clock"))
                    .foregroundStyle(ready ? Color("Brand") : .secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func mealRow(_ meal: Meal) -> some View {
        HStack(spacing: 12) {
            if let data = meal.photo, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                Image(systemName: "fork.knife")
                    .frame(width: 48, height: 48)
                    .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(meal.title).font(.body.weight(.medium)).lineLimit(1)
                Text("\(meal.date.formatted(date: .omitted, time: .shortened)) · P \(Int(meal.protein.rounded())) C \(Int(meal.carbs.rounded())) F \(Int(meal.fat.rounded())) g")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(Int(meal.calories.rounded())) kcal")
                .font(.subheadline.weight(.semibold))
        }
        .contentShape(Rectangle())
    }

    private func methodText(_ target: CalorieTarget) -> String {
        switch target.method {
        case .watchAverage(let days):
            return "Based on your Apple Watch: \(Int(target.assumedActive.rounded())) active calories a day on average over \(days) days."
        case .activityLevel:
            let have = snapshot.activeHistory.count
            let need = CalorieCalculator.daysNeededForWatchAverage
            return "Based on the activity level you chose. Switches to Apple Watch data after \(need) recorded days (\(have) so far)."
        }
    }

    // MARK: - Activity and sleep

    private var activityGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            tile("Steps", value: snapshot.steps.formatted(.number.precision(.fractionLength(0))),
                 symbol: "figure.walk", tint: .green)
            tile("Exercise", value: "\(Int(snapshot.exerciseMinutes.rounded())) min",
                 symbol: "figure.run", tint: .mint)
            tile("Active calories", value: "\(Int(snapshot.activeCalories.rounded())) kcal",
                 symbol: "flame.fill", tint: .orange)
            tile("Sleep", value: sleepText, symbol: "bed.double.fill", tint: .indigo)
        }
    }

    private var sleepText: String {
        guard let seconds = snapshot.sleepSeconds else { return hasLoaded ? "No data" : "–" }
        let minutes = Int((seconds / 60).rounded())
        return "\(minutes / 60) h \(minutes % 60) min"
    }

    private func tile(_ title: String, value: String, symbol: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol)
                .font(.subheadline)
                .foregroundStyle(tint)
            Text(value)
                .font(.title2.weight(.semibold))
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Weight

    private func weightCard(_ profile: UserProfile) -> some View {
        let metric = profile.usesMetric
        let factor = metric ? 1 : UnitConvert.lbPerKg
        let current = weights.last?.kg ?? profile.weightKg
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Weight").font(.subheadline).foregroundStyle(.secondary)
                    Text(UnitConvert.weightText(kg: current, metric: metric))
                        .font(.title2.weight(.semibold))
                }
                Spacer()
                Button {
                    showWeightEntry = true
                } label: {
                    Label("Log weight", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
            if profile.goal != .maintain {
                Text("Goal: \(UnitConvert.weightText(kg: profile.targetWeightKg, metric: metric))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if weights.count >= 2 {
                Chart(weights) { entry in
                    LineMark(x: .value("Date", entry.date), y: .value("Weight", entry.kg * factor))
                        .foregroundStyle(Color("Brand"))
                    PointMark(x: .value("Date", entry.date), y: .value("Weight", entry.kg * factor))
                        .foregroundStyle(Color("Brand"))
                        .symbolSize(20)
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 160)
                Text("Last 90 days, from Apple Health")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Log your weight a few times to see the trend here.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

/// Entry of one weight. Saves to Apple Health through `onSave`.
struct WeightEntrySheet: View {
    let usesMetric: Bool
    let lastKg: Double?
    let onSave: @MainActor (Double) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var errorText: String?
    @State private var isSaving = false
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField("0.0", text: $text)
                            .keyboardType(.decimalPad)
                            .font(.system(size: 34, weight: .semibold, design: .rounded))
                            .focused($focused)
                        Text(usesMetric ? "kg" : "lb").foregroundStyle(.secondary)
                    }
                } footer: {
                    if let errorText {
                        Text(errorText).foregroundStyle(.red)
                    } else {
                        Text("Saved to Apple Health.")
                    }
                }
            }
            .navigationTitle("Log weight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(kilograms == nil || isSaving)
                }
            }
            .onAppear {
                if let lastKg {
                    text = String(format: "%.1f", usesMetric ? lastKg : lastKg * UnitConvert.lbPerKg)
                }
                focused = true
            }
        }
    }

    private var kilograms: Double? {
        let cleaned = text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
        guard let value = Double(cleaned) else { return nil }
        let kg = usesMetric ? value : value / UnitConvert.lbPerKg
        return (30...300).contains(kg) ? kg : nil
    }

    private func save() {
        guard let kg = kilograms else { return }
        isSaving = true
        Task {
            do {
                try await onSave(kg)
                dismiss()
            } catch {
                errorText = "Could not save to Apple Health. Allow weight under Settings › Health › Data Access & Devices, then try again."
                isSaving = false
            }
        }
    }
}
