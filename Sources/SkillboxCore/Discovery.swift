import Foundation

public struct SkillHit: Decodable, Identifiable, Sendable {
    public let id: String
    public let source: String
    public let skillId: String
    public let name: String
    public let installs: Int?
}
public enum SkillSearch {
    public static func search(_ query: String) async throws -> [SkillHit] {
        var components = URLComponents(string: "https://skills.sh/api/search")!
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        struct Response: Decodable { let skills: [SkillHit] }
        return try await APIClient().getJSON(components.url!, as: Response.self, accept: "application/json", useAuth: false).skills
    }
}
public struct InstallCandidate: Identifiable, Sendable {
    public var id: String { path }
    public let path: String
    public let name: String
    public let files: [TreeEntry]
}
public struct RepositoryPlan: Sendable {
    public let repo: RepoRef
    public let commit: String
    public let candidates: [InstallCandidate]
}
public enum InstallFailure: LocalizedError {
    case invalid(String)
    public var errorDescription: String? { if case .invalid(let message) = self { return message }; return nil }
}
public struct SkillInstaller {
    let github: GitHubClient
    let token: String?
    public init(token: String? = nil) { self.token = token; github = GitHubClient(token: token) }
    public static func safePath(_ path: String) -> Bool {
        !path.isEmpty && !path.hasPrefix("/") && !path.contains("\\") && !path.contains("\0") && path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }
    public func inspect(_ input: String) async throws -> RepositoryPlan {
        guard let repo = RepoRef.parse(input), Self.safePath(repo.slug), repo.owner.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil,
              repo.repo.range(of: "^[A-Za-z0-9_.-]+$", options: .regularExpression) != nil else { throw InstallFailure.invalid("请输入有效的 GitHub owner/repo 或仓库地址。") }
        let branch: String
        if let ref = repo.ref { branch = ref } else { branch = try await github.defaultBranch(owner: repo.owner, repo: repo.repo) }
        var url = URLComponents(string: "https://api.github.com/repos/\(repo.slug)/commits")!
        url.path += "/" + branch
        struct Commit: Decodable { let sha: String }
        let commit = try await APIClient(token: token).getJSON(url.url!, as: Commit.self).sha
        let tree = try await github.tree(owner: repo.owner, repo: repo.repo, ref: commit)
        let candidates = Self.plan(tree: tree).filter { repo.subpath == nil || $0.path == repo.subpath || $0.path.hasPrefix((repo.subpath ?? "") + "/") }
        return RepositoryPlan(repo: repo, commit: commit, candidates: candidates)
    }
    public static func plan(tree: [TreeEntry]) -> [InstallCandidate] {
        tree.filter { $0.isFile && $0.fileName == "SKILL.md" && safePath($0.path) && $0.path.split(separator: "/").count <= 6 && !$0.path.split(separator: "/").contains("node_modules") }.map { entry in
            let path = (entry.path as NSString).deletingLastPathComponent
            return InstallCandidate(path: path, name: path.isEmpty ? "root-skill" : (path as NSString).lastPathComponent,
                                    files: tree.filter { $0.isFile && (path.isEmpty || $0.path.hasPrefix(path + "/")) })
        }.sorted { $0.path < $1.path }
    }
    public func install(_ candidate: InstallCandidate, plan: RepositoryPlan, roots: SkillRoots) async throws -> (String, InstallRecord) {
        guard candidate.files.count <= 1000 else { throw InstallFailure.invalid("文件数超过安全上限 1000。") }
        guard !candidate.files.contains(where: { $0.mode == "120000" }) else { throw InstallFailure.invalid("为安全起见，不安装含符号链接的技能。") }
        for root in [roots.enabled, roots.disabled] {
            guard (try? root.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else { throw InstallFailure.invalid("技能目录不能是符号链接。") }
        }
        let fm = FileManager.default
        let stage = fm.temporaryDirectory.appendingPathComponent("skillbox-" + UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: stage, withIntermediateDirectories: true)
        defer { if stage.lastPathComponent.hasPrefix("skillbox-") { try? fm.removeItem(at: stage) } }
        var bytes = 0
        for entry in candidate.files {
            try Task.checkCancellation()
            let relative = candidate.path.isEmpty ? entry.path : String(entry.path.dropFirst(candidate.path.count + 1))
            guard Self.safePath(relative) else { throw InstallFailure.invalid("拒绝不安全的文件路径。") }
            let data = try await github.file(owner: plan.repo.owner, repo: plan.repo.repo, ref: plan.commit, path: entry.path)
            bytes += data.count
            guard bytes <= 25 * 1024 * 1024 else { throw InstallFailure.invalid("下载超过 25 MB 安全上限。") }
            let target = stage.appendingPathComponent(relative)
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: target, options: .atomic)
        }
        let markdown = try String(contentsOf: stage.appendingPathComponent("SKILL.md"), encoding: .utf8)
        let parsed = FrontmatterParser.parse(markdown)
        guard let name = parsed["name"], name.range(of: "^[a-zA-Z0-9][a-zA-Z0-9_.-]{0,100}$", options: .regularExpression) != nil,
              parsed["description"]?.isEmpty == false else { throw InstallFailure.invalid("SKILL.md 缺少有效 name 或 description。") }
        let destination = roots.enabled.appendingPathComponent(name)
        guard !fm.fileExists(atPath: destination.path), !fm.fileExists(atPath: roots.disabled.appendingPathComponent(name).path) else {
            throw InstallFailure.invalid("\(name) 已存在；为保护本地修改，此次安装已跳过。")
        }
        try fm.createDirectory(at: roots.enabled, withIntermediateDirectories: true)
        try fm.moveItem(at: stage, to: destination)
        return (name, InstallRecord(repo: plan.repo.slug, pathInRepo: candidate.path, sha: plan.commit))
    }
}
