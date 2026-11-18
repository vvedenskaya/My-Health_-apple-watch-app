import Foundation
import Security

/// The Claude API key lives in the iPhone's Keychain, never in the repo or UserDefaults.
/// "This device only": it is not synced to iCloud and not restored onto another phone.
enum ClaudeKeychain {
    private static let service = "personal.myhealth.claude-api"
    private static let account = "api-key"

    static func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func save(_ key: String) -> Bool {
        delete()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: Data(key.utf8),
        ]
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

/// Which Claude model reads meal photos. Stored in UserDefaults under `storageKey`.
enum ClaudeModel: String, CaseIterable, Identifiable {
    case sonnet = "claude-sonnet-5-5"
    case haiku = "claude-haiku-5-5"
    case opus = "claude-opus-5-5"

    static let storageKey = "claudeModel"
    static let `default`: ClaudeModel = .sonnet

    static var current: ClaudeModel {
        UserDefaults.standard.string(forKey: storageKey).flatMap(ClaudeModel.init) ?? .default
    }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sonnet: "Sonnet 5.5"
        case .haiku: "Haiku 5.5"
        case .opus: "Opus 5.5"
        }
    }

    /// Rough cost of one meal photo, from the project's estimate.
    var costNote: String {
        switch self {
        case .sonnet: "Best balance · about $0.008 per photo"
        case .haiku: "Cheapest · about $0.0004 per photo"
        case .opus: "Most capable · about $0.016 per photo"
        }
    }
}

enum ClaudeKeyCheck {
    enum Result: Equatable {
        case ok
        case failed(String)
    }

    /// Looks up the chosen model with the key. The Models endpoint is free, so this
    /// confirms the key and the model without spending credit.
    static func run(key: String, model: ClaudeModel) async -> Result {
        guard let url = URL(string: "https://api.anthropic.com/v1/models/\(model.rawValue)") else {
            return .failed("Bad URL")
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            switch status {
            case 200: return .ok
            case 401: return .failed("The key was rejected. Check that you copied all of it.")
            case 403: return .failed("This key isn't allowed to use the API. Check your Console account.")
            case 404: return .failed("\(model.title) isn't available to this key.")
            default:
                let message = (try? JSONDecoder().decode(APIError.self, from: data))?.error.message
                return .failed(message ?? "Unexpected response (HTTP \(status)).")
            }
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private struct APIError: Decodable {
        struct Body: Decodable { let message: String }
        let error: Body
    }
}
