import Foundation
import Security

public enum CredentialStore {
    public static func get(_ account: String) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.thomas.skillbox", kSecAttrAccount as String: account, kSecReturnData as String: true]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    public static func set(_ value: String, account: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.thomas.skillbox", kSecAttrAccount as String: account]
        let status: OSStatus
        if value.isEmpty { status = SecItemDelete(query as CFDictionary) }
        else {
            let data = Data(value.utf8)
            let updated = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            if updated == errSecItemNotFound {
                var item = query; item[kSecValueData as String] = data
                status = SecItemAdd(item as CFDictionary, nil)
            } else { status = updated }
        }
        guard status == errSecSuccess || (value.isEmpty && status == errSecItemNotFound) else { throw InstallFailure.invalid("Keychain 保存失败：\(status)") }
    }
}
public struct AIService {
    public let settings: AISettings
    public init(settings: AISettings) { self.settings = settings }
    public func models() async throws -> [String] {
        struct Models: Decodable { struct Model: Decodable { let name: String }; let models: [Model] }
        guard let url = URL(string: settings.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/api/tags") else { throw InstallFailure.invalid("AI 地址无效") }
        return try await APIClient().getJSON(url, as: Models.self, accept: "application/json", useAuth: false).models.map(\.name)
    }
    public func stream(system: String, prompt: String, structured: Bool = false) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let local = settings.backend == .ollama
                    let base = settings.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                    let endpoint = local ? base + "/api/chat" : base + (base.hasSuffix("/v1") ? "/chat/completions" : "/v1/chat/completions")
                    guard let url = URL(string: endpoint), !settings.model.isEmpty else { throw InstallFailure.invalid("请在设置中选择 AI 模型。") }
                    var request = URLRequest(url: url); request.httpMethod = "POST"; request.timeoutInterval = 180
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    if !local, let key = CredentialStore.get("ai"), !key.isEmpty { request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization") }
                    if !local, settings.hasAPIKey, CredentialStore.get("ai")?.isEmpty != false { throw InstallFailure.invalid("已选择云端 AI，但 API key 尚未保存到 Keychain。") }
                    var payload: [String: Any] = ["model": settings.model, "stream": true,
                        "messages": [["role": "system", "content": system], ["role": "user", "content": prompt]]]
                    if structured && local {
                        payload["format"] = "json"
                        payload["think"] = false
                        payload["options"] = ["temperature": 0.1, "num_predict": 1000]
                    }
                    request.httpBody = try JSONSerialization.data(withJSONObject: payload)
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw InstallFailure.invalid("AI 服务请求失败，请检查地址、模型和凭据。") }
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        let text = local ? line : (line.hasPrefix("data: ") ? String(line.dropFirst(6)) : "")
                        if text == "[DONE]" { break }
                        guard let data = text.data(using: .utf8), let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                        if let error = json["error"] { throw InstallFailure.invalid(String(describing: error)) }
                        if local, let message = json["message"] as? [String: Any], let chunk = message["content"] as? String { continuation.yield(chunk) }
                        else if let choices = json["choices"] as? [[String: Any]], let delta = choices.first?["delta"] as? [String: Any], let chunk = delta["content"] as? String { continuation.yield(chunk) }
                    }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
