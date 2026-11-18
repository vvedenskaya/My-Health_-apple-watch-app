import SwiftUI

/// The setup questionnaire. Shown on first launch, and again from Today › Edit goals.
struct OnboardingView: View {
    @ObservedObject private var store = ProfileStore.shared
    @Environment(\.dismiss) private var dismiss

    /// True when opened to change an existing profile; shows Cancel.
    let isEditing: Bool

    @State private var draft: UserProfile
    @State private var weightText: String
    @State private var targetWeightText: String
    @State private var heightCmText: String
    @State private var feet: Int
    @State private var inches: Int
    @State private var didPrefill = false
    @State private var healthNote: String?
    @State private var activeHistory: [Double] = []

    init(isEditing: Bool) {
        self.isEditing = isEditing
        let start = ProfileStore.shared.profile ?? UserProfile()
        _draft = State(initialValue: start)
        _weightText = State(initialValue: Self.weightString(kg: start.weightKg, metric: start.usesMetric))
        _targetWeightText = State(initialValue: Self.weightString(kg: start.targetWeightKg, metric: start.usesMetric))
        _heightCmText = State(initialValue: String(format: "%.0f", start.heightCm))
        let imperial = UnitConvert.feetInches(cm: start.heightCm)
        _feet = State(initialValue: imperial.feet)
        _inches = State(initialValue: imperial.inches)
    }

    var body: some View {
        NavigationStack {
            Form {
                if !isEditing {
                    Section {
                        Text("A few questions set your daily calorie target. Answers already in Apple Health are filled in for you.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("About you") {
                    Picker("Sex", selection: $draft.sex) {
                        ForEach(UserProfile.Sex.allCases) { Text($0.label).tag($0) }
                    }
                    DatePicker("Date of birth", selection: $draft.birthDate,
                               in: Self.birthDateRange, displayedComponents: .date)
                    Picker("Units", selection: $draft.usesMetric) {
                        Text("lb, ft").tag(false)
                        Text("kg, cm").tag(true)
                    }
                    .pickerStyle(.segmented)
                    heightRow
                    numberRow("Current weight", text: $weightText, unit: weightUnit)
                }

                Section("Your goal") {
                    Picker("Goal", selection: $draft.goal) {
                        ForEach(UserProfile.Goal.allCases) { Text($0.label).tag($0) }
                    }
                    if draft.goal != .maintain {
                        numberRow("Target weight", text: $targetWeightText, unit: weightUnit)
                        Picker("Pace", selection: $draft.pace) {
                            ForEach(UserProfile.Pace.allCases) {
                                Text($0.label(metric: draft.usesMetric)).tag($0)
                            }
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    }
                }

                Section {
                    Picker("Activity", selection: $draft.activity) {
                        ForEach(UserProfile.ActivityLevel.allCases) { level in
                            VStack(alignment: .leading) {
                                Text(level.label)
                                Text(level.detail).font(.caption).foregroundStyle(.secondary)
                            }
                            .tag(level)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("Activity level")
                } footer: {
                    Text("Used until your Apple Watch has recorded \(CalorieCalculator.daysNeededForWatchAverage) days of activity. After that the target uses what the Watch measured.")
                }

                resultSection
            }
            .navigationTitle(isEditing ? "Goals" : "Set up")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if isEditing {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(resolved == nil)
                }
            }
            .onChange(of: draft.usesMetric) { _, metric in
                // Re-express what is typed in the other unit.
                if let kg = Self.parse(weightText).map({ metric ? $0 / UnitConvert.lbPerKg : $0 }) {
                    weightText = Self.weightString(kg: kg, metric: metric)
                }
                if let kg = Self.parse(targetWeightText).map({ metric ? $0 / UnitConvert.lbPerKg : $0 }) {
                    targetWeightText = Self.weightString(kg: kg, metric: metric)
                }
                if metric {
                    heightCmText = String(format: "%.0f", Double(feet * 12 + inches) * UnitConvert.cmPerInch)
                } else if let cm = Self.parse(heightCmText) {
                    let imperial = UnitConvert.feetInches(cm: cm)
                    feet = imperial.feet
                    inches = imperial.inches
                }
            }
            .task { await loadFromHealth() }
        }
        .interactiveDismissDisabled(!isEditing)
    }

    // MARK: - Rows

    private var weightUnit: String { draft.usesMetric ? "kg" : "lb" }

    @ViewBuilder
    private var heightRow: some View {
        if draft.usesMetric {
            numberRow("Height", text: $heightCmText, unit: "cm")
        } else {
            HStack {
                Text("Height")
                Spacer()
                Picker("Feet", selection: $feet) {
                    ForEach(3...7, id: \.self) { Text("\($0) ft").tag($0) }
                }
                .labelsHidden()
                Picker("Inches", selection: $inches) {
                    ForEach(0...11, id: \.self) { Text("\($0) in").tag($0) }
                }
                .labelsHidden()
            }
        }
    }

    private func numberRow(_ title: String, text: Binding<String>, unit: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 90)
            Text(unit).foregroundStyle(.secondary)
        }
    }

    // MARK: - Result

    @ViewBuilder
    private var resultSection: some View {
        if let profile = resolved {
            let result = CalorieCalculator.target(profile: profile, activeHistory: activeHistory)
            Section {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(Int(result.target))")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(Color("Brand"))
                    Text("calories a day").foregroundStyle(.secondary)
                }
                LabeledContent("Protein", value: "\(Int(result.proteinGrams.rounded())) g")
                LabeledContent("Carbs", value: "\(Int(result.carbGrams.rounded())) g")
                LabeledContent("Fat", value: "\(Int(result.fatGrams.rounded())) g")
            } header: {
                Text("Your daily target")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Your body uses about \(Int(result.bmr.rounded())) calories at rest and about \(Int(result.maintenance.rounded())) with your activity.")
                    if result.raisedToMinimum {
                        Text("This pace would put you under \(Int(CalorieCalculator.minimum(for: profile.sex))) calories a day, so the target stops there. Going lower is something to plan with a doctor or dietitian.")
                    }
                    if let warning = targetWeightWarning(profile) {
                        Text(warning)
                    }
                    if let healthNote {
                        Text(healthNote)
                    }
                    Text("An estimate from a standard formula, not medical advice.")
                }
            }
        } else {
            Section {
                Text("Enter your height and weight to see your target.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func targetWeightWarning(_ profile: UserProfile) -> String? {
        guard profile.goal == .lose else { return nil }
        let bmi = CalorieCalculator.bmi(weightKg: profile.targetWeightKg, heightCm: profile.heightCm)
        guard bmi > 0, bmi < 18.5 else { return nil }
        return "That target weight is below the healthy range for your height (BMI under 18.5). Consider a higher target."
    }

    // MARK: - Reading the form

    private static var birthDateRange: ClosedRange<Date> {
        let calendar = Calendar.current
        let now = Date()
        let oldest = calendar.date(byAdding: .year, value: -100, to: now) ?? now
        let youngest = calendar.date(byAdding: .year, value: -18, to: now) ?? now
        return oldest...youngest
    }

    private static func parse(_ text: String) -> Double? {
        let cleaned = text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
        guard let value = Double(cleaned), value > 0 else { return nil }
        return value
    }

    private static func weightString(kg: Double, metric: Bool) -> String {
        String(format: "%.1f", metric ? kg : kg * UnitConvert.lbPerKg)
    }

    /// The form as a profile in metric units, or nil while a number is missing
    /// or outside what a person can be.
    private var resolved: UserProfile? {
        var profile = draft
        guard let weight = Self.parse(weightText) else { return nil }
        profile.weightKg = draft.usesMetric ? weight : weight / UnitConvert.lbPerKg
        if draft.usesMetric {
            guard let cm = Self.parse(heightCmText) else { return nil }
            profile.heightCm = cm
        } else {
            profile.heightCm = Double(feet * 12 + inches) * UnitConvert.cmPerInch
        }
        if draft.goal == .maintain {
            profile.targetWeightKg = profile.weightKg
        } else {
            guard let target = Self.parse(targetWeightText) else { return nil }
            profile.targetWeightKg = draft.usesMetric ? target : target / UnitConvert.lbPerKg
        }
        guard (30...300).contains(profile.weightKg),
              (30...300).contains(profile.targetWeightKg),
              (100...230).contains(profile.heightCm) else { return nil }
        return profile
    }

    private func save() {
        guard let profile = resolved else { return }
        store.save(profile)
        dismiss()
    }

    private func loadFromHealth() async {
        guard !didPrefill else { return }
        didPrefill = true
        let health = HealthSnapshotService.shared
        do {
            try await health.requestAccess()
        } catch {
            healthNote = "Apple Health could not be reached, so nothing was filled in."
            return
        }
        activeHistory = await health.snapshot().activeHistory

        // An existing profile keeps what the user entered.
        guard !isEditing else { return }
        let found = await health.prefill()
        if let sex = found.sex { draft.sex = sex }
        if let birthDate = found.birthDate, Self.birthDateRange.contains(birthDate) {
            draft.birthDate = birthDate
        }
        if let cm = found.heightCm {
            heightCmText = String(format: "%.0f", cm)
            let imperial = UnitConvert.feetInches(cm: cm)
            feet = min(max(imperial.feet, 3), 7)
            inches = imperial.inches
        }
        if let kg = found.weightKg {
            weightText = Self.weightString(kg: kg, metric: draft.usesMetric)
            targetWeightText = weightText
        }
    }
}
