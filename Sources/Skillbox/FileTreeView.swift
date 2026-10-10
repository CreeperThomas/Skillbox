import SwiftUI
import SkillboxCore

struct FileTreeView: View {
    let root: URL
    @State private var files: [URL] = []
    @State private var preview = ""
    var body: some View {
        DisclosureGroup("文件夹内容") {
            ForEach(files, id: \.path) { url in
                Button(String(url.path.dropFirst(root.path.count + 1))) {
                    guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isSymbolicLinkKey]), values.isSymbolicLink != true, (values.fileSize ?? 0) < 500_000 else { preview = "文件过大或是链接，请在 Finder 中打开。"; return }
                    preview = (try? String(contentsOf: url, encoding: .utf8)) ?? "无法作为文本预览。"
                }.buttonStyle(.plain).font(.caption.monospaced())
            }
            if !preview.isEmpty { Text(preview).font(.caption.monospaced()).textSelection(.enabled).lineLimit(60) }
        }.task {
            let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
            files = (enumerator?.allObjects as? [URL] ?? []).filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }.sorted { $0.path < $1.path }
        }
    }
}
