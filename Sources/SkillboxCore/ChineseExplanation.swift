import Foundation
import CryptoKit

/// Human-facing Chinese copy generated from a skill's local source text.
/// English `Skill.name` and the original markdown remain unchanged for agents.
public struct ChineseExplanation: Codable, Sendable, Equatable {
    public var purpose: String
    public var scenario: String
    public var requirements: String
    public var kind: String
    public var evidence: [String]
    public var model: String
    public var sourceHash: String
    public var manuallyEdited: Bool
    public var needsReview: Bool
    public var updatedAt: Date

    public init(purpose: String, scenario: String, requirements: String, kind: String, evidence: [String], model: String, sourceHash: String, manuallyEdited: Bool = false, needsReview: Bool? = nil, updatedAt: Date = Date()) {
        self.purpose = purpose; self.scenario = scenario; self.requirements = requirements; self.kind = kind; self.evidence = evidence; self.model = model; self.sourceHash = sourceHash; self.manuallyEdited = manuallyEdited; self.needsReview = needsReview ?? !manuallyEdited; self.updatedAt = updatedAt
    }
    private enum CodingKeys: String, CodingKey { case purpose, scenario, requirements, kind, evidence, model, sourceHash, manuallyEdited, needsReview, updatedAt }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let manuallyEdited = try container.decodeIfPresent(Bool.self, forKey: .manuallyEdited) ?? false
        purpose = try container.decode(String.self, forKey: .purpose)
        scenario = try container.decode(String.self, forKey: .scenario)
        requirements = try container.decode(String.self, forKey: .requirements)
        kind = try container.decode(String.self, forKey: .kind)
        evidence = try container.decode([String].self, forKey: .evidence)
        model = try container.decode(String.self, forKey: .model)
        sourceHash = try container.decode(String.self, forKey: .sourceHash)
        self.manuallyEdited = manuallyEdited
        needsReview = try container.decodeIfPresent(Bool.self, forKey: .needsReview) ?? !manuallyEdited
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
    public static func hash(_ source: String) -> String { SHA256.hash(data: Data(source.utf8)).map { String(format: "%02x", $0) }.joined() }
    /// Only the supplied, non-omitted text can substantiate generated copy.
    public static func evidenceText(_ skillMarkdown: String) -> String {
        let firstLine = skillMarkdown.components(separatedBy: "\n").first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let parsed = FrontmatterParser.parse(skillMarkdown)
        let hasValidFrontmatter = firstLine?.trimmingCharacters(in: .whitespaces) == "---" && parsed.body != skillMarkdown
        let full = hasValidFrontmatter ? parsed.body : skillMarkdown
        if full.count <= 18000 { return full }
        return String(full.prefix(14000)) + "\n\n" + String(full.suffix(4000))
    }
    public func isCurrent(_ source: String) -> Bool { sourceHash == Self.hash(source) }
    public var shortText: String { purpose }
    public var fullText: String { [purpose, scenario.isEmpty ? "" : "适合：" + scenario].filter { !$0.isEmpty }.joined(separator: "\n") }
    public static func parse(_ json: String, source: String, evidenceSource: String? = nil, model: String, manuallyEdited: Bool = false) throws -> ChineseExplanation {
        struct Payload: Decodable { let purpose: String; let scenario: String; let requirements: String; let kind: String; let evidence: [String] }
        let object = json.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = object.data(using: .utf8), let payload = try? JSONDecoder().decode(Payload.self, from: data) else { throw ExplanationError.invalidJSON }
        let values = [payload.purpose, payload.scenario, payload.requirements, payload.kind]
        guard values.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }), payload.purpose.count <= 120, payload.scenario.count <= 180, payload.requirements.count <= 180 else { throw ExplanationError.invalidContent }
        guard ChineseCopyPolicy.isDisplayable(ChineseExplanation(purpose: payload.purpose, scenario: payload.scenario, requirements: payload.requirements, kind: payload.kind, evidence: payload.evidence, model: model, sourceHash: Self.hash(source))) else { throw ExplanationError.invalidContent }
        guard !payload.evidence.isEmpty, payload.evidence.allSatisfy({ evidence in !evidence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && evidence.count <= 200 && (evidenceSource ?? source).contains(evidence) }) else { throw ExplanationError.unsupportedEvidence }
        return ChineseExplanation(purpose: payload.purpose, scenario: payload.scenario, requirements: payload.requirements, kind: payload.kind, evidence: payload.evidence, model: model, sourceHash: Self.hash(source), manuallyEdited: manuallyEdited)
    }
}
/// Fail-closed presentation policy: never substitute an English agent trigger
/// description into a human-facing purpose field.
public enum ChineseCopyPolicy {
    public static func isSimplifiedChinese(_ text: String) -> Bool {
        let han = text.unicodeScalars.filter { (0x3400...0x9FFF).contains($0.value) }
        let latin = text.unicodeScalars.filter { CharacterSet.letters.contains($0) && !(0x3400...0x9FFF).contains($0.value) }
        // ICU conversion distinguishes Traditional forms without rejecting
        // characters shared by both scripts, such as 环境's 境 or 配置.
        let simplified = text.applyingTransform(StringTransform("Traditional-Simplified"), reverse: false) ?? text
        let traditional = simplified != text
        // Long product names and package lists can outweigh Chinese glue text
        // in a valid requirements field; English-only sentences still fail.
        return han.count >= 2 && latin.count <= max(32, han.count * 6) && !traditional
    }
    public static func isDisplayable(_ explanation: ChineseExplanation) -> Bool {
        isSimplifiedChinese(explanation.purpose) && isSimplifiedChinese(explanation.scenario) && isSimplifiedChinese(explanation.requirements)
    }
    public static func displayPurpose(_ explanation: ChineseExplanation?, englishFallback: String) -> String {
        guard let explanation, isDisplayable(explanation) else { return "中文用途说明待生成" }
        return explanation.purpose
    }
}

public enum ExplanationError: LocalizedError, Equatable {
    case invalidJSON, invalidContent, unsupportedEvidence
    public var errorDescription: String? { switch self { case .invalidJSON: return "AI 返回的中文说明格式无效。"; case .invalidContent: return "中文说明缺少字段或长度超限。"; case .unsupportedEvidence: return "中文说明包含原始 skill 中无法核验的事实。" } }
}
