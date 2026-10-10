import SwiftUI
import SkillboxCore

struct SkillDetailView: View {
    @Bindable var model: AppModel
    let skill: Skill
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top) {
                    Image(systemName: skill.category.symbol).font(.largeTitle).foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(skill.name).font(.largeTitle.bold()).textSelection(.enabled)
                        Text(skill.sourceID ?? "来源待确认").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("启用", isOn: Binding(get: { skill.enabled }, set: { model.toggle(skill, to: $0) })).toggleStyle(.switch)
                }
                SummaryCard(model: model, skill: skill)
                HStack(alignment: .top, spacing: 24) {
                    VStack(alignment: .leading) { Text("作者").foregroundStyle(.secondary); Text(skill.author ?? "未注明") }
                    VStack(alignment: .leading) { Text("许可").foregroundStyle(.secondary); Text(skill.license ?? "未注明") }
                    VStack(alignment: .leading) { Text("文件").foregroundStyle(.secondary); Text("\(skill.fileCount) · \(ByteCountFormatter.string(fromByteCount: skill.sizeBytes, countStyle: .file))") }
                }.font(.callout)
                Picker("分类", selection: Binding(get: { skill.category }, set: { model.updateCategory(skill, $0) })) {
                    ForEach(Category.displayOrder, id: \.self) { Text($0.title).tag($0) }
                }
                Picker("来源", selection: Binding(get: { skill.sourceID ?? SourceInferrer.unsortedID }, set: { model.source(skill, $0) })) {
                    ForEach(model.groups) { Text($0.displayName).tag($0.id) }
                }
                Button("在 Finder 中显示", systemImage: "folder") { NSWorkspace.shared.activateFileViewerSelecting([skill.folderURL]) }
                FileTreeView(root: skill.folderURL)
                Divider()
                Text("完整说明").font(.title2.bold())
                MarkdownContent(markdown: FrontmatterParser.parse(skill.markdown).body)
            }.padding(28)
        }.navigationTitle(skill.name)
    }
}

struct MarkdownContent: View {
    let markdown: String
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(markdown.components(separatedBy: "\n\n").enumerated()), id: \.offset) { _, paragraph in
                if paragraph.hasPrefix("# ") {
                    Text(String(paragraph.dropFirst(2))).font(.title.bold())
                } else if paragraph.hasPrefix("## ") {
                    Text(String(paragraph.dropFirst(3))).font(.title2.bold())
                } else if paragraph.hasPrefix("### ") {
                    Text(String(paragraph.dropFirst(4))).font(.headline)
                } else {
                    Text((try? AttributedString(markdown: paragraph, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(paragraph))
                        .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                }
            }
        }.lineSpacing(4)
    }
}
