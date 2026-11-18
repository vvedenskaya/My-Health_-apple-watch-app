import SwiftUI

/// Settings › Meal Photos: enter the Claude API key and pick the model.
struct ClaudeSettingsView: View {
    @AppStorage(ClaudeModel.storageKey) private var modelRaw = ClaudeModel.default.rawValue
    @State private var hasKey = ClaudeKeychain.load() != nil
    @State private var draftKey = ""
    @State private var checking = false
    @State private var checkResult: ClaudeKeyCheck.Result?

    private var model: ClaudeModel { ClaudeModel(rawValue: modelRaw) ?? .default }

    var body: some View {
        Form {
            Section {
                if hasKey {
                    LabeledContent("API key") {
                        Label("Saved", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                    }
                    Button("Test key") { Task { await test(ClaudeKeychain.load() ?? "") } }
                        .disabled(checking)
                    Button("Remove key", role: .destructive) {
                        ClaudeKeychain.delete()
                        hasKey = false
                        checkResult = nil
                    }
                } else {
                    SecureField("sk-ant-…", text: $draftKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.password)
                    Button("Save key") { Task { await saveDraft() } }
                        .disabled(draftKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || checking)
                }
                if checking {
                    HStack { ProgressView(); Text("Checking with Anthropic…") }
                } else if let checkResult {
                    switch checkResult {
                    case .ok:
                        Label("Key works with \(model.title).", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    case .failed(let message):
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
            } header: {
                Text("Claude API key")
            } footer: {
                Text("Create a key at console.anthropic.com › API Keys. It is stored only in this iPhone's Keychain and sent only to Anthropic.")
            }

            Section {
                Picker("Model", selection: $modelRaw) {
                    ForEach(ClaudeModel.allCases) { option in
                        VStack(alignment: .leading) {
                            Text(option.title)
                            Text(option.costNote)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .tag(option.rawValue)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
                .onChange(of: modelRaw) { checkResult = nil }
            } header: {
                Text("Model for meal photos")
            }
        }
        .navigationTitle("Meal Photos")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func saveDraft() async {
        let key = draftKey.trimmingCharacters(in: .whitespacesAndNewlines)
        await test(key)
        // Keep the key even if the check fails for a network reason; a rejected key is not saved.
        if case .failed(let message) = checkResult, message.hasPrefix("The key was rejected") { return }
        if ClaudeKeychain.save(key) {
            hasKey = true
            draftKey = ""
        } else {
            checkResult = .failed("Couldn't save the key to the Keychain.")
        }
    }

    private func test(_ key: String) async {
        checking = true
        checkResult = await ClaudeKeyCheck.run(key: key, model: model)
        checking = false
    }
}
