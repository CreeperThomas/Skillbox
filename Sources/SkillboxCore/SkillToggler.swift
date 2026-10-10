import Foundation

public enum ToggleError: LocalizedError, Equatable {
    /// The destination folder already exists in the other root.
    case destinationExists(String)
    case moveFailed(from: String, to: String, reason: String)

    public var errorDescription: String? {
        switch self {
        case .destinationExists(let name):
            return "A skill named “\(name)” already exists in the destination folder."
        case .moveFailed(let from, let to, let reason):
            return "Could not move \(from) to \(to): \(reason)"
        }
    }
}

/// Moves skill folders between the enabled and disabled roots.
///
/// Disabling moves a folder out of `~/.agents/skills`, which is the directory
/// the agent runtime watches — so a disabled skill disappears from the agent
/// immediately, without any extra bookkeeping.
public enum SkillToggler {
    /// Moves `skill` into the root for the requested state and returns the new
    /// folder URL. Throws without touching the filesystem when the destination
    /// is occupied.
    @discardableResult
    public static func setEnabled(
        _ skill: Skill,
        _ enabled: Bool,
        roots: SkillRoots,
        fileManager: FileManager = .default
    ) throws -> URL {
        let destinationRoot = enabled ? roots.enabled : roots.disabled
        let source = skill.folderURL
        guard (try? source.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true,
              (try? destinationRoot.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else {
            throw ToggleError.moveFailed(from: source.path, to: destinationRoot.path, reason: "技能目录不能位于符号链接下。")
        }
        let destination = destinationRoot.appendingPathComponent(skill.id, isDirectory: true)

        if source.standardizedFileURL == destination.standardizedFileURL {
            return destination // already where it belongs
        }

        guard !fileManager.fileExists(atPath: destination.path) else {
            throw ToggleError.destinationExists(skill.id)
        }

        try fileManager.createDirectory(at: destinationRoot, withIntermediateDirectories: true)

        do {
            try fileManager.moveItem(at: source, to: destination)
        } catch {
            // Best-effort rollback: if the move half-completed, put it back.
            if fileManager.fileExists(atPath: destination.path),
               !fileManager.fileExists(atPath: source.path) {
                try? fileManager.moveItem(at: destination, to: source)
            }
            throw ToggleError.moveFailed(
                from: source.lastPathComponent,
                to: destinationRoot.lastPathComponent,
                reason: error.localizedDescription
            )
        }
        return destination
    }

    /// Enables or disables several skills in order, stopping at the first
    /// failure. Returns the ids that were moved and the error that stopped it,
    /// so the caller can report a partially applied change honestly.
    public static func setEnabled(
        _ skills: [Skill],
        _ enabled: Bool,
        roots: SkillRoots,
        fileManager: FileManager = .default
    ) -> (moved: [String], failure: (skill: Skill, error: Error)?) {
        var moved: [String] = []
        for skill in skills {
            if skill.enabled == enabled { continue }
            do {
                try setEnabled(skill, enabled, roots: roots, fileManager: fileManager)
                moved.append(skill.id)
            } catch {
                return (moved, (skill, error))
            }
        }
        return (moved, nil)
    }
}
