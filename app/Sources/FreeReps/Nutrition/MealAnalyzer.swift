import Foundation
import UIKit

/// One food on the plate, as Claude estimated it and the user corrected it.
struct MealItem: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var portion: String
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double
}

struct MealEstimate: Codable, Equatable {
    var title: String
    var items: [MealItem]
    var confidence: String
    var notes: String
}

enum MealAnalyzerError: LocalizedError {
    case noKey
    case badImage
    case offline
    case api(String)
    case refused
    case unreadable

    var errorDescription: String? {
        switch self {
        case .noKey: "Add your Claude API key in Settings › Claude API Key first."
        case .badImage: "Couldn't read that photo. Try another one."
        case .offline: "No internet connection. Try again when you have signal."
        case .api(let message): message
        case .refused: "Claude declined to analyse this photo. Try another photo or add a description."
        case .unreadable: "Claude's answer couldn't be read. Try again."
        }
    }
}

/// Sends a meal photo straight from the phone to the Claude Messages API and
/// returns the foods with portions and nutrition. Raw HTTP: there is no official
/// Swift SDK.
enum MealAnalyzer {

    static func analyze(image: UIImage, hint: String, model: ClaudeModel = .current) async throws -> MealEstimate {
        guard let key = ClaudeKeychain.load(), !key.isEmpty else { throw MealAnalyzerError.noKey }
        guard let jpeg = image.resized(maxSide: 1568).jpegData(compressionQuality: 0.8) else {
            throw MealAnalyzerError.badImage
        }

        var userContent: [[String: Any]] = [
            ["type": "image",
             "source": ["type": "base64", "media_type": "image/jpeg", "data": jpeg.base64EncodedString()]],
        ]
        let trimmedHint = hint.trimmingCharacters(in: .whitespacesAndNewlines)
        userContent.append(["type": "text", "text": trimmedHint.isEmpty
            ? "Estimate this meal."
            : "Estimate this meal. Note from me: \(trimmedHint)"])

        let body: [String: Any] = [
            "model": model.rawValue,
            "max_tokens": 16000,
            "system": systemPrompt,
            "output_config": [
                "effort": "medium",
                "format": ["type": "json_schema", "schema": schema],
            ],
            "messages": [["role": "user", "content": userContent]],
        ]

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError where [.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost].contains(error.code) {
            throw MealAnalyzerError.offline
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw MealAnalyzerError.api(errorMessage(status: status, data: data)) }

        let message = try JSONDecoder().decode(APIMessage.self, from: data)
        if message.stop_reason == "refusal" { throw MealAnalyzerError.refused }
        let text = message.content.filter { $0.type == "text" }.compactMap(\.text).joined()
        guard let json = text.data(using: .utf8),
              let result = try? JSONDecoder().decode(SchemaResult.self, from: json) else {
            throw MealAnalyzerError.unreadable
        }
        return MealEstimate(
            title: result.title,
            items: result.items.map {
                MealItem(name: $0.name, portion: $0.portion, calories: $0.calories,
                         protein: $0.protein_g, carbs: $0.carbs_g, fat: $0.fat_g)
            },
            confidence: result.confidence,
            notes: result.notes)
    }

    // MARK: - Prompt and schema

    private static let systemPrompt = """
    You estimate the nutrition of a meal from a photo for someone tracking calories \
    on their phone. They will review and correct your numbers before saving, so give \
    your best realistic estimate rather than refusing.

    List each distinct food or drink you can see as its own item. For each, judge the \
    portion from visual cues (plate and cutlery size, packaging, hands) and write it the \
    way a person would, with an approximate weight, e.g. "1 cup, ~180 g" or "2 slices, ~60 g". \
    Include likely hidden calories such as cooking oil, butter, dressings and sauces, as \
    their own item when they are significant. If the user adds a note, trust it over what \
    you see. Calories in kcal, protein, carbs and fat in grams, for the portion shown.

    title: a short name for the meal, like "Chicken salad with bread". \
    confidence: "high" when the foods and portions are clear, "low" when the photo is \
    unclear or the portions are hard to judge. notes: one or two short sentences on \
    what you assumed (for example the cooking method or a hidden ingredient); empty if \
    nothing notable. If the photo shows no food or drink, return no items and say so in notes.
    """

    private static let schema: [String: Any] = [
        "type": "object",
        "properties": [
            "title": ["type": "string"],
            "items": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "name": ["type": "string"],
                        "portion": ["type": "string"],
                        "calories": ["type": "number"],
                        "protein_g": ["type": "number"],
                        "carbs_g": ["type": "number"],
                        "fat_g": ["type": "number"],
                    ],
                    "required": ["name", "portion", "calories", "protein_g", "carbs_g", "fat_g"],
                    "additionalProperties": false,
                ],
            ],
            "confidence": ["type": "string", "enum": ["low", "medium", "high"]],
            "notes": ["type": "string"],
        ],
        "required": ["title", "items", "confidence", "notes"],
        "additionalProperties": false,
    ]

    // MARK: - Response types

    private struct APIMessage: Decodable {
        struct Block: Decodable {
            let type: String
            let text: String?
        }
        let content: [Block]
        let stop_reason: String?
    }

    private struct SchemaResult: Decodable {
        struct Item: Decodable {
            let name: String
            let portion: String
            let calories: Double
            let protein_g: Double
            let carbs_g: Double
            let fat_g: Double
        }
        let title: String
        let items: [Item]
        let confidence: String
        let notes: String
    }

    private struct APIError: Decodable {
        struct Body: Decodable { let message: String }
        let error: Body
    }

    private static func errorMessage(status: Int, data: Data) -> String {
        let detail = (try? JSONDecoder().decode(APIError.self, from: data))?.error.message
        switch status {
        case 401: return "Your Claude API key was rejected. Check it in Settings."
        case 429: return "Too many requests right now. Wait a minute and try again."
        case 500...599: return "Claude is busy or unavailable. Try again in a moment."
        default:
            if let detail, detail.localizedCaseInsensitiveContains("credit") {
                return "Your Anthropic credit balance is too low. Add credit at console.anthropic.com › Billing."
            }
            return detail ?? "Unexpected response from Claude (HTTP \(status))."
        }
    }
}

extension UIImage {
    /// Scales down so the longer side is at most `maxSide` points; never scales up.
    func resized(maxSide: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxSide else { return self }
        let scale = maxSide / longest
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
