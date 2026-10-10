import SwiftUI
import SkillboxCore

@MainActor @Observable final class AppModel {
    var skills: [Skill] = []
    var catalog: CatalogState
    var roots: SkillRoots = .standard()
    var filter = "all"
    var selectedID: String?
    var query = ""
    var error: String?
    var batchBusy = false
    var batchProgress = ""
    var batchTask: Task<Void, Never>?
    var loading = false
    let store = CatalogStore()
    init() { catalog = store.load() }
    var groups: [SourceGroup] { SourceInferrer.groups(for: skills, groups: catalog.customGroups) }
    var selected: Skill? { skills.first { $0.id == selectedID } }
    var filtered: [Skill] {
        skills.filter { skill in
            let matches: Bool
            if filter == "enabled" { matches = skill.enabled }
            else if filter == "disabled" { matches = !skill.enabled }
            else if filter.hasPrefix("category:") { matches = skill.category.rawValue == String(filter.dropFirst(9)) }
            else if filter.hasPrefix("source:") { matches = (skill.sourceID ?? SourceInferrer.unsortedID) == String(filter.dropFirst(7)) }
            else { matches = true }
            let explanation = catalog.explanations?[skill.id]
            let humanText = [explanation?.purpose, explanation?.scenario, explanation?.requirements].compactMap { $0 }.filter(ChineseCopyPolicy.isSimplifiedChinese).joined(separator: " ")
            let displayPurpose = ChineseCopyPolicy.displayPurpose(explanation, englishFallback: skill.description)
            return matches && (query.isEmpty || (skill.name + " " + displayPurpose + " " + humanText + " " + skill.tags.joined(separator: " ")).localizedCaseInsensitiveContains(query))
        }.sorted { filter == "recent" ? ($0.modifiedAt ?? .distantPast) > ($1.modifiedAt ?? .distantPast) : $0.name < $1.name }
    }
    func refresh() async {
        loading = true
        // The local batch generator may update catalog.json while the app is
        // running; reload it on Refresh so new Chinese copy appears immediately.
        catalog = store.load()
        let roots = roots; let state = catalog
        skills = await Task.detached { SkillScanner.scan(roots: roots, overrides: state) }.value
        if selectedID == nil { selectedID = filtered.first?.id }
        loading = false
    }
    func save() {
        do {
            // Preserve copies saved by the external local batch since the last
            // refresh. Newer manual edits take precedence over generated copy.
            let disk = store.load()
            for (id, copy) in disk.explanations ?? [:] {
                let current = catalog.explanations?[id]
                if current == nil || (copy.manuallyEdited && current?.manuallyEdited != true) || (current?.manuallyEdited != true && copy.updatedAt > current!.updatedAt) {
                    if catalog.explanations == nil { catalog.explanations = [:] }
                    catalog.explanations?[id] = copy
                }
            }
            try store.save(catalog)
        } catch { self.error = error.localizedDescription }
    }
    func explanation(_ skill: Skill) -> ChineseExplanation? { catalog.explanations?[skill.id] }
    func purpose(_ skill: Skill) -> String {
        ChineseCopyPolicy.displayPurpose(explanation(skill), englishFallback: skill.description)
    }
    func saveExplanation(_ copy: ChineseExplanation, for skill: Skill) {
        if catalog.explanations == nil { catalog.explanations = [:] }
        catalog.explanations?[skill.id] = copy
        save()
    }
    func generateExplanation(_ skill: Skill) async throws {
        guard explanation(skill)?.manuallyEdited != true else { throw InstallFailure.invalid("此说明已经人工修正，自动生成不会覆盖。") }
        var settings = catalog.aiSettings
        if settings.backend == .ollama && settings.model.isEmpty {
            settings.model = try await AIService(settings: settings).models().first ?? ""
            catalog.aiSettings = settings; save()
        }
        let copy = try await ExplanationGenerator.generate(skill: skill, settings: settings)
        try Task.checkCancellation()
        // An edit may have been saved while the request was running.
        guard explanation(skill)?.manuallyEdited != true else { return }
        saveExplanation(copy, for: skill)
    }
    func startBatch(limit: Int = 15) {
        guard !batchBusy else { return }
        let queue = Array(skills.filter { skill in
            guard let copy = explanation(skill) else { return true }
            return !copy.manuallyEdited && (!copy.isCurrent(skill.markdown) || !ChineseCopyPolicy.isDisplayable(copy))
        }.sorted { $0.name < $1.name }.prefix(max(0, limit)))
        batchBusy = true
        batchTask = Task { @MainActor in
            defer { batchBusy = false; batchTask = nil }
            var completed = 0; var failures = 0
            for skill in queue {
                if Task.isCancelled { break }
                batchProgress = "正在生成 \(completed + failures + 1)/\(queue.count)：\(skill.name)"
                do { try await generateExplanation(skill); completed += 1 }
                catch is CancellationError { break }
                catch { failures += 1; self.error = "\(skill.name)：\(error.localizedDescription)" }
            }
            batchProgress = "已保存 \(completed) 项，失败 \(failures) 项。继续生成会跳过已完成和人工编辑的说明。"
        }
    }
    func pauseBatch() { batchTask?.cancel() }

    func toggle(_ skill: Skill, to enabled: Bool) {
        do { try SkillToggler.setEnabled(skill, enabled, roots: roots); Task { await refresh() } }
        catch { self.error = error.localizedDescription }
    }
    func toggleGroup(_ group: SourceGroup, enabled: Bool) {
        let members = skills.filter { ($0.sourceID ?? SourceInferrer.unsortedID) == group.id }
        let result = SkillToggler.setEnabled(members, enabled, roots: roots)
        if let failure = result.failure { error = "已变更 \(result.moved.count) 项。\(failure.error.localizedDescription)" }
        Task { await refresh() }
    }
    func updateCategory(_ skill: Skill, _ value: SkillboxCore.Category) {
        catalog.categoryOverrides[skill.id] = value; save(); Task { await refresh() }
    }
    func source(_ skill: Skill, _ value: String) {
        catalog.sourceOverrides[skill.id] = value; save(); Task { await refresh() }
    }
}
