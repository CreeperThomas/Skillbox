import Foundation

/// Walks the enabled and disabled skill roots and builds `Skill` values.
public enum SkillScanner {
    /// Scans both roots. A folder is a skill when it contains a `SKILL.md`
    /// (case-insensitive). Non-directories and folders without one are skipped.
    ///
    /// - Parameters:
    ///   - roots: enabled + disabled directory URLs.
    ///   - overrides: user corrections applied after inference —
    ///     `categoryOverrides` and `sourceOverrides` keyed by folder name.
    public static func scan(
        roots: SkillRoots,
        overrides: CatalogState = CatalogState(),
        fileManager: FileManager = .default
    ) -> [Skill] {
        var skills: [Skill] = []
        skills += scanRoot(roots.enabled, enabled: true, overrides: overrides, fileManager: fileManager)
        skills += scanRoot(roots.disabled, enabled: false, overrides: overrides, fileManager: fileManager)
        return skills.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func scanRoot(
        _ root: URL,
        enabled: Bool,
        overrides: CatalogState,
        fileManager: FileManager
    ) -> [Skill] {
        guard let entries = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return entries.compactMap { folder -> Skill? in
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: folder.path, isDirectory: &isDirectory),
                  isDirectory.boolValue,
                  let skillFile = skillFileURL(in: folder, fileManager: fileManager),
                  let markdown = try? String(contentsOf: skillFile, encoding: .utf8)
            else { return nil }

            let parsed = FrontmatterParser.parse(markdown)
            let folderName = folder.lastPathComponent
            let hasFrontmatter = !parsed.fields.isEmpty

            let name = parsed["name"]?.isEmpty == false ? parsed["name"]! : folderName
            let description = resolveDescription(parsed: parsed, fallback: markdown)

            let stats = folderStats(folder, fileManager: fileManager)
            let modified = (try? folder.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate

            let category = overrides.categoryOverrides[folderName]
                ?? Categorizer.categorize(name: name, description: description, tags: parsed.tags)

            let recordedSource = overrides.installRecords[folderName].map { "github:" + $0.repo }
            let sourceID = overrides.sourceOverrides[folderName]
                ?? recordedSource
                ?? SourceInferrer.infer(parsed: parsed, markdown: markdown)?.id

            return Skill(
                id: folderName,
                name: name,
                description: description,
                version: parsed["version"] ?? parsed.metadata["version"],
                author: parsed["author"] ?? parsed.metadata["skill-author"],
                license: parsed["license"],
                tags: parsed.tags,
                folderURL: folder,
                enabled: enabled,
                fileCount: stats.files,
                sizeBytes: stats.bytes,
                category: category,
                sourceID: sourceID,
                hasFrontmatter: hasFrontmatter,
                modifiedAt: modified,
                markdown: markdown
            )
        }
    }

    static func skillFileURL(in folder: URL, fileManager: FileManager) -> URL? {
        let canonical = folder.appendingPathComponent("SKILL.md")
        if fileManager.fileExists(atPath: canonical.path) { return canonical }
        // Some vendored skills use a different case.
        guard let entries = try? fileManager.contentsOfDirectory(atPath: folder.path) else { return nil }
        guard let match = entries.first(where: { $0.lowercased() == "skill.md" }) else { return nil }
        return folder.appendingPathComponent(match)
    }

    /// Frontmatter description, else the first non-empty, non-heading body line.
    static func resolveDescription(parsed: Frontmatter, fallback: String) -> String {
        if let description = parsed["description"], !description.isEmpty {
            return description
        }
        for line in parsed.body.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") || trimmed.hasPrefix("---") { continue }
            return trimmed
        }
        return ""
    }

    /// Counts files and total bytes under `folder`, skipping hidden entries.
    static func folderStats(_ folder: URL, fileManager: FileManager) -> (files: Int, bytes: Int64) {
        guard let enumerator = fileManager.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return (0, 0) }

        var files = 0
        var bytes: Int64 = 0
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true
            else { continue }
            files += 1
            bytes += Int64(values.fileSize ?? 0)
        }
        return (files, bytes)
    }
}
