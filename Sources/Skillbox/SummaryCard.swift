import SwiftUI
import SkillboxCore

struct SummaryCard: View {
    @Bindable var model: AppModel
    let skill: Skill
    @State private var busy = false
    @State private var failure = ""
    @State private var editing = false
    @State private var purpose = ""
    @State private var scenario = ""
    @State private var requirements = ""
    @State private var confirmCloudUpload = false
    private var copy: ChineseExplanation? { model.explanation(skill) }
    var body: some View {
        GroupBox("中文用途说明") {
            VStack(alignment: .leading, spacing: 12) {
                if let copy, ChineseCopyPolicy.isDisplayable(copy) {
                    Text(copy.purpose).font(.headline).textSelection(.enabled)
                    LabeledContent("适合", value: copy.scenario)
                    LabeledContent("需要", value: copy.requirements)
                    if !copy.isCurrent(skill.markdown) { Label("原始内容已更新，请检查这份说明。", systemImage: "clock").font(.caption).foregroundStyle(.orange) }
                    if copy.manuallyEdited { Text("已人工修正 · 自动生成不会覆盖").font(.caption).foregroundStyle(.secondary) }
                    else if copy.needsReview { Label("AI 初稿 · 请核对用途和必要条件", systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.orange) }
                    DisclosureGroup("查看原文依据") {
                        ForEach(Array(copy.evidence.enumerated()), id: \.offset) { _, quote in Text(quote).font(.caption).textSelection(.enabled) }
                    }
                } else if let copy {
                    Text("旧说明不是简体中文，请重新生成或人工编辑。").foregroundStyle(.secondary)
                    if !copy.isCurrent(skill.markdown) { Label("原始内容已更新，请检查这份说明。", systemImage: "clock").font(.caption).foregroundStyle(.orange) }
                    if copy.manuallyEdited { Text("已人工修正 · 自动生成不会覆盖").font(.caption).foregroundStyle(.secondary) }
                    else if copy.needsReview { Text("AI 初稿 · 请核对用途和必要条件").font(.caption).foregroundStyle(.orange) }
                    DisclosureGroup("查看原文依据") {
                        ForEach(Array(copy.evidence.enumerated()), id: \.offset) { _, quote in Text(quote).font(.caption).textSelection(.enabled) }
                    }
                } else { Text("用一句中文解释用途，并说明适用任务与必要条件。").foregroundStyle(.secondary) }
                if busy { ProgressView("正在核对原始说明…") }
                if !failure.isEmpty { Text(failure).font(.caption).foregroundStyle(.orange) }
                HStack {
                    Button(copy == nil ? "生成说明" : "重新生成", systemImage: "sparkles") {
                        if model.catalog.aiSettings.backend == .openAICompatible { confirmCloudUpload = true }
                        else { generate() }
                    }.disabled(busy || model.batchBusy || copy?.manuallyEdited == true)
                    Button("人工编辑", systemImage: "pencil") {
                        purpose = copy?.purpose ?? ""; scenario = copy?.scenario ?? ""; requirements = copy?.requirements ?? "未注明"; editing = true
                    }
                }
                if model.catalog.aiSettings.backend == .openAICompatible { Text("生成会把此 skill 的说明发送到设置中的云端 AI 服务。").font(.caption).foregroundStyle(.secondary) }
            }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
        }
        .confirmationDialog("发送此技能说明到云端 AI？", isPresented: $confirmCloudUpload, titleVisibility: .visible) {
            Button("发送并生成") { generate() }
            Button("取消", role: .cancel) {}
        } message: { Text("SKILL.md 正文将发送到你配置的 OpenAI-compatible 服务，并可能产生模型费用。") }
        .sheet(isPresented: $editing) {
            VStack(alignment: .leading, spacing: 16) {
                Text("编辑中文说明").font(.title2)
                TextField("一句话用途", text: $purpose)
                TextField("适合什么任务", text: $scenario)
                TextField("账号、平台或软件条件", text: $requirements)
                HStack {
                    Button("取消") { editing = false }
                    if let copy, copy.needsReview && !copy.manuallyEdited {
                        Button("确认无误") {
                            var confirmed = copy; confirmed.needsReview = false; model.saveExplanation(confirmed, for: skill)
                        }
                    }
                    Spacer()
                    Button("保存并保护") {
                        let updated = ChineseExplanation(purpose: purpose, scenario: scenario, requirements: requirements, kind: copy?.kind ?? "人工说明", evidence: copy?.evidence ?? [], model: "人工编辑", sourceHash: ChineseExplanation.hash(skill.markdown), manuallyEdited: true, needsReview: false)
                        model.saveExplanation(updated, for: skill); editing = false
                    }.disabled(purpose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }.padding(24).frame(width: 540)
        }
    }
    private func generate() {
        busy = true; failure = ""
        Task { @MainActor in
            defer { busy = false }
            do { try await model.generateExplanation(skill) }
            catch { failure = error.localizedDescription }
        }
    }
}
