import Foundation

/// A record of one skill installed by Skillbox, used for exact source
/// attribution and (later) update checks.
public struct InstallRecord: Codable, Sendable, Equatable {
    /// `owner/repo`.
    public var repo: String
    /// Path of the skill folder inside the repo, e.g. `skills/pdf`.
    public var pathInRepo: String
    /// Commit SHA the files were taken from.
    public var sha: String
    public var installedAt: Date

    public init(repo: String, pathInRepo: String, sha: String, installedAt: Date = Date()) {
        self.repo = repo
        self.pathInRepo = pathInRepo
        self.sha = sha
        self.installedAt = installedAt
    }
}

/// A cached plain-language explanation of what a skill is for.
public struct AISummary: Codable, Sendable, Equatable {
    public var text: String
    public var model: String
    /// SHA-256 of the SKILL.md this summary was generated from.
    public var contentHash: String
    public var createdAt: Date

    public init(text: String, model: String, contentHash: String, createdAt: Date = Date()) {
        self.text = text
        self.model = model
        self.contentHash = contentHash
        self.createdAt = createdAt
    }
}

/// Which AI backend to talk to.
public enum AIBackend: String, Codable, Sendable, CaseIterable {
    case ollama
    case openAICompatible

    public var title: String {
        switch self {
        case .ollama: return "Ollama (local)"
        case .openAICompatible: return "OpenAI-compatible API"
        }
    }
}

public struct AISettings: Codable, Sendable, Equatable {
    public var backend: AIBackend
    public var baseURL: String
    public var model: String
    /// Whether an API key has been stored in the Keychain. The key itself
    /// never lives in the catalog file.
    public var hasAPIKey: Bool

    public init(
        backend: AIBackend = .ollama,
        baseURL: String = "http://localhost:11434",
        model: String = "",
        hasAPIKey: Bool = false
    ) {
        self.backend = backend
        self.baseURL = baseURL
        self.model = model
        self.hasAPIKey = hasAPIKey
    }
}

/// Everything Skillbox persists that cannot be derived from SKILL.md.
public struct CatalogState: Codable, Sendable, Equatable {
    /// User-assigned category per skill id, overriding inference.
    public var categoryOverrides: [String: Category]
    /// User-assigned source group per skill id, overriding inference.
    public var sourceOverrides: [String: String]
    /// Groups created or renamed by the user.
    public var customGroups: [SourceGroup]
    /// Install records keyed by skill id (folder name).
    public var installRecords: [String: InstallRecord]
    /// Cached AI summaries keyed by skill id (legacy compatibility).
    public var summaries: [String: AISummary]
    /// Structured Chinese copy keyed by skill id.
    public var explanations: [String: ChineseExplanation]?
    public var aiSettings: AISettings
    /// Whether a GitHub token is stored in the Keychain.
    public var hasGitHubToken: Bool
    /// Set once the user has reviewed the inferred source groups.
    public var didReviewSources: Bool

    public init(
        categoryOverrides: [String: Category] = [:],
        sourceOverrides: [String: String] = [:],
        customGroups: [SourceGroup] = [],
        installRecords: [String: InstallRecord] = [:],
        summaries: [String: AISummary] = [:],
        explanations: [String: ChineseExplanation]? = nil,
        aiSettings: AISettings = AISettings(),
        hasGitHubToken: Bool = false,
        didReviewSources: Bool = false
    ) {
        self.categoryOverrides = categoryOverrides
        self.sourceOverrides = sourceOverrides
        self.customGroups = customGroups
        self.installRecords = installRecords
        self.summaries = summaries
        self.explanations = explanations
        self.aiSettings = aiSettings
        self.hasGitHubToken = hasGitHubToken
        self.didReviewSources = didReviewSources
    }
}

/// Reads and writes `catalog.json`.
public final class CatalogStore: @unchecked Sendable {
    public let fileURL: URL

    /// - Parameter fileURL: defaults to
    ///   `~/Library/Application Support/Skillbox/catalog.json`.
    public init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first ?? FileManager.default.homeDirectoryForCurrentUser
            self.fileURL = base
                .appendingPathComponent("Skillbox", isDirectory: true)
                .appendingPathComponent("catalog.json")
        }
    }

    /// Returns an empty state when the file is missing or unreadable, so a
    /// corrupt catalog never blocks launching the app.
    public func load() -> CatalogState {
        guard let data = try? Data(contentsOf: fileURL) else { return CatalogState() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(CatalogState.self, from: data)) ?? CatalogState()
    }

    public func save(_ state: CatalogState) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(state)
        // Atomic write so a crash mid-save cannot truncate the catalog.
        try data.write(to: fileURL, options: .atomic)
    }
}
