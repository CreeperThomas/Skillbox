import Foundation

public struct SkillsShHit: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let description: String?
    public let url: String?
    public let installs: Int?
    public init(id: String, name: String, description: String? = nil, url: String? = nil, installs: Int? = nil) {
        self.id = id; self.name = name; self.description = description; self.url = url; self.installs = installs
    }
}

public enum SkillsShError: LocalizedError, Equatable {
    case invalidResponse, status(Int), decoding(String)
    public var errorDescription: String? {
        switch self { case .invalidResponse: return "skills.sh returned an invalid response."; case .status(let c): return "skills.sh returned HTTP \(c)."; case .decoding(let s): return "Could not decode skills.sh response: \(s)" }
    }
}

public struct SkillsShClient: Sendable {
    public let baseURL: URL
    public let http: HTTPFetching
    public init(baseURL: URL = URL(string: "https://skills.sh")!, http: HTTPFetching = URLSessionHTTP()) { self.baseURL = baseURL; self.http = http }

    public func search(_ query: String, limit: Int = 20) async throws -> [SkillsShHit] {
        var components = URLComponents(url: baseURL.appendingPathComponent("api/search"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "q", value: query), URLQueryItem(name: "limit", value: String(max(1, min(limit, 100))))]
        guard let url = components?.url else { throw SkillsShError.invalidResponse }
        var request = URLRequest(url: url); request.setValue("Skillbox/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await http.data(for: request)
        guard 200..<300 ~= response.statusCode else { throw SkillsShError.status(response.statusCode) }
        do {
            if let array = try? JSONDecoder().decode([SkillsShHit].self, from: data) { return array }
            struct Envelope: Decodable { let results: [SkillsShHit]?; let skills: [SkillsShHit]?; let items: [SkillsShHit]? }
            let envelope = try JSONDecoder().decode(Envelope.self, from: data)
            return envelope.results ?? envelope.skills ?? envelope.items ?? []
        } catch { throw SkillsShError.decoding(error.localizedDescription) }
    }
}
