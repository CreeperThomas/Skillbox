import Foundation

/// A single installed agent skill: one folder containing a `SKILL.md`.
public struct Skill: Identifiable, Hashable, Sendable {
    /// Folder name, unique across the enabled + disabled roots.
    public var id: String
    /// `name` from frontmatter, falling back to the folder name.
    public var name: String
    /// `description` from frontmatter, falling back to the first body paragraph.
    public var description: String
    public var version: String?
    public var author: String?
    public var license: String?
    public var tags: [String]
    /// The skill folder inside whichever root it lives in.
    public var folderURL: URL
    /// True when the folder lives in the enabled root.
    public var enabled: Bool
    public var fileCount: Int
    public var sizeBytes: Int64
    public var category: Category
    public var sourceID: String?
    /// False when SKILL.md has no parsable frontmatter block.
    public var hasFrontmatter: Bool
    public var modifiedAt: Date?
    /// Raw SKILL.md contents (kept so the UI can render without re-reading).
    public var markdown: String

    /// Machine-facing description used for agent prompts; human-facing views
    /// should prefer a current `ChineseExplanation` when available.
    public var machineDescription: String { description }

    public init(
        id: String,
        name: String,
        description: String,
        version: String? = nil,
        author: String? = nil,
        license: String? = nil,
        tags: [String] = [],
        folderURL: URL,
        enabled: Bool,
        fileCount: Int = 0,
        sizeBytes: Int64 = 0,
        category: Category = .other,
        sourceID: String? = nil,
        hasFrontmatter: Bool = true,
        modifiedAt: Date? = nil,
        markdown: String = ""
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.version = version
        self.author = author
        self.license = license
        self.tags = tags
        self.folderURL = folderURL
        self.enabled = enabled
        self.fileCount = fileCount
        self.sizeBytes = sizeBytes
        self.category = category
        self.sourceID = sourceID
        self.hasFrontmatter = hasFrontmatter
        self.modifiedAt = modifiedAt
        self.markdown = markdown
    }

    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
    public static func == (lhs: Skill, rhs: Skill) -> Bool {
        lhs.id == rhs.id && lhs.enabled == rhs.enabled && lhs.modifiedAt == rhs.modifiedAt
    }
}

/// The two directories Skillbox moves skills between.
public struct SkillRoots: Sendable, Equatable {
    public var enabled: URL
    public var disabled: URL

    public init(enabled: URL, disabled: URL) {
        self.enabled = enabled
        self.disabled = disabled
    }

    /// `~/.agents/skills` and `~/.agents/skills-disabled`.
    public static func standard(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> SkillRoots {
        let agents = home.appendingPathComponent(".agents", isDirectory: true)
        return SkillRoots(
            enabled: agents.appendingPathComponent("skills", isDirectory: true),
            disabled: agents.appendingPathComponent("skills-disabled", isDirectory: true)
        )
    }
}
