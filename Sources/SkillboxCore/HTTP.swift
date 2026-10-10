import Foundation

/// Thin seam over URLSession so clients can be tested with fixture data.
public protocol HTTPFetching: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionHTTP: HTTPFetching {
    let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw HTTPError.notHTTP
        }
        return (data, http)
    }
}

public enum HTTPError: LocalizedError, Equatable {
    case notHTTP
    case status(Int, String?)
    case rateLimited(reset: Date?)
    case decoding(String)

    public var errorDescription: String? {
        switch self {
        case .notHTTP:
            return "The server returned a non-HTTP response."
        case .status(let code, let message):
            if let message, !message.isEmpty {
                return "HTTP \(code): \(message)"
            }
            return "HTTP \(code)"
        case .rateLimited(let reset):
            if let reset {
                let formatter = DateFormatter()
                formatter.timeStyle = .short
                return "GitHub rate limit reached. Try again after \(formatter.string(from: reset)), or add a token in Settings."
            }
            return "GitHub rate limit reached. Add a token in Settings for a higher limit."
        case .decoding(let detail):
            return "Could not read the server response: \(detail)"
        }
    }
}

/// Shared request building: JSON headers, optional bearer token, and
/// translation of HTTP status codes into `HTTPError`.
public struct APIClient: Sendable {
    let http: HTTPFetching
    let token: String?

    public init(http: HTTPFetching = URLSessionHTTP(), token: String? = nil) {
        self.http = http
        self.token = token
    }

    public func getJSON<T: Decodable>(
        _ url: URL,
        as type: T.Type,
        accept: String = "application/vnd.github+json",
        useAuth: Bool = true
    ) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue("Skillbox/1.0", forHTTPHeaderField: "User-Agent")
        if useAuth, let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await http.data(for: request)
        try Self.validate(response, body: data)

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw HTTPError.decoding(error.localizedDescription)
        }
    }

    public func getData(_ url: URL, useAuth: Bool = false) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("Skillbox/1.0", forHTTPHeaderField: "User-Agent")
        if useAuth, let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await http.data(for: request)
        try Self.validate(response, body: data)
        return data
    }

    static func validate(_ response: HTTPURLResponse, body: Data) throws {
        switch response.statusCode {
        case 200..<300:
            return
        case 403, 429:
            let remaining = response.value(forHTTPHeaderField: "X-RateLimit-Remaining")
            if remaining == "0" {
                let reset = response.value(forHTTPHeaderField: "X-RateLimit-Reset")
                    .flatMap(TimeInterval.init)
                    .map { Date(timeIntervalSince1970: $0) }
                throw HTTPError.rateLimited(reset: reset)
            }
            throw HTTPError.status(response.statusCode, message(from: body))
        default:
            throw HTTPError.status(response.statusCode, message(from: body))
        }
    }

    static func message(from body: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return nil
        }
        return object["message"] as? String
    }
}
