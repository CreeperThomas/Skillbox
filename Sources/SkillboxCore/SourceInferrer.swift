import Foundation

/// A set of skills that came from one place — a GitHub repo, or a group we
/// inferred from content fingerprints for skills that predate install records.
public struct SourceGroup: Identifiable, Hashable, Codable, Sendable {
    public enum Kind: String, Codable, Sendable {
        /// Derived from an install record written by Skillbox.
        case installed
        /// Guessed from frontmatter/metadata fingerprints.
        case inferred
        /// Created or renamed by the user.
        case manual
    }

    public var id: String
    public var displayName: String
    /// `owner/repo` when known.
    public var repo: String?
    public var kind: Kind
    /// Website for the group, shown as a link in the sidebar/detail.
    public var url: String?

    public init(id: String, displayName: String, repo: String? = nil, kind: Kind, url: String? = nil) {
        self.id = id
        self.displayName = displayName
        self.repo = repo
        self.kind = kind
        self.url = url
    }

    public var hashValue: Int { id.hashValue }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
    public static func == (lhs: SourceGroup, rhs: SourceGroup) -> Bool { lhs.id == rhs.id }
}

/// Guesses which upstream collection a skill came from when no install record
/// exists. Fingerprints come from frontmatter fields and licence/attribution
/// lines that the well-known collections write into their SKILL.md files.
public enum SourceInferrer {
    /// The builtin groups, in match order. `test` receives the frontmatter and
    /// the raw markdown so rules can look at either.
    static let builtins: [(group: SourceGroup, test: (Frontmatter, String) -> Bool)] = [
        (
            SourceGroup(
                id: "inferred:k-dense",
                displayName: "K-Dense Scientific Skills",
                repo: "K-Dense-AI/claude-scientific-skills",
                kind: .inferred,
                url: "https://github.com/K-Dense-AI/claude-scientific-skills"
            ),
            { fm, markdown in
                authors(match: fm, markdown: markdown, needle: "K-Dense")
            }
        ),
        (
            SourceGroup(
                id: "inferred:orchestra",
                displayName: "Orchestra AI-Research-SKILLs",
                repo: "Orchestra-Research/AI-Research-SKILLs",
                kind: .inferred,
                url: "https://github.com/Orchestra-Research/AI-Research-SKILLs"
            ),
            { fm, markdown in
                markdown.contains("author: Orchestra Research")
                    || (fm["author"]?.contains("Orchestra") ?? false)
            }
        ),
        (
            SourceGroup(
                id: "inferred:anthropic",
                displayName: "Anthropic Skills",
                repo: "anthropics/skills",
                kind: .inferred,
                url: "https://github.com/anthropics/skills"
            ),
            { fm, markdown in
                markdown.contains("Anthropic, PBC")
                    || markdown.contains("github.com/anthropics/skills")
                    || (fm.metadata["source"]?.contains("anthropics/skills") ?? false)
            }
        ),
        (
            SourceGroup(
                id: "inferred:superpowers",
                displayName: "Superpowers (obra)",
                repo: "obra/superpowers",
                kind: .inferred,
                url: "https://github.com/obra/superpowers"
            ),
            { _, markdown in
                markdown.contains("human partner")
                    || markdown.contains("superpowers:")
                    || markdown.contains("REQUIRED SUB-SKILL")
            }
        ),
        (
            SourceGroup(
                id: "inferred:aris",
                displayName: "ARIS Research Pipeline",
                kind: .inferred
            ),
            { _, markdown in
                markdown.contains("mcp__codex")
                    || markdown.contains("ARIS")
                    || markdown.contains("external reviewer backend")
                    || markdown.contains("Use when user says")
            }
        ),
        (
            SourceGroup(
                id: "inferred:ara",
                displayName: "ARA (A-EVO Lab)",
                kind: .inferred
            ),
            { _, markdown in
                markdown.contains("A-EVO Lab") || markdown.contains("ARA Seal")
            }
        ),
        (
            SourceGroup(
                id: "inferred:vercel-labs",
                displayName: "Vercel Labs Agent Skills",
                repo: "vercel-labs/agent-skills",
                kind: .inferred,
                url: "https://github.com/vercel-labs/agent-skills"
            ),
            { _, markdown in markdown.contains("vercel-labs/agent-skills") }
        ),
    ]

    /// Group id for skills that match nothing.
    public static let unsortedID = "inferred:unsorted"

    public static var unsorted: SourceGroup {
        SourceGroup(id: unsortedID, displayName: "Unsorted", kind: .inferred)
    }

    static func authors(match fm: Frontmatter, markdown: String, needle: String) -> Bool {
        if fm.metadata["skill-author"]?.contains(needle) == true { return true }
        if fm["author"]?.contains(needle) == true { return true }
        return markdown.contains("skill-author: \(needle)") || markdown.contains("skill-author: \"\(needle)")
    }

    /// Returns the matching group, or nil when nothing matches.
    public static func infer(parsed: Frontmatter, markdown: String) -> SourceGroup? {
        // An explicit source URL in frontmatter beats a content fingerprint.
        if let source = parsed.metadata["source"], let ref = RepoRef.parse(source) {
            return SourceGroup(
                id: "github:\(ref.owner)/\(ref.repo)",
                displayName: "\(ref.owner)/\(ref.repo)",
                repo: "\(ref.owner)/\(ref.repo)",
                kind: .inferred,
                url: "https://github.com/\(ref.owner)/\(ref.repo)"
            )
        }
        for builtin in builtins where builtin.test(parsed, markdown) {
            return builtin.group
        }
        return nil
    }

    /// Every group present in a skill list, with counts.
    public static func groups(for skills: [Skill], groups custom: [SourceGroup] = []) -> [SourceGroup] {
        var byID: [String: SourceGroup] = [:]
        for group in custom { byID[group.id] = group }
        for builtin in builtins { byID[builtin.group.id] = builtin.group }
        byID[unsortedID] = unsorted

        var seen: Set<String> = []
        for skill in skills {
            let id = skill.sourceID ?? unsortedID
            if seen.insert(id).inserted, byID[id] == nil {
                byID[id] = SourceGroup(id: id, displayName: id, kind: .inferred)
            }
        }
        return byID.values
            .filter { group in skills.contains { ($0.sourceID ?? unsortedID) == group.id } }
            .sorted { lhs, rhs in
                let lc = skills.filter { ($0.sourceID ?? unsortedID) == lhs.id }.count
                let rc = skills.filter { ($0.sourceID ?? unsortedID) == rhs.id }.count
                if lc != rc { return lc > rc }
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
    }
}
