import Foundation

public struct AIMessage: Codable, Sendable, Equatable {
    public let role: String
    public let content: String
    public init(role: String, content: String) { self.role = role; self.content = content }
    public static func system(_ text: String) -> AIMessage { AIMessage(role: "system", content: text) }
    public static func user(_ text: String) -> AIMessage { AIMessage(role: "user", content: text) }
}

public struct AIModel: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let backend: AIBackend
    public init(id: String, name: String, backend: AIBackend) { self.id = id; self.name = name; self.backend = backend }
}

public enum AIClientError: LocalizedError, Equatable {
    case invalidURL, missingModel, missingAPIKey, status(Int, String?), decoding(String)
    public var errorDescription: String? {
        switch self { case .invalidURL: return "Invalid AI endpoint URL."; case .missingModel: return "Choose an AI model first."; case .missingAPIKey: return "An API key is required."; case .status(let c, let m): return m.map { "HTTP \(c): \($0)" } ?? "HTTP \(c)"; case .decoding(let s): return "Could not decode AI response: \(s)" }
    }
}

public struct AIClient: Sendable {
    public let settings: AISettings
    public let http: HTTPFetching
    public let keychain: Keychain
    public init(settings: AISettings, http: HTTPFetching = URLSessionHTTP(), keychain: Keychain = .shared) { self.settings = settings; self.http = http; self.keychain = keychain }

    public func models() async throws -> [AIModel] {
        guard let base = URL(string: settings.baseURL) else { throw AIClientError.invalidURL }
        let path = settings.backend == .ollama ? "api/tags" : "v1/models"
        var request = URLRequest(url: base.appendingPathComponent(path)); request.setValue("Skillbox/1.0", forHTTPHeaderField: "User-Agent")
        addAuth(to: &request)
        let (data, response) = try await http.data(for: request); try validate(response, data: data)
        do {
            if settings.backend == .ollama {
                struct R: Decodable { struct M: Decodable { let name: String }; let models: [M] }
                return try JSONDecoder().decode(R.self, from: data).models.map { AIModel(id: $0.name, name: $0.name, backend: .ollama) }
            }
            struct R: Decodable { struct M: Decodable { let id: String }; let data: [M] }
            return try JSONDecoder().decode(R.self, from: data).data.map { AIModel(id: $0.id, name: $0.id, backend: .openAICompatible) }
        } catch { throw AIClientError.decoding(error.localizedDescription) }
    }

    public func stream(messages: [AIMessage], model: String? = nil) -> AsyncThrowingStream<String, Error> {
        let selected = model ?? settings.model
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    guard !selected.isEmpty else { throw AIClientError.missingModel }
                    guard let base = URL(string: settings.baseURL) else { throw AIClientError.invalidURL }
                    let endpoint = settings.backend == .ollama ? "api/chat" : "v1/chat/completions"
                    var request = URLRequest(url: base.appendingPathComponent(endpoint)); request.httpMethod = "POST"; request.setValue("application/json", forHTTPHeaderField: "Content-Type"); addAuth(to: &request)
                    let body: [String: Any] = ["model": selected, "messages": messages.map { ["role": $0.role, "content": $0.content] }, "stream": true]
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)
                    let (data, response) = try await http.data(for: request); try validate(response, data: data)
                    for line in String(decoding: data, as: UTF8.self).components(separatedBy: .newlines) {
                        let value = line.hasPrefix("data:") ? String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces) : line
                        if value.isEmpty || value == "[DONE]" { continue }
                        if let json = value.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any] {
                            if let message = (object["message"] as? [String: Any])?["content"] as? String { continuation.yield(message) }
                            else if let choices = object["choices"] as? [[String: Any]], let delta = choices.first?["delta"] as? [String: Any], let content = delta["content"] as? String { continuation.yield(content) }
                        }
                    }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
        }
    }

    private func addAuth(to request: inout URLRequest) {
        guard settings.backend == .openAICompatible, let key = try? keychain.get(account: "openai-api-key"), !key.isEmpty else { return }
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
    }
    private func validate(_ response: HTTPURLResponse, data: Data) throws {
        guard 200..<300 ~= response.statusCode else { throw AIClientError.status(response.statusCode, String(data: data, encoding: .utf8)) }
    }
}
