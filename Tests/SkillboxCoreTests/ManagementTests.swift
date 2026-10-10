import Foundation
import Testing
@testable import SkillboxCore

struct ManagementTests {
    @Test func toggleRoundTripAndConflict() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let roots = SkillRoots(enabled: root.appendingPathComponent("enabled"), disabled: root.appendingPathComponent("disabled"))
        let folder = roots.enabled.appendingPathComponent("example")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try "---\nname: example\ndescription: Test skill\n---\nBody".write(to: folder.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        let skills = SkillScanner.scan(roots: roots)
        #expect(skills.count == 1)
        let skill = try #require(skills.first)
        try SkillToggler.setEnabled(skill, false, roots: roots)
        let disabled = try #require(SkillScanner.scan(roots: roots).first)
        #expect(!disabled.enabled)
        try SkillToggler.setEnabled(disabled, true, roots: roots)
        #expect(SkillScanner.scan(roots: roots).first?.enabled == true)
        try FileManager.default.createDirectory(at: roots.disabled.appendingPathComponent("example"), withIntermediateDirectories: true)
        #expect(throws: ToggleError.self) { try SkillToggler.setEnabled(skill, false, roots: roots) }
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("SKILL.md").path))
    }
    @Test func catalogRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("catalog.json")
        let store = CatalogStore(fileURL: url)
        var state = CatalogState()
        state.categoryOverrides["example"] = .scienceBio
        state.sourceOverrides["example"] = "manual:mine"
        try store.save(state)
        #expect(store.load() == state)
    }
    @Test func metadataClassification() {
        #expect(Categorizer.categorize(name: "scanpy", description: "single-cell RNA-seq analysis") == .scienceBio)
        #expect(Categorizer.categorize(name: "docx", description: "Word documents") == .documentsOffice)
        #expect(Categorizer.categorize(name: "brainstorming", description: "Creative planning") == .devWorkflow)
    }
}
