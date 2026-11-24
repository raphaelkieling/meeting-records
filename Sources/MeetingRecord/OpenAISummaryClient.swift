import Foundation
import Security

enum OpenAISummaryKey {
    // Only the presence flag is stored in preferences.
    static let savedPreferenceKey = "openAISummaryKeySaved"

    private static var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: (Bundle.main.bundleIdentifier ?? "MeetingRecord") + ".OpenAISummary",
            kSecAttrAccount as String: "API Key"
        ]
    }

    static func save(_ value: String) throws {
        let key = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, key.utf8.allSatisfy({ (33...126).contains($0) }) else {
            throw OpenAISummaryError.invalidKey
        }
        let attributes = [kSecValueData as String: Data(key.utf8)]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(attributes) { _, value in value } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw OpenAISummaryError.keychain(status) }
    }

    static func load() throws -> String {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &item)
        if status == errSecItemNotFound { throw OpenAISummaryError.missingKey }
        guard status == errSecSuccess else { throw OpenAISummaryError.keychain(status) }
        guard let data = item as? Data, let key = String(data: data, encoding: .utf8), !key.isEmpty else {
            throw OpenAISummaryError.missingKey
        }
        return key
    }

    static func remove() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw OpenAISummaryError.keychain(status)
        }
    }
}

enum OpenAISummaryError: LocalizedError, Equatable {
    case invalidKey, missingKey, keychain(OSStatus), unauthorized, modelUnavailable, rateLimited
    case responseIncomplete, emptyResponse, contextOverflow, requestFailed(Int)

    var errorDescription: String? {
        switch self {
        case .invalidKey: "Enter an OpenAI API key without spaces or line breaks."
        case .missingKey: "Save an OpenAI API key in the model settings."
        case .keychain(let status): "Could not access the macOS Keychain (code \(status))."
        case .unauthorized: "OpenAI rejected the API key. Check its permissions or replace it in Settings."
        case .modelUnavailable: "This model is unavailable for your OpenAI API project. Choose another model in Settings."
        case .rateLimited: "OpenAI reported a rate or quota limit. Check API billing or try again later."
        case .responseIncomplete: "OpenAI did not finish the response. Try again or choose another model."
        case .emptyResponse: "OpenAI returned no text."
        case .contextOverflow: "The input exceeds the OpenAI model's context window."
        case .requestFailed(let code): "Could not get a response from OpenAI (HTTP \(code))."
        }
    }
}

struct OpenAISummaryClient {
    let model: SummaryModel
    let key: String

    private struct RequestBody: Encodable {
        struct Reasoning: Encodable { let effort: String }
        let model: String
        let instructions: String
        let input: String
        let reasoning: Reasoning?
        let store = false
        let max_output_tokens = 2_000
    }

    private struct ResponseBody: Decodable {
        struct Item: Decodable {
            struct Content: Decodable {
                let type: String
                let text: String?
            }
            let type: String
            let content: [Content]?
        }
        let status: String
        let output: [Item]
    }

    private struct ErrorBody: Decodable {
        struct Detail: Decodable { let code: String? }
        let error: Detail
    }

    func respond(instructions: String, input: String) async throws -> String {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let reasoning: RequestBody.Reasoning? = switch model {
        case .gpt62Astra, .gpt62Sol, .gpt61Terra, .gpt6Luna: .init(effort: "low")
        case .appleIntelligence, .gpt54Mini, .gpt54Nano: nil
        }
        request.httpBody = try JSONEncoder().encode(RequestBody(
            model: model.rawValue, instructions: instructions, input: input, reasoning: reasoning))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(http.statusCode) else {
            let code = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error.code
            if code == "context_length_exceeded" { throw OpenAISummaryError.contextOverflow }
            if code == "model_not_found" || http.statusCode == 404 { throw OpenAISummaryError.modelUnavailable }
            switch http.statusCode {
            case 401, 403: throw OpenAISummaryError.unauthorized
            case 429: throw OpenAISummaryError.rateLimited
            default: throw OpenAISummaryError.requestFailed(http.statusCode)
            }
        }

        let decoded = try JSONDecoder().decode(ResponseBody.self, from: data)
        guard decoded.status == "completed" else { throw OpenAISummaryError.responseIncomplete }
        let text = decoded.output.filter { $0.type == "message" }
            .flatMap { $0.content ?? [] }
            .filter { $0.type == "output_text" }
            .compactMap(\.text)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw OpenAISummaryError.emptyResponse }
        return text
    }
}
