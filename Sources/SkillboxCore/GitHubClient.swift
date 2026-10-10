import Foundation

/// One entry in a repo's git tree.
public struct TreeEntry: Codable, Sendable, Hashable {
    public var path: String
    public var type: String   // "blob" | "tree" | "commit"
    public var sha: String
    public var mode: String?

    public init(path: String, type: String, sha: String, mode: String? = nil) {
        self.path = path
        self.type = type
        self.sha = sha
        self.mode = mode
    }

    public var isFile: Bool { type == "blob" }
    public var fileName: String { (path as NSString).lastPathComponent }
}

/// A repository search hit.
public struct RepoHit: Sendable, Hashable, Identifiable {
    public var id: String { fullName }
    public var fullName: String
    public var description: String?
    public var stars: Int
    public var url: String

    public init(fullName: String, description: String?, stars: Int, url: String) {
        self.fullName = fullName
        self.description = description
        self.stars = stars
        self.url = url
    }
}

/// GitHub REST access: tree listing, raw file download, repo search.
public struct GitHubClient: Sendable {
    let api: APIClient

    public init(http: HTTPFetching = URLSessionHTTP(), token: String? = nil) {
        self.api = APIClient(http: http, token: token)
    }

    // MARK: - Responses

    struct TreeResponse: Decodable {
        var tree: [Entry]
        var truncated: Bool?
        struct Entry: Decodable {
            var path: String
            var type: String
            var sha: String
            var mode: String?
        }
    }

    struct RepoResponse: Decodable {
        var defaultBranch: String
        enum CodingKeys: String, CodingKey { case defaultBranch = "default_branch" }
    }

    struct SearchResponse: Decodable {
        var items: [Item]
        struct Item: Decodable {
            var fullName: String
            var description: String?
            var stargazersCount: Int
            var htmlURL: String
            enum CodingKeys: String, CodingKey {
                case fullName = "full_name"
                case description
                case stargazersCount = "stargazers_count"
                case htmlURL = "html_url"
            }
        }
    }

    // MARK: - API

    /// The repo's default branch, used when the caller did not name a ref.
    public func defaultBranch(owner: String, repo: String) async throws -> String {
        let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)")!
        return try await api.getJSON(url, as: RepoResponse.self).defaultBranch
    }

    /// Every entry of the repo tree. Asks GitHub to recurse so one request
    /// covers the whole repo.
    public func tree(owner: String, repo: String, ref: String) async throws -> [TreeEntry] {
        let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/git/trees/\(ref)?recursive=1")!
        let response = try await api.getJSON(url, as: TreeResponse.self)
        if response.truncated == true {
            throw HTTPError.decoding(
                "This repository is too large for GitHub's tree API to return in one page."
            )
        }
        return response.tree.map { TreeEntry(path: $0.path, type: $0.type, sha: $0.sha, mode: $0.mode) }
    }

    /// Downloads one file's bytes from the raw host (no API rate limit).
    public func file(owner: String, repo: String, ref: String, path: String) async throws -> Data {
        let encoded = path.split(separator: "/").map {
            $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0)
        }.joined(separator: "/")
        let url = URL(string: "https://raw.githubusercontent.com/\(owner)/\(repo)/\(ref)/\(encoded)")!
        return try await api.getData(url)
    }

    /// Searches repositories. GitHub's search endpoint is unauthenticated
    /// rate-limited to 10 requests/minute.
    public func searchRepos(query: String, limit: Int = 20) async throws -> [RepoHit] {
        let escaped = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let url = URL(string: "https://api.github.com/search/repositories?q=\(escaped)&sort=stars&per_page=\(limit)")!
        let response = try await api.getJSON(url, as: SearchResponse.self)
        return response.items.map {
            RepoHit(
                fullName: $0.fullName,
                description: $0.description,
                stars: $0.stargazersCount,
                url: $0.htmlURL
            )
        }
    }
}
