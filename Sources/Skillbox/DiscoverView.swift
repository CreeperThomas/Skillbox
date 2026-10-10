import SwiftUI
import SkillboxCore

struct DiscoverView: View {
    @Bindable var model: AppModel
    @State private var query = ""
    @State private var repoInput = ""
    @State private var hits: [SkillHit] = []
    @State private var repos: [RepoHit] = []
    @State private var plan: RepositoryPlan?
    @State private var selection: Set<String> = []
    @State private var busy = false
    @State private var status = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("发现 Skills").font(.title.bold())
            HStack {
                TextField("搜索技能或任务", text: $query).onSubmit { search() }
                Button("搜索", systemImage: "magnifyingglass", action: search).disabled(busy || query.isEmpty)
            }
            HStack {
                TextField("GitHub owner/repo", text: $repoInput).onSubmit { inspect(repoInput) }
                Button("查看仓库", systemImage: "folder.badge.plus") { inspect(repoInput) }.disabled(busy || repoInput.isEmpty)
            }
            if busy { ProgressView().controlSize(.small) }
            if !status.isEmpty { Text(status).font(.callout).foregroundStyle(.secondary).textSelection(.enabled) }
            if let plan {
                HStack {
                    Text(plan.repo.slug).font(.headline)
                    Spacer()
                    Button("全选") { selection = Set(plan.candidates.map(\.id)) }
                    Button("安装所选") { install(plan) }.disabled(selection.isEmpty || busy)
                }
                Text("下载后不会执行脚本。安装将影响 Agent 可加载的技能，请确认来源可信。").font(.caption).foregroundStyle(.secondary)
                List(plan.candidates) { candidate in
                    Toggle(isOn: Binding(get: { selection.contains(candidate.id) }, set: { if $0 { selection.insert(candidate.id) } else { selection.remove(candidate.id) } })) {
                        VStack(alignment: .leading) { Text(candidate.name); Text("\(candidate.path) · \(candidate.files.count) 文件").font(.caption).foregroundStyle(.secondary) }
                    }
                }
            } else {
                List {
                    Section("Skills 搜索") {
                        ForEach(hits) { hit in
                            HStack {
                                VStack(alignment: .leading) { Text(hit.name).font(.headline); Text("\(hit.source) · \(hit.installs ?? 0) 次安装").font(.caption).foregroundStyle(.secondary) }
                                Spacer()
                                Button("查看") { inspect(hit.source) }
                            }
                        }
                    }
                    Section("GitHub 仓库") {
                        ForEach(repos) { repo in
                            VStack(alignment: .leading, spacing: 5) {
                                HStack { Text(repo.fullName).font(.headline); Spacer(); Button("查看") { inspect(repo.fullName) } }
                                Text(repo.description ?? "").font(.callout).foregroundStyle(.secondary).lineLimit(3)
                                Text("★ \(repo.stars)").font(.caption)
                            }
                        }
                    }
                }
            }
        }.padding(24)
    }
    func search() {
        busy = true; status = "搜索中…"; plan = nil
        Task {
            do { hits = try await SkillSearch.search(query) } catch { status = error.localizedDescription }
            do { repos = try await GitHubClient(token: CredentialStore.get("github")).searchRepos(query: query + " skills") }
            catch { status += "\nGitHub：" + error.localizedDescription }
            if status == "搜索中…" { status = "\(hits.count) 个技能，\(repos.count) 个仓库" }
            busy = false
        }
    }
    func inspect(_ input: String) {
        busy = true; status = "读取仓库…"; selection = []
        Task {
            do {
                plan = try await SkillInstaller(token: CredentialStore.get("github")).inspect(input)
                status = "找到 \(plan?.candidates.count ?? 0) 个技能。选择后安装。"
            } catch { status = error.localizedDescription }
            busy = false
        }
    }
    func install(_ plan: RepositoryPlan) {
        busy = true
        Task {
            var installed = 0
            for candidate in plan.candidates where selection.contains(candidate.id) {
                status = "下载 \(candidate.name)…"
                do {
                    let (id, record) = try await SkillInstaller(token: CredentialStore.get("github")).install(candidate, plan: plan, roots: model.roots)
                    model.catalog.installRecords[id] = record
                    let sourceID = "github:" + record.repo
                    model.catalog.sourceOverrides[id] = sourceID
                    if !model.catalog.customGroups.contains(where: { $0.id == sourceID }) {
                        model.catalog.customGroups.append(SourceGroup(id: sourceID, displayName: record.repo, repo: record.repo, kind: .installed, url: plan.repo.htmlURL))
                    }
                    model.save(); installed += 1
                } catch { status = error.localizedDescription; break }
            }
            await model.refresh(); status += "\n已安装 \(installed) 项。"; busy = false
        }
    }
}
