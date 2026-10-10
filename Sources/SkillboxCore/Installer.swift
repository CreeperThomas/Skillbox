import Foundation

public enum InstallConflict: Sendable { case skip, overwrite }

public struct InstallPlan: Sendable, Equatable {
    public let repo: String
    public let pathInRepo: String
    public let sha: String
    public let files: [String]
    public init(repo: String, pathInRepo: String, sha: String, files: [String]) {
        self.repo = repo; self.pathInRepo = pathInRepo; self.sha = sha; self.files = files
    }
}

public enum InstallerError: LocalizedError, Equatable {
    case invalidReference, noSkillFile, unsafePath(String), symlinkRejected(String)
    case missingTarget, downloadFailed(String), invalidArchive(String), installFailed(String)
    public var errorDescription: String? {
        switch self {
        case .invalidReference: return "Invalid repository reference."
        case .noSkillFile: return "The selected directory does not contain SKILL.md."
        case .unsafePath(let p): return "Unsafe path: \(p)"
        case .symlinkRejected(let p): return "Symlinks are not allowed: \(p)"
        case .missingTarget: return "Installation target is missing."
        case .downloadFailed(let s), .invalidArchive(let s), .installFailed(let s): return s
        }
    }
}

/// Plans and atomically installs one skill from a pinned GitHub commit.
public struct Installer: Sendable {
    public let github: GitHubClient
    public let http: HTTPFetching
    public let fileManager: FileManager
    public init(github: GitHubClient? = nil, http: HTTPFetching = URLSessionHTTP(), token: String? = nil, fileManager: FileManager = .default) {
        self.http = http
        self.github = github ?? GitHubClient(http: http, token: token)
        self.fileManager = fileManager
    }

    public func plan(_ reference: RepoRef) async throws -> InstallPlan {
        let ref: String
        if let explicit = reference.ref {
            ref = explicit
        } else {
            ref = try await github.defaultBranch(owner: reference.owner, repo: reference.repo)
        }
        let sha = try await commitSHA(owner: reference.owner, repo: reference.repo, ref: ref)
        let entries = try await github.tree(owner: reference.owner, repo: reference.repo, ref: sha)
        let prefix = normalized(reference.subpath ?? "")
        if !prefix.isEmpty { try validateRelativePath(prefix) }
        let files = try select(entries: entries, prefix: prefix)
        guard files.contains(where: { $0.lowercased().hasSuffix("/skill.md") || $0.lowercased() == "skill.md" }) else { throw InstallerError.noSkillFile }
        return InstallPlan(repo: reference.slug, pathInRepo: prefix, sha: sha, files: files)
    }

    public func install(_ reference: RepoRef, into root: URL, conflict: InstallConflict = .skip) async throws -> InstallRecord? {
        let plan = try await plan(reference)
        try validateDirectory(root)
        let folderName = URL(fileURLWithPath: plan.pathInRepo).lastPathComponent.isEmpty ? reference.repo : URL(fileURLWithPath: plan.pathInRepo).lastPathComponent
        let destination = root.appendingPathComponent(folderName, isDirectory: true)
        if fileManager.fileExists(atPath: destination.path) && conflict == .skip { return nil }
        let temp = root.appendingPathComponent(".skillbox-").appendingPathComponent(UUID().uuidString)
        try fileManager.createDirectory(at: temp, withIntermediateDirectories: true)
        var backup: URL?
        do {
            for relative in plan.files {
                let local = relative.hasPrefix(plan.pathInRepo + "/") ? String(relative.dropFirst(plan.pathInRepo.count + 1)) : relative
                try validateRelativePath(local)
                let data = try await github.file(owner: reference.owner, repo: reference.repo, ref: plan.sha, path: relative)
                let output = temp.appendingPathComponent(local)
                try fileManager.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: output, options: .atomic)
            }
            try validateDownloadedTree(temp)
            if fileManager.fileExists(atPath: destination.path) {
                backup = root.appendingPathComponent(".skillbox-backup-").appendingPathComponent(UUID().uuidString)
                try fileManager.moveItem(at: destination, to: backup!)
            }
            try fileManager.moveItem(at: temp, to: destination)
            if let backup { try? fileManager.removeItem(at: backup) }
            return InstallRecord(repo: plan.repo, pathInRepo: plan.pathInRepo, sha: plan.sha)
        } catch {
            try? fileManager.removeItem(at: temp)
            if let backup, !fileManager.fileExists(atPath: destination.path) { try? fileManager.moveItem(at: backup, to: destination) }
            if let installer = error as? InstallerError { throw installer }
            throw InstallerError.installFailed(error.localizedDescription)
        }
    }

    private func select(entries: [TreeEntry], prefix: String) throws -> [String] {
        try entries.filter { entry in
            guard entry.isFile else { return false }
            try validateRelativePath(entry.path)
            return prefix.isEmpty || entry.path == prefix || entry.path.hasPrefix(prefix + "/")
        }.map(\.path).sorted()
    }

    private func validateDirectory(_ url: URL) throws {
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { throw InstallerError.missingTarget }
        try rejectSymlink(url)
    }
    private func validateDownloadedTree(_ root: URL) throws {
        guard let e = fileManager.enumerator(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey]) else { return }
        for case let url as URL in e { try rejectSymlink(url) }
    }
    private func rejectSymlink(_ url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey])
        if values.isSymbolicLink == true { throw InstallerError.symlinkRejected(url.path) }
    }
    private func validateRelativePath(_ path: String) throws {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\") else { throw InstallerError.unsafePath(path) }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !parts.contains(".."), !parts.contains(".") else { throw InstallerError.unsafePath(path) }
    }
    private func normalized(_ path: String) -> String { path.split(separator: "/").map(String.init).joined(separator: "/") }
    private func commitSHA(owner: String, repo: String, ref: String) async throws -> String {
        let encoded = ref.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ref
        let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/commits/\(encoded)")!
        struct Response: Decodable { let sha: String }
        return try await APIClient(http: http).getJSON(url, as: Response.self)
            .sha
    }
}
