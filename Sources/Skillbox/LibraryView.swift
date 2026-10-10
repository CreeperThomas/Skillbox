import SwiftUI
import SkillboxCore

struct LibraryView: View {
    @Bindable var model: AppModel
    @State private var pendingGroup: SourceGroup?
    var body: some View {
        NavigationSplitView {
            List(selection: $model.filter) {
                Section("资料库") {
                    Label("全部 · \(model.skills.count)", systemImage: "square.stack.3d.up").tag("all")
                    Label("已启用", systemImage: "checkmark.circle").tag("enabled")
                    Label("已禁用", systemImage: "pause.circle").tag("disabled")
                    Label("最近添加", systemImage: "clock").tag("recent")
                }
                Section("分类") {
                    ForEach(Category.displayOrder, id: \.rawValue) { category in
                        Label(category.title, systemImage: category.symbol).tag("category:" + category.rawValue)
                    }
                }
                Section("来源") {
                    ForEach(model.groups) { group in
                        DisclosureGroup {
                            ForEach(model.skills.filter { ($0.sourceID ?? SourceInferrer.unsortedID) == group.id }) { skill in
                                Button(skill.name) { model.filter = "source:" + group.id; model.selectedID = skill.id }
                                    .buttonStyle(.plain).foregroundStyle(skill.enabled ? .primary : .secondary)
                            }
                        } label: {
                            HStack {
                                Button { model.filter = "source:" + group.id } label: {
                                    Label(group.displayName, systemImage: "folder").lineLimit(1)
                                }.buttonStyle(.plain)
                                Spacer()
                                let members = model.skills.filter { ($0.sourceID ?? SourceInferrer.unsortedID) == group.id }
                                Toggle("启用来源", isOn: Binding(get: { members.contains { $0.enabled } }, set: { on in
                                    if !on && members.filter({ $0.enabled }).count > 10 { pendingGroup = group }
                                    else { model.toggleGroup(group, enabled: on) }
                                })).labelsHidden().toggleStyle(.switch).controlSize(.mini)
                            }
                        }
                    }
                }
                Section("发现") {
                    Label("搜索 GitHub", systemImage: "globe").tag("discover")
                    Label("问 AI", systemImage: "sparkles").tag("ask")
                }
                Section("说明生成") {
                    Menu {
                        Button("先生成15项") { model.startBatch(limit: 15) }
                        Button("生成所有待处理项") { model.startBatch(limit: model.skills.count) }
                    } label: { Label("生成中文用途说明", systemImage: "text.badge.sparkles") }.disabled(model.batchBusy)
                    if model.catalog.aiSettings.backend == .openAICompatible { Text("发送说明到云端模型，产生 API 费用。").font(.caption).foregroundStyle(.secondary) }
                    if model.batchBusy {
                        Text(model.batchProgress).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        Button("暂停队列", systemImage: "pause.fill") { model.pauseBatch() }
                    } else if !model.batchProgress.isEmpty { Text(model.batchProgress).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                }
            }
            .navigationTitle("Skillbox")
            .navigationSplitViewColumnWidth(min: 230, ideal: 270)
        } content: {
            List(model.filtered, selection: $model.selectedID) { skill in
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Image(systemName: skill.category.symbol).foregroundStyle(.secondary)
                        Text(skill.name).font(.headline)
                        if !skill.enabled { Image(systemName: "pause.circle").foregroundStyle(.secondary) }
                    }
                    Text(model.purpose(skill) + (model.explanation(skill)?.needsReview == true ? " · 待复核" : "")).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                    Text(skill.category.title).font(.caption).foregroundStyle(.secondary)
                }.padding(.vertical, 5).tag(skill.id)
                    .contextMenu {
                        Button(skill.enabled ? "禁用" : "启用") { model.toggle(skill, to: !skill.enabled) }
                        Button("在 Finder 中显示") { NSWorkspace.shared.activateFileViewerSelecting([skill.folderURL]) }
                    }
            }
            .navigationTitle(model.filter == "discover" ? "发现" : "Skills")
            .searchable(text: $model.query, prompt: "搜索名称、用途和标签")
            .navigationSplitViewColumnWidth(min: 280, ideal: 350)
        } detail: {
            if model.filter == "discover" { DiscoverView(model: model) }
            else if model.filter == "ask" { AskView(model: model) }
            else if let skill = model.selected { SkillDetailView(model: model, skill: skill).id(skill.id) }
            else { ContentUnavailableView("选择一个 Skill", systemImage: "square.stack.3d.up", description: Text("查看用途、来源和完整说明")) }
        }
        .toolbar { Button { Task { await model.refresh() } } label: { Label("刷新", systemImage: "arrow.clockwise") }.disabled(model.loading) }
        .task { await model.refresh() }
        .alert("操作未完成", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) { Button("好") { model.error = nil } } message: { Text(model.error ?? "") }
        .confirmationDialog("禁用这一来源下的所有 skills？", isPresented: Binding(get: { pendingGroup != nil }, set: { if !$0 { pendingGroup = nil } })) {
            Button("全部禁用", role: .destructive) { if let group = pendingGroup { model.toggleGroup(group, enabled: false) }; pendingGroup = nil }
        } message: { Text("文件会移到禁用目录，之后可随时重新启用。已经加载到会话中的内容可能需要新建会话才会更新。") }
    }
}
