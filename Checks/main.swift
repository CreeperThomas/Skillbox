import Foundation
import SkillboxCore

func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw InstallFailure.invalid("FAIL: " + message) }
    print("PASS: " + message)
}
let fm = FileManager.default
let root = fm.temporaryDirectory.appendingPathComponent("skillbox-check-" + UUID().uuidString)
try fm.createDirectory(at: root, withIntermediateDirectories: true)
defer { if root.lastPathComponent.hasPrefix("skillbox-check-") { try? fm.removeItem(at: root) } }
let parsed = FrontmatterParser.parse("---\nname: example\ndescription: Test skill\ntags: [One, Two]\n---\nBody")
try check(parsed["name"] == "example" && parsed.tags == ["One", "Two"], "frontmatter parsing")
let roots = SkillRoots(enabled: root.appendingPathComponent("enabled"), disabled: root.appendingPathComponent("disabled"))
let folder = roots.enabled.appendingPathComponent("example")
try fm.createDirectory(at: folder, withIntermediateDirectories: true)
try "---\nname: example\ndescription: Test skill\n---\nBody".write(to: folder.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
let initial = SkillScanner.scan(roots: roots)
try check(initial.count == 1 && initial[0].enabled, "directory scanning")
try SkillToggler.setEnabled(initial[0], false, roots: roots)
let disabled = SkillScanner.scan(roots: roots)
try check(disabled.count == 1 && !disabled[0].enabled, "disable moves skill")
try SkillToggler.setEnabled(disabled[0], true, roots: roots)
try check(fm.fileExists(atPath: folder.path), "enable restores skill")
try fm.createDirectory(at: roots.disabled.appendingPathComponent("example"), withIntermediateDirectories: true)
var refused = false
do { try SkillToggler.setEnabled(initial[0], false, roots: roots) } catch { refused = true }
try check(refused && fm.fileExists(atPath: folder.path), "conflict leaves source intact")
try check(!SkillInstaller.safePath("../escape") && !SkillInstaller.safePath("/absolute") && SkillInstaller.safePath("references/guide.md"), "download path protection")
let store = CatalogStore(fileURL: root.appendingPathComponent("catalog.json"))
var state = CatalogState(); state.categoryOverrides["example"] = .scienceBio
try store.save(state)
try check(store.load() == state, "catalog persistence")
try check(Categorizer.categorize(name: "scanpy", description: "single-cell RNA-seq") == .scienceBio, "scientific categorization")
print("8 checks passed")
let sourceText = "---\nname: example\ndescription: Protein analysis\n---\nRequires an account."
let explanationJSON = """
{"purpose":"提交蛋白实验并获取结果。","scenario":"已有蛋白序列，需要实验验证。","requirements":"需要平台账号。","kind":"外部服务","evidence":["Requires an account."]}
"""
let explanation = try ChineseExplanation.parse(explanationJSON, source: sourceText, model: "test")
try check(!ChineseCopyPolicy.isSimplifiedChinese("Use this skill whenever needed."), "English fallback is not valid simplified Chinese")
try check(ChineseCopyPolicy.isSimplifiedChinese("需要对数据进行处理，并配置软件环境。"), "shared characters in valid Simplified Chinese are accepted")
try check(ChineseCopyPolicy.isSimplifiedChinese("需要 Python 环境和 API 密钥。"), "technical names remain valid within Chinese requirements")
try check(ChineseCopyPolicy.isSimplifiedChinese("Python环境；依赖optlang求解器（GLPK/HIGHS/OSQP）；可选MATLAB I/O支持。"), "package lists do not invalidate Chinese requirements")
try check(ChineseCopyPolicy.displayPurpose(nil, englishFallback: "Use when working with time series") == "中文用途说明待生成", "English machine description is never shown as human purpose")
try check(ChineseCopyPolicy.displayPurpose(explanation, englishFallback: "Use this skill whenever") == "提交蛋白实验并获取结果。", "Chinese purpose wins over English machine description")
let englishCopy = ChineseExplanation(purpose: "Use this skill for time series.", scenario: "Use when working with temporal data.", requirements: "Python package", kind: "tool", evidence: ["evidence"], model: "old", sourceHash: "hash")
try check(ChineseCopyPolicy.displayPurpose(englishCopy, englishFallback: "Use this skill") == "中文用途说明待生成", "stale English cache cannot display as purpose")
try check(!ChineseCopyPolicy.isDisplayable(englishCopy), "English scenario and requirements invalidate cached copy")
let traditionalCopy = ChineseExplanation(purpose: "資料庫說明", scenario: "適合處理資料", requirements: "需要 Python 環境", kind: "工具", evidence: ["evidence"], model: "old", sourceHash: "hash")
try check(!ChineseCopyPolicy.isDisplayable(traditionalCopy), "traditional Chinese cache cannot pass simplified-Chinese filter")
try check(ExplanationGenerator.systemPrompt.contains("简体中文"), "generator explicitly requests simplified Chinese")
try check(explanation.purpose == "提交蛋白实验并获取结果。", "structured Chinese explanation")
try check(explanation.needsReview && !explanation.manuallyEdited, "generated explanation starts pending review")
let oldExplanationJSON = """
{"purpose":"用途","scenario":"场景","requirements":"条件","kind":"工具","evidence":["原文"],"model":"旧模型","sourceHash":"hash","manuallyEdited":false,"updatedAt":"2026-01-01T00:00:00Z"}
"""
let oldDecoder = JSONDecoder(); oldDecoder.dateDecodingStrategy = .iso8601
let oldDecoded = try? oldDecoder.decode(ChineseExplanation.self, from: Data(oldExplanationJSON.utf8))
try check(oldDecoded?.needsReview == true, "older structured explanation decodes as pending review")
let edited = ChineseExplanation(purpose: "人工确认用途", scenario: "人工核准场景", requirements: "未注明", kind: "人工说明", evidence: [], model: "人工编辑", sourceHash: ChineseExplanation.hash(sourceText), manuallyEdited: true)
try check(!edited.needsReview && edited.manuallyEdited, "manual copy marks reviewed and protected")
try check(ChineseExplanation.evidenceText(sourceText).contains("Protein analysis") == false, "frontmatter is excluded from semantic evidence")
try check(ChineseExplanation.evidenceText("  ---\nname: example\n---\nBody").contains("Body"), "indented frontmatter is removed from semantic evidence")
try check(ChineseExplanation.evidenceText("Plain text description").contains("Plain text"), "plain text fallback remains evidence")
try check(ChineseExplanation.evidenceText("---\nunterminated frontmatter").contains("unterminated"), "unterminated frontmatter remains evidence")
let promptSkill = Skill(id: "example", name: "example", description: "machine trigger description", folderURL: root, enabled: true, markdown: "---\nname: example\ndescription: machine trigger description\n---\n正文记载的实际能力")
let promptInput = ExplanationGenerator.input(promptSkill)
try check(!promptInput.contains("machine trigger description") && promptInput.contains("正文记载的实际能力"), "generator excludes agent trigger description")
try check(explanation.isCurrent(sourceText), "content hash validity")
try check(!explanation.isCurrent(sourceText + "changed"), "changed skills invalidate generated copy")
var badEvidenceRejected = false
do { _ = try ChineseExplanation.parse(explanationJSON.replacingOccurrences(of: "Requires an account.", with: "Invented evidence"), source: sourceText, model: "test") } catch { badEvidenceRejected = true }
try check(badEvidenceRejected, "unsupported evidence rejected")
var omittedEvidenceRejected = false
do { _ = try ChineseExplanation.parse(explanationJSON, source: "prefix Requires an account. suffix", evidenceSource: "prefix suffix", model: "test") } catch { omittedEvidenceRejected = true }
try check(omittedEvidenceRejected, "evidence must come from supplied text")
state.explanations = ["example": explanation]
try store.save(state)
try check(store.load().explanations?["example"]?.purpose == explanation.purpose && store.load().explanations?["example"]?.sourceHash == explanation.sourceHash, "Chinese copy persisted")
var emptyEvidenceRejected = false
do { _ = try ChineseExplanation.parse(explanationJSON.replacingOccurrences(of: "Requires an account.", with: ""), source: sourceText, model: "test") } catch { emptyEvidenceRejected = true }
try check(emptyEvidenceRejected, "empty evidence cannot substantiate copy")
var englishRejected = false
do { _ = try ChineseExplanation.parse(explanationJSON.replacingOccurrences(of: "提交蛋白实验并获取结果。", with: "Use this skill whenever needed."), source: sourceText, model: "test") } catch { englishRejected = true }
try check(englishRejected, "English trigger copy rejected")
if CommandLine.arguments.contains("--repair-local") {
    let skills = SkillScanner.scan(roots: .standard())
    let data = try Data(contentsOf: URL(fileURLWithPath: "build/chinese-repairs.json"))
    let entries = try JSONSerialization.jsonObject(with: data) as! [String: [String: Any]]
    let catalog = CatalogStore()
    var state = catalog.load()
    for (id, payload) in entries {
        guard let skill = skills.first(where: { $0.id == id }) else { throw InstallFailure.invalid("Missing skill: \(id)") }
        let json = String(decoding: try JSONSerialization.data(withJSONObject: payload), as: UTF8.self)
        let copy = try ChineseExplanation.parse(json, source: skill.markdown, evidenceSource: ChineseExplanation.evidenceText(skill.markdown), model: "原文核对补写")
        guard state.explanations?[id]?.manuallyEdited != true else { continue }
        if state.explanations == nil { state.explanations = [:] }
        state.explanations?[id] = copy
    }
    try catalog.save(state)
    let saved = catalog.load()
    let missing = skills.filter { saved.explanations?[$0.id].map(ChineseCopyPolicy.isDisplayable) != true }
    try check(missing.isEmpty, "all \(skills.count) local skills have displayable Chinese explanations")
    try Data("{}\n".utf8).write(to: URL(fileURLWithPath: "build/chinese-generation-report.json"), options: .atomic)
}
if CommandLine.arguments.contains("--all-local") {
    let allSkills = SkillScanner.scan(roots: .standard())
    var settings = AISettings()
    settings.model = try await AIService(settings: settings).models().first ?? ""
    guard !settings.model.isEmpty else { throw InstallFailure.invalid("Ollama 没有可用模型。") }
    let catalog = CatalogStore()
    var state = catalog.load()
    if state.explanations == nil { state.explanations = [:] }
    let reportURL = URL(fileURLWithPath: "build/chinese-generation-report.json")
    var failed: [String: String] = [:]
    var done = 0; var skipped = 0
    let priorFailures: Set<String> = (try? Set(JSONDecoder().decode([String: String].self, from: Data(contentsOf: reportURL)).keys)) ?? []
    try catalog.save(state)
    for (index, skill) in allSkills.enumerated() {
        print("开始 \(index + 1)/\(allSkills.count)：\(skill.name)")
        if let existing = state.explanations?[skill.id], existing.manuallyEdited { skipped += 1; continue }
        if let existing = state.explanations?[skill.id], existing.isCurrent(skill.markdown), ChineseCopyPolicy.isDisplayable(existing) { skipped += 1; continue }
        if !priorFailures.isEmpty && !priorFailures.contains(skill.id) { skipped += 1; continue }
        do {
            let explanation = try await ExplanationGenerator.generate(skill: skill, settings: settings)
            guard ChineseCopyPolicy.isDisplayable(explanation) else { throw ExplanationError.invalidContent }
            // Reload before each write to preserve app edits and settings made
            // while the local model was generating this entry.
            state = catalog.load()
            if state.explanations?[skill.id]?.manuallyEdited == true { skipped += 1; continue }
            if state.explanations == nil { state.explanations = [:] }
            state.explanations?[skill.id] = explanation
            try catalog.save(state)
            let reloaded = catalog.load()
            guard reloaded.explanations?[skill.id]?.purpose == explanation.purpose else { throw InstallFailure.invalid("保存后复读 catalog 不匹配") }
            done += 1
            print("\(index + 1)/\(allSkills.count) 已保存：\(skill.name) — \(explanation.purpose)")
        } catch {
            failed[skill.id] = error.localizedDescription
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(failed).write(to: reportURL, options: .atomic)
            print("\(index + 1)/\(allSkills.count) 待重试：\(skill.name) — \(error.localizedDescription)")
        }
    }
    let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(failed).write(to: reportURL, options: .atomic)
    print("本机中文说明队列完成：成功 \(done)，跳过 \(skipped)，待重试 \(failed.count)。Catalog: \(catalog.fileURL.path)")
}
if CommandLine.arguments.contains("--samples") {
    let allSkills = SkillScanner.scan(roots: .standard())
    let names = ["adaptyv", "aeon", "anndata", "brainstorming", "scanpy", "pdf", "docx", "pptx", "xlsx", "biopython", "sympy", "matplotlib", "arxiv", "test-driven-development", "nextflow"]
    let catalog = CatalogStore()
    var catalogState = catalog.load()
    if catalogState.explanations == nil { catalogState.explanations = [:] }
    let catalogURL = catalog.fileURL
    var settings = AISettings()
    settings.model = try await AIService(settings: settings).models().first ?? ""
    print("Sample model: \(settings.model)")
    var copies: [String: ChineseExplanation] = [:]
    for name in names {
        guard let skill = allSkills.first(where: { $0.name == name || $0.id == name }) else { continue }
        do {
            let copy = try await ExplanationGenerator.generate(skill: skill, settings: settings)
            copies[skill.id] = copy
            catalogState.explanations?[skill.id] = copy
            try catalog.save(catalogState)
            print("SAMPLE \(name): \(copy.purpose) | \(copy.scenario) | \(copy.requirements)")
        } catch { print("REVIEW \(name): \(error.localizedDescription)") }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(copies).write(to: URL(fileURLWithPath: "build/chinese-samples.json"), options: .atomic)
    }
    print("Saved \(copies.count) validated sample explanations to \(catalogURL.path)")
}
if CommandLine.arguments.contains("--network") {
    let plan = try await SkillInstaller().inspect("obra/superpowers")
    try check(!plan.candidates.isEmpty && plan.commit.count == 40, "GitHub pinned repository discovery")
    if let candidate = plan.candidates.first {
        let temporaryRoots = SkillRoots(enabled: root.appendingPathComponent("network"), disabled: root.appendingPathComponent("network-disabled"))
        let (name, record) = try await SkillInstaller().install(candidate, plan: plan, roots: temporaryRoots)
        try check(record.sha == plan.commit && fm.fileExists(atPath: temporaryRoots.enabled.appendingPathComponent(name).appendingPathComponent("SKILL.md").path), "real GitHub skill download into temporary directory")
    }
    let models = try await AIService(settings: AISettings()).models()
    try check(!models.isEmpty, "local Ollama model discovery")
    print("Network integration checks passed")
}
