import PhotosUI
import SwiftData
import SwiftUI

/// Take or pick a photo → Claude estimates it → the user corrects it → save.
struct MealLogSheet: View {
    /// A photo saved for later; opens straight on the review screen when it has an estimate.
    var pending: PendingMeal? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    private enum Stage: Equatable {
        case pick
        case analyzing
        case confirm
    }

    @State private var stage: Stage = .pick
    @State private var image: UIImage?
    @State private var hint = ""
    @State private var pickerItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var errorText: String?
    @State private var canSaveForLater = false
    @State private var photoTakenAt = Date()

    // Editable result
    @State private var title = ""
    @State private var items: [MealItem] = []
    @State private var notes = ""
    @State private var confidence = ""
    @State private var mealDate = Date()
    @State private var isSaving = false

    private var cameraAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    var body: some View {
        NavigationStack {
            Group {
                switch stage {
                case .pick, .analyzing: pickView
                case .confirm: confirmView
                }
            }
            .navigationTitle(stage == .confirm ? "Check and save" : "Log meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if stage == .confirm {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { Task { await save() } }
                            .disabled(items.isEmpty || isSaving)
                    }
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker(image: $image).ignoresSafeArea()
            }
            .onAppear(perform: loadPending)
            .onChange(of: image) { photoTakenAt = Date() }
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let picked = UIImage(data: data) {
                        image = picked
                    }
                }
            }
        }
    }

    // MARK: - Pick and analyse

    private var pickView: some View {
        Form {
            Section {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: 260)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .listRowInsets(EdgeInsets())
                }
                if cameraAvailable {
                    Button {
                        showCamera = true
                    } label: {
                        Label(image == nil ? "Take photo" : "Retake photo", systemImage: "camera")
                    }
                }
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Label("Choose from Photos", systemImage: "photo.on.rectangle")
                }
            }

            Section {
                TextField("Optional, e.g. \"cooked in olive oil, half eaten\"", text: $hint, axis: .vertical)
                    .lineLimit(1...3)
            } header: {
                Text("Anything Claude can't see?")
            }

            Section {
                Button {
                    Task { await analyze() }
                } label: {
                    HStack {
                        Spacer()
                        if stage == .analyzing {
                            ProgressView()
                            Text("Analysing with \(ClaudeModel.current.title)…")
                        } else {
                            Label("Analyse meal", systemImage: "sparkles")
                                .font(.headline)
                        }
                        Spacer()
                    }
                }
                .disabled(image == nil || stage == .analyzing)
            } footer: {
                if let errorText {
                    Text(errorText).foregroundStyle(.red)
                } else {
                    Text("The photo is sent to Anthropic for the estimate. You can correct everything before saving.")
                }
            }

            if canSaveForLater {
                Section {
                    Button {
                        saveForLater()
                    } label: {
                        Label("Save photo for later", systemImage: "tray.and.arrow.down")
                    }
                } footer: {
                    Text("It's analysed automatically when you're back online, then waits on Today for you to check it.")
                }
            }
        }
    }

    private func saveForLater() {
        guard let image else { return }
        MealQueue.shared.enqueue(image: image, hint: hint, takenAt: photoTakenAt, in: context)
        dismiss()
    }

    private func loadPending() {
        guard let pending, image == nil else { return }
        image = UIImage(data: pending.photo)
        hint = pending.hint
        // Set after `image`, whose onChange resets it.
        DispatchQueue.main.async { photoTakenAt = pending.createdAt }
        if let estimate = pending.estimate {
            fill(with: estimate)
            mealDate = pending.createdAt
            stage = .confirm
        } else if let error = pending.errorText {
            errorText = error
        }
    }

    private func fill(with estimate: MealEstimate) {
        title = estimate.title
        items = estimate.items
        notes = estimate.notes
        confidence = estimate.confidence
    }

    private func analyze() async {
        guard let image else { return }
        errorText = nil
        canSaveForLater = false
        stage = .analyzing
        do {
            let estimate = try await MealAnalyzer.analyze(image: image, hint: hint)
            fill(with: estimate)
            mealDate = photoTakenAt
            if items.isEmpty {
                errorText = estimate.notes.isEmpty ? "No food found in this photo." : estimate.notes
                stage = .pick
            } else {
                stage = .confirm
            }
        } catch {
            errorText = error.localizedDescription
            canSaveForLater = pending == nil && (error as? MealAnalyzerError).map {
                if case .offline = $0 { return true }
                if case .api = $0 { return true }
                return false
            } ?? false
            stage = .pick
        }
    }

    // MARK: - Confirm

    private var totals: MealItem {
        MealItem(name: "", portion: "",
                 calories: items.reduce(0) { $0 + $1.calories },
                 protein: items.reduce(0) { $0 + $1.protein },
                 carbs: items.reduce(0) { $0 + $1.carbs },
                 fat: items.reduce(0) { $0 + $1.fat })
    }

    private var confirmView: some View {
        Form {
            Section {
                TextField("Meal name", text: $title)
                    .font(.headline)
                DatePicker("Eaten at", selection: $mealDate, in: ...Date())
                HStack(alignment: .firstTextBaseline) {
                    Text("\(Int(totals.calories.rounded()))")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(Color("Brand"))
                    Text("kcal").foregroundStyle(.secondary)
                    Spacer()
                    Text("P \(Int(totals.protein.rounded())) · C \(Int(totals.carbs.rounded())) · F \(Int(totals.fat.rounded())) g")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if confidence == "low" {
                        Label("Claude wasn't sure about this one; check the portions.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                    if !notes.isEmpty { Text(notes) }
                }
            }

            ForEach($items) { $item in
                Section {
                    TextField("Food", text: $item.name)
                        .font(.headline)
                    TextField("Portion", text: $item.portion)
                        .foregroundStyle(.secondary)
                    numberRow("Calories", value: $item.calories, unit: "kcal")
                    numberRow("Protein", value: $item.protein, unit: "g")
                    numberRow("Carbs", value: $item.carbs, unit: "g")
                    numberRow("Fat", value: $item.fat, unit: "g")
                    Button("Remove item", role: .destructive) {
                        items.removeAll { $0.id == item.id }
                    }
                }
            }

            Section {
                Button {
                    items.append(MealItem(name: "", portion: "", calories: 0, protein: 0, carbs: 0, fat: 0))
                } label: {
                    Label("Add item", systemImage: "plus")
                }
            } footer: {
                if let errorText { Text(errorText).foregroundStyle(.red) }
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func numberRow(_ label: String, value: Binding<Double>, unit: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0", value: value, format: .number.precision(.fractionLength(0...1)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 90)
            Text(unit).foregroundStyle(.secondary).frame(width: 34, alignment: .leading)
        }
    }

    private func save() async {
        isSaving = true
        errorText = nil
        let thumbnail = image?.resized(maxSide: 600).jpegData(compressionQuality: 0.7)
        let cleaned = items.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty || $0.calories > 0 }
        let meal = Meal(date: mealDate,
                        title: title.isEmpty ? "Meal" : title,
                        items: cleaned,
                        photo: thumbnail,
                        model: ClaudeModel.current.rawValue)
        if let pending {
            context.delete(pending)
        }
        do {
            try await context.addMeal(meal)
            dismiss()
        } catch {
            // The meal is on the phone already; only the Health write failed.
            if meal.modelContext != nil {
                errorText = "Saved in the app, but not to Apple Health. Allow nutrition under Settings › Privacy & Security › Health › My Health."
                try? await Task.sleep(for: .seconds(3))
                dismiss()
            } else {
                errorText = "Couldn't save the meal: \(error.localizedDescription)"
            }
            isSaving = false
        }
    }
}

/// The system camera, wrapped for SwiftUI.
struct CameraPicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            parent.image = info[.originalImage] as? UIImage
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
