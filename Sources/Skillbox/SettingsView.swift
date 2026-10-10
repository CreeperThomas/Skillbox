import SwiftUI
import SkillboxCore

struct SettingsView: View {
    @Bindable var model: AppModel
    @State private var aiKey = ""
    @State private var githubKey = ""
    @State private var connection = ""
    var body: some View {
        Form {
            Section("AI 设置") {
                Picker("后端", selection: $model.catalog.aiSettings.backend) {
                    ForEach(AIBackend.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                TextField("服务地址", text: $model.catalog.aiSettings.baseURL)
                TextField("模型", text: $model.catalog.aiSettings.model, prompt: Text("dolphin-llama3:8b"))
                Text("Ollama 默认使用 http://localhost:11434。云端服务请填写 OpenAI 兼容接口地址。").font(.caption).foregroundStyle(.secondary)
            }
            Section("中文用途说明") {
                Text("可先生成15项或生成全部；逐项保存，可暂停。继续生成时会跳过有效说明和人工编辑项，失败项可重试。AI 说明需人工核对或确认；人工修正永不自动覆盖。").font(.caption).foregroundStyle(.secondary)
                if model.catalog.aiSettings.backend == .openAICompatible {
                    Text("点击生成即会向所选云端服务发送 skill 说明，并产生该服务的模型费用。建议先生成15项检查质量。").font(.caption).foregroundStyle(.secondary)
                } else { Text("当前使用本机 Ollama，skill 内容由本机模型处理。").font(.caption).foregroundStyle(.secondary) }
            }
            Section("技能目录") {
                LabeledContent("已启用", value: model.roots.enabled.path)
                LabeledContent("已禁用", value: model.roots.disabled.path)
            }
            Section("凭据 · 存储在 Keychain") {
                SecureField("AI API key（留空保留）", text: $aiKey)
                SecureField("GitHub token（可选）", text: $githubKey)
            }
            HStack {
                Button("保存设置") {
                    do {
                        if !aiKey.isEmpty { try CredentialStore.set(aiKey, account: "ai"); aiKey = ""; model.catalog.aiSettings.hasAPIKey = true }
                        if !githubKey.isEmpty { try CredentialStore.set(githubKey, account: "github"); githubKey = ""; model.catalog.hasGitHubToken = true }
                        model.save(); connection = "已保存"
                    } catch { connection = error.localizedDescription }
                }
                Button("检测 Ollama 模型") {
                    Task {
                        do {
                            let names = try await AIService(settings: model.catalog.aiSettings).models()
                            if model.catalog.aiSettings.model.isEmpty { model.catalog.aiSettings.model = names.first ?? "" }
                            connection = names.joined(separator: ", ")
                        } catch { connection = error.localizedDescription }
                    }
                }
            }
            Text(connection).font(.caption).textSelection(.enabled)
        }.formStyle(.grouped).padding().frame(width: 620, height: 600)
    }
}
