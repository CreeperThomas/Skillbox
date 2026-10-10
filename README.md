# Skillbox

原生 macOS Skills 管理器，用于浏览、分类、按来源整理、启用/禁用、搜索和安装 Agent Skills。

## 当前能力

- 扫描 `~/.agents/skills` 与 `~/.agents/skills-disabled`
- 解析 `SKILL.md` 的名称、用途、标签、作者、版本和许可
- 自动分为 Research、Science、ML、Data、Dev、Design、Agents、Infra、Documents 等类别
- 根据元数据和内容指纹推断来源组，并支持来源组批量开关
- 启用/禁用通过移动目录实现，符合 DSH 对 `~/.agents/skills` 的扫描方式
- GitHub 仓库扫描、SKILL.md 候选选择、提交 SHA 固定、临时目录校验后安装
- skills.sh 与 GitHub 搜索
- Ollama 和 OpenAI-compatible AI 推荐
- Keychain 保存 API key 与 GitHub token
- 本地 catalog 保存分类修正、来源修正、安装记录和 AI 摘要缓存
- 中文用途说明：一句话用途、适用任务、必要条件；列表、中文搜索、详情和 AI 推荐共用
- 根据本地 SKILL.md 生成结构化说明，核对原文依据；原文变更会标记旧说明
- 批量生成支持15项抽样或全量、暂停、逐项保存和失败重试；继续生成会跳过已完成项
- 人工编辑的说明不会被自动生成覆盖；保留英文 skill 名与原始内容

中文说明按需生成，不内置对全部技能的翻译。Ollama 使用本机模型；OpenAI-compatible 模式会发送技能说明到配置的服务并产生 API 费用。原文引用核对可发现伪造依据，不能代替对语义准确性的人工复核。当前仅使用本地 SKILL.md，不自动抓取 GitHub 补充文档，也不自动生成新安装项目。

## 构建

需要 macOS 26 和 Command Line Tools。无需 Xcode。

```bash
make test
make app
open build/Skillbox.app
```

SwiftPM 在 DeepSeek Harness 沙箱里需要 `--disable-sandbox`；Makefile 已处理。构建缓存保存在项目的 `.build` 中。

## 安装

```bash
make app
cp -R build/Skillbox.app /Applications/
```

应用使用 ad-hoc 签名，仅供本机使用。首次使用时，在设置中填写 Ollama 模型或 OpenAI-compatible 服务配置；API key 保存到 macOS Keychain，不写入 catalog.json。

## 安全边界

下载功能只保存技能文件，不执行仓库中的脚本。安装过程拒绝绝对路径、路径穿越和符号链接，下载体积及文件数量有限制，并在写入启用目录前完成 `SKILL.md` 校验。来源推断是启发式结果，界面中的推断来源不等同于经过远端仓库验证的来源；Skillbox 安装的项目会记录准确的仓库和 commit。
