import Foundation

public struct SkillRecommendation: Sendable, Equatable, Identifiable {
    public let skill: Skill
    public let score: Int
    public var id: String { skill.id }
    public init(skill: Skill, score: Int) { self.skill = skill; self.score = score }
}

public enum RecommenderError: LocalizedError, Equatable {
    case unknownSkill(String)
    public var errorDescription: String? { if case .unknownSkill(let id) = self { return "Unknown skill id: \(id)" }; return nil }
}

/// Deterministic, local recommendation search. It never trusts an LLM-provided id.
public struct Recommender: Sendable {
    public init() {}

    public func recommend(query: String, from skills: [Skill], limit: Int = 10) -> [SkillRecommendation] {
        let terms = tokenize(query)
        guard !terms.isEmpty else { return [] }
        return skills.compactMap { skill in
            let haystack = tokenize([skill.id, skill.name, skill.description, skill.tags.joined(separator: " ")].joined(separator: " "))
            let score = terms.reduce(0) { total, term in total + (haystack.contains(term) ? 1 : 0) }
            return score == 0 ? nil : SkillRecommendation(skill: skill, score: score)
        }.sorted { $0.score == $1.score ? $0.skill.name < $1.skill.name : $0.score > $1.score }.prefix(max(0, limit)).map { $0 }
    }

    public func verify(ids: [String], against skills: [Skill]) throws -> [Skill] {
        let index = Dictionary(uniqueKeysWithValues: skills.map { ($0.id, $0) })
        return try ids.map { id in guard let skill = index[id] else { throw RecommenderError.unknownSkill(id) }; return skill }
    }

    private func tokenize(_ text: String) -> Set<String> {
        let lower = text.lowercased()
        var result = Set<String>()
        var current = ""
        for scalar in lower.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) { current.unicodeScalars.append(scalar) }
            else if !current.isEmpty { result.insert(current); current = "" }
        }
        if !current.isEmpty { result.insert(current) }
        // Keep Chinese single-character terms useful for short queries.
        for scalar in lower.unicodeScalars where scalar.properties.isIdeographic { result.insert(String(scalar)) }
        return result
    }
}
