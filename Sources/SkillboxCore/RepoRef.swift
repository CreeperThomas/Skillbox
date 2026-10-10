import Foundation

/// A parsed reference to a repo somewhere on a git host.
public struct RepoRef: Sendable, Equatable {
    public var owner: String
    public var repo: String
    /// Branch/tag/ref when the input named one.
    public var ref: String?
    /// Path of a skill folder inside the repo, when the input pointed at one.
    public var subpath: String?

    public init(owner: String, repo: String, ref: String? = nil, subpath: String? = nil) {
        self.owner = owner
        self.repo = repo
        self.ref = ref
        self.subpath = subpath
    }

    public var slug: String { "\(owner)/\(repo)" }
    public var htmlURL: String { "https://github.com/\(slug)" }

    /// Parses the shapes a user might paste:
    ///
    /// - `owner/repo`
    /// - `https://github.com/owner/repo`
    /// - `https://github.com/owner/repo/tree/main/skills/pdf`
    /// - `git@github.com:owner/repo.git`
    /// - `owner/repo.git`
    public static func parse(_ input: String) -> RepoRef? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        // SSH form: git@host:owner/repo(.git)
        if text.hasPrefix("git@") {
            guard let colon = text.firstIndex(of: ":") else { return nil }
            text = String(text[text.index(after: colon)...])
            return parsePathForm(text)
        }

        if text.hasPrefix("http://") || text.hasPrefix("https://") {
            guard let url = URL(string: text), let host = url.host?.lowercased() else { return nil }
            // Only GitHub-style hosts expose the APIs we use.
            guard host == "github.com" || host == "www.github.com" else { return nil }
            var parts = url.pathComponents.filter { $0 != "/" }
            guard parts.count >= 2 else { return nil }
            let owner = parts.removeFirst()
            let repo = parts.removeFirst()
            var ref: String?
            var subpath: String?
            if parts.count >= 2, parts[0] == "tree" || parts[0] == "blob" {
                ref = parts[1]
                let rest = parts.dropFirst(2)
                if !rest.isEmpty { subpath = rest.joined(separator: "/") }
            }
            return RepoRef(owner: owner, repo: stripGit(repo), ref: ref, subpath: subpath)
        }

        return parsePathForm(text)
    }

    static func parsePathForm(_ text: String) -> RepoRef? {
        var cleaned = text
        if cleaned.hasSuffix("/") { cleaned.removeLast() }
        let parts = cleaned.split(separator: "/").map(String.init)
        guard parts.count >= 2 else { return nil }
        let owner = parts[0]
        let repo = stripGit(parts[1])
        guard !owner.isEmpty, !repo.isEmpty else { return nil }
        var ref: String?
        var subpath: String?
        if parts.count >= 4, parts[2] == "tree" || parts[2] == "blob" {
            ref = parts[3]
            let rest = parts.dropFirst(4)
            if !rest.isEmpty { subpath = rest.joined(separator: "/") }
        }
        return RepoRef(owner: owner, repo: repo, ref: ref, subpath: subpath)
    }

    static func stripGit(_ repo: String) -> String {
        repo.hasSuffix(".git") ? String(repo.dropLast(4)) : repo
    }
}
