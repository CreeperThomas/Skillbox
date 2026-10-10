# Skillbox — Design Spec

Date: 2026-10-08
Status: approved by user (chat), pending written review

## 1. Purpose

A native macOS app that manages the agent skills under `~/.agents/skills`
(currently 376 folders, each containing a `SKILL.md`). The user's problem:
"there are too many skills". Skillbox lets them browse, understand, group,
enable/disable, discover and install skills, and ask an AI which skill fits a
task.

## 2. Constraints

- Native SwiftUI app. Built with the Command Line Tools toolchain only
  (Swift 6.3.3, macOS 26 SDK) — **no Xcode**. SwiftPM executable target +
  a script that assembles `Skillbox.app`.
- Zero third-party Swift packages. Markdown preview is rendered in a
  `WKWebView` with a small in-app Markdown → HTML converter and Apple-style
  CSS.
- Deployment target macOS 26 (the user's machine). Liquid Glass APIs may be
  used but nothing may depend on Xcode asset catalogs.
- Skills directory truth: the DSH runtime scans `~/.agents/skills` (and
  `~/.dsh/skills`, project-level dirs) with live file watching. Moving a
  folder out of `~/.agents/skills` removes it from the agent immediately.
- AI: Ollama first (auto-detect at `http://localhost:11434`), optional
  OpenAI-compatible endpoint + key stored in Keychain.

## 3. Domain model

```
Skill
  id: String              // folder name
  name, description       // from SKILL.md frontmatter (fallback: folder name / first paragraph)
  version, author, license, tags: [String]   // optional frontmatter
  folderURL: URL
  enabled: Bool           // true if under skills/, false if under skills-disabled/
  fileCount: Int, sizeBytes: Int64
  category: Category      // inferred (see §5)
  sourceID: String?       // SourceGroup.id

SourceGroup
  id: String              // e.g. "github:obra/superpowers" or "inferred:k-dense"
  displayName: String
  repo: String?           // owner/repo when known
  kind: .installed | .inferred | .manual

CatalogState (persisted JSON, ~/Library/Application Support/Skillbox/catalog.json)
  sourceOverrides: [skillID: sourceID]      // user corrections
  installRecords: [skillID: InstallRecord]  // repo, path in repo, commit sha, installedAt
  summaries: [skillID: AISummary]           // text, model, contentHash
  aiSettings: AISettings (endpoint kind, base URL, model; key lives in Keychain)
```

SKILL.md is always the source of truth for name/description; the catalog
only stores what cannot be derived.

## 4. Architecture (modules inside one SwiftPM package)

```
Skillbox/
  Package.swift
  Sources/SkillboxCore/       # pure logic, no UI, fully unit-tested
    Frontmatter.swift         # YAML-ish frontmatter parser (name/description/tags/metadata)
    SkillScanner.swift        # scan skills/ + skills-disabled/ → [Skill]
    Categorizer.swift         # keyword rules → Category
    SourceInferrer.swift      # content fingerprints → SourceGroup
    Catalog.swift             # load/save catalog.json, merge overrides
    SkillToggler.swift        # move folders between skills/ and skills-disabled/, rollback on failure
    Markdown.swift            # Markdown → HTML (headings, lists, code, tables, links, emphasis)
    GitHubClient.swift        # tree listing, raw file download, repo search
    SkillsShClient.swift      # skills.sh search API
    Installer.swift           # InstallPlan (which files) → download → write → record
    AIClient.swift            # Ollama + OpenAI-compatible chat (streaming)
    Recommender.swift         # local prefilter (keyword scoring) + prompt building
  Sources/Skillbox/           # SwiftUI app
    SkillboxApp.swift
    AppModel.swift            # @Observable, owns catalog + scanner + actions
    Sidebar/, SkillList/, Detail/, Discover/, Ask/, Settings/
    Resources/preview.css
  Tests/SkillboxCoreTests/
  scripts/make-app.sh         # swift build -c release → Skillbox.app (Info.plist, icon, codesign -s -)
  Makefile                    # make app / make install / make test
```

Dependency direction: `Skillbox` (UI) → `SkillboxCore`. Core has no AppKit
dependency except Foundation.

## 5. Classification

### Categories (fixed list, inferred by keyword rules over name+description+tags)

| Category | Symbol | Example keywords |
|---|---|---|
| Research & Writing | doc.text | paper, review, citation, arxiv, rebuttal, grant, patent |
| Science & Bio | atom | rnaseq, protein, genomic, scanpy, molecular, cell, clinical |
| ML Engineering | cpu | training, fine-tun, quantiz, inference, llm, rl, distributed |
| Data & Analysis | chart.bar | dataframe, statistic, polars, pandas, plot, time series |
| Dev Workflow | hammer | debugging, plan, review, git, test, brainstorm, subagent |
| Design & Visuals | paintbrush | design, figure, diagram, poster, slides, image, ui |
| Agents & LLM Apps | sparkles | agent, rag, langchain, embedding, vector, prompt |
| Infra & Compute | cloud | gpu, modal, vast, cloud, cluster, serve, deploy |
| Documents & Office | folder | docx, pptx, xlsx, pdf, markdown |
| Other | square.grid.2x2 | fallback |

Rules are a first-match ordered list; ties go to the category with the most
keyword hits. User can override per skill (stored in catalog).

### Source groups

Inference order for existing skills (first match wins):

1. Install record exists → exact repo.
2. `metadata.source` URL in frontmatter → repo from URL.
3. Content fingerprints:
   - `skill-author: K-Dense` → K-Dense Scientific Skills
   - `author: Orchestra Research` → Orchestra AI-Research-SKILLs
   - `Anthropic, PBC` / `github.com/anthropics/skills` → Anthropic Skills
   - `human partner` / `superpowers` → Superpowers (obra)
   - `ARIS` / `mcp__codex` / Chinese trigger phrases → ARIS Research Pipeline
   - `A-EVO Lab` / `ARA Seal` → ARA
4. Otherwise → "Unsorted". User can drag/assign to a group; assignment is
   stored in `sourceOverrides`.

The initial inference run is shown to the user once as a review sheet.

## 6. UI

Three-column `NavigationSplitView`, follows macOS HIG (sidebar source list,
toolbar search, inspector-like detail). System fonts, system colors,
SF Symbols, standard list row heights. Liquid Glass only where the system
gives it for free (toolbar, sidebar).

### Sidebar
- **Library**: All (count), Enabled, Disabled, Recently Added.
- **Categories**: one row per category with count.
- **Sources**: `DisclosureGroup` per source group; header row shows name,
  count, and a `Toggle` that enables/disables the whole group (confirmation
  alert when disabling > 10). Expanded shows the skills in that group.
- **Discover**: Search, Ask AI.
- Settings via standard `⌘,` window.

### Skill list (middle column)
- Searchable (`.searchable`), filters by name/description/tags.
- Row: name (monospaced-ish headline), one-line description, category
  pill, dimmed + "Disabled" badge when disabled.
- Sort: name / recently added / source.
- Context menu: Enable/Disable, Reveal in Finder, Change category, Change
  source, Delete (confirm).

### Detail (right column)
- Header: name, source › category breadcrumb, Enable toggle.
- "What is this for?" card: 2–3 sentence Chinese plain-language summary
  generated by the configured AI model from SKILL.md, cached by content
  hash; "Regenerate" button; graceful placeholder if no AI backend.
- Metadata grid: version, author, license, files, size, path.
- SKILL.md rendered in `WKWebView` with `preview.css` (Apple documentation
  look: SF Pro, 15px body, 1.5 line-height, subtle code blocks, hairline
  tables). Supports light/dark via `prefers-color-scheme`.
- File tree of the skill folder (collapsed by default); clicking a file
  previews it as text/markdown.

### Discover › Search
- One search field. Queries skills.sh (`/api/search?q=`) and GitHub repo
  search (`search/repositories?q=<q>+SKILL.md`) concurrently.
- Results list: name, source repo, installs (skills.sh), stars (GitHub),
  "Install" button. Already-installed → "Installed" label.
- "Install from repo…" sheet: enter `owner/repo` (or URL); app lists all
  `SKILL.md` folders via Git Trees API, user checks which to install.
- Optional GitHub token in Settings raises rate limits and enables code
  search.

### Discover › Ask AI
- Chat panel. System prompt includes the top 30 locally pre-filtered skills
  (name + description) and instructs the model to recommend by id with a
  reason, and to emit `SEARCH: <query>` lines when local coverage is poor.
- Recommended skill ids are rendered as clickable chips → selects the skill
  in the list. `SEARCH:` lines trigger a Discover search whose top 5
  results are appended to the answer with Install buttons.
- Streaming responses.

### Settings
- AI: backend (Ollama / OpenAI-compatible), base URL, model picker
  (Ollama `/api/tags`), API key (Keychain), "Test connection".
- GitHub token (Keychain).
- Skills directory (default `~/.agents/skills`), disabled directory
  (default `~/.agents/skills-disabled`).

## 7. Key flows

**Enable/disable**: `SkillToggler.move(skill, enabled:)` → `FileManager.moveItem`
between the two roots. If the destination exists → error shown, no move.
Group toggle performs moves sequentially; on first failure, stops and
reports which succeeded. Scanner re-runs after any move.

**Install from repo**: parse input → `GitHubClient.tree(owner, repo, ref)`
→ filter paths ending `/SKILL.md` (depth ≤ 4, skipping `node_modules`,
`test*`) → `InstallPlan` with one entry per folder → user selects → for each
folder download every blob under that folder via raw.githubusercontent.com
→ write to a temp dir → validate SKILL.md frontmatter → move into
`~/.agents/skills/<name>` (conflict: ask Overwrite / Skip) → write
`InstallRecord` (repo, path, sha, date) → rescan.

**AI summary**: `contentHash = sha256(SKILL.md)`; if cached summary matches
hash, show it; else when the skill is selected, request in background with
a concurrency limit of 1, store result.

## 8. Error handling

- No Ollama / no key → AI areas show an inline "Set up AI in Settings"
  callout; nothing else breaks.
- Network errors in Discover → inline message with Retry.
- GitHub 403 rate limit → message suggests adding a token.
- Invalid SKILL.md (no frontmatter) → still listed, description derived
  from first paragraph, warning icon.
- Move failures → rollback any partial state, show alert.

## 9. Testing

Unit tests in `SkillboxCoreTests` (run with `swift test`):
- Frontmatter: quoted/unquoted description, multi-line, metadata nesting,
  tags arrays, missing fields.
- Categorizer: fixture of ~20 real skill descriptions → expected category.
- SourceInferrer: fixtures per fingerprint + "unsorted" fallback.
- Markdown: headings, fenced code, tables, nested lists, inline code, links.
- SkillToggler: temp dirs, move both directions, conflict error, rollback.
- Installer: plan building from a fake tree JSON; conflict handling with a
  fake downloader.
- Recommender prefilter: query "single cell" ranks scanpy/anndata top.

UI verified manually with screenshots of each column and state (empty,
disabled, no-AI, search results).

## 10. Build & distribution

- `make test` → `swift test`
- `make app` → `swift build -c release`, assemble `build/Skillbox.app`
  (Contents/MacOS/Skillbox, Info.plist with bundle id
  `com.thomas.skillbox`, LSMinimumSystemVersion 26.0, NSHighResolutionCapable,
  icon generated from an SF Symbol-based PNG set via `iconutil`),
  `codesign --force --deep -s -`.
- `make install` → copy to `/Applications/Skillbox.app`.

## 11. Out of scope (v1)

- Editing SKILL.md inside the app.
- Project-level `.agents/skills` directories.
- Syncing to other agents' skill directories (Claude, Cursor…).
- Update checking for installed skills (install records make this possible later).
