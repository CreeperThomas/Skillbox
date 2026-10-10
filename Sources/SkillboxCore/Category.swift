import Foundation

/// Coarse grouping shown in the sidebar. Ten buckets, inferred from
/// name + description + tags; the user can override any assignment.
public enum Category: String, CaseIterable, Codable, Sendable {
    case researchWriting = "research"
    case scienceBio = "science"
    case mlEngineering = "ml"
    case dataAnalysis = "data"
    case devWorkflow = "dev"
    case designVisuals = "design"
    case agentsLLMApps = "agents"
    case infraCompute = "infra"
    case documentsOffice = "documents"
    case other = "other"

    public var title: String {
        switch self {
        case .researchWriting: return "研究与写作"
        case .scienceBio: return "科学与生物"
        case .mlEngineering: return "机器学习工程"
        case .dataAnalysis: return "数据分析"
        case .devWorkflow: return "开发流程"
        case .designVisuals: return "设计与视觉"
        case .agentsLLMApps: return "智能体与大模型"
        case .infraCompute: return "基础设施与计算"
        case .documentsOffice: return "文档与办公"
        case .other: return "其他"
        }
    }

    /// SF Symbol name.
    public var symbol: String {
        switch self {
        case .researchWriting: return "doc.text"
        case .scienceBio: return "atom"
        case .mlEngineering: return "cpu"
        case .dataAnalysis: return "chart.bar"
        case .devWorkflow: return "hammer"
        case .designVisuals: return "paintbrush"
        case .agentsLLMApps: return "sparkles"
        case .infraCompute: return "cloud"
        case .documentsOffice: return "folder"
        case .other: return "square.grid.2x2"
        }
    }

    /// Sidebar display order.
    public static let displayOrder: [Category] = [
        .researchWriting, .scienceBio, .mlEngineering, .dataAnalysis,
        .devWorkflow, .designVisuals, .agentsLLMApps, .infraCompute,
        .documentsOffice, .other,
    ]
}

/// Keyword rules that map a skill onto a `Category`.
///
/// Rules are scored rather than first-match: the category with the most
/// keyword hits wins, which handles descriptions that mention two domains.
/// `priority` breaks ties in favour of the more specific bucket.
public enum Categorizer {
    struct Rule {
        let category: Category
        let keywords: [String]
        /// Weight applied per hit; higher wins ties.
        let weight: Double
    }

    static let rules: [Rule] = [
        Rule(category: .documentsOffice, keywords: [
            "docx", "pptx", "xlsx", "word document", "powerpoint", "excel", "spreadsheet",
            "office file", "pdf form", ".dotx", ".potx", "workbook",
        ], weight: 3.0),

        Rule(category: .scienceBio, keywords: [
            "rna-seq", "rnaseq", "single-cell", "single cell", "scanpy", "anndata", "scvi",
            "genomic", "genome", "gene expression", "protein", "proteom", "bioinformatic",
            "molecular dynamics", "docking", "cheminformat", "smiles", "rdkit", "crispr",
            "phylogen", "sequence alignment", "mass spectrom", "microscopy", "histolog",
            "cell type", "biolog", "clinical", "pharmacokinet", "neuroscience", "neuropixels",
            "flow cytometry", "metabolic", "glyco", "variant", "ontology term",
        ], weight: 2.5),

        Rule(category: .mlEngineering, keywords: [
            "fine-tun", "finetun", "quantiz", "pretrain", "pre-train", "distributed training",
            "lora", "qlora", "rlhf", "grpo", "dpo", "ppo", "checkpoint", "gpu memory",
            "throughput", "inference", "vllm", "tensorrt", "deepspeed", "fsdp", "megatron",
            "transformer", "diffusion model", "neural network", "torch", "pytorch",
            "training loop", "hyperparameter", "embedding model", "attention", "mixture of experts",
            "sparse autoencoder", "interpretability", "model merging", "pruning",
        ], weight: 2.5),

        Rule(category: .dataAnalysis, keywords: [
            "dataframe", "polars", "pandas", "statistical analysis", "statistics", "hypothesis test",
            "regression", "time series", "forecast", "visualization of data", "exploratory data",
            "csv", "parquet", "out-of-core", "distributed computing", "aggregation", "eda",
            "sample size", "power analysis", "survival analysis", "bayesian model",
        ], weight: 2.0),

        Rule(category: .agentsLLMApps, keywords: [
            "rag", "retrieval-augmented", "vector database", "embedding database", "langchain",
            "llamaindex", "dspy", "agent framework", "multi-agent", "crewai", "autogpt",
            "prompt engineering", "structured output", "guardrail", "observability for llm",
            "llm application", "chatbot", "tool calling", "mcp server", "semantic search",
            "context window", "hallucination", "jailbreak",
        ], weight: 2.0),

        Rule(category: .infraCompute, keywords: [
            "gpu cloud", "rent gpu", "vast.ai", "modal", "serverless", "kubernetes", "docker",
            "slurm", "hpc", "cluster", "ssh job", "cloud instance", "deploy", "serving",
            "lambda labs", "sky pilot", "skypilot", "orchestration", "job queue", "scheduler",
        ], weight: 2.0),

        Rule(category: .designVisuals, keywords: [
            "diagram", "figure", "poster", "slide", "deck", "presentation", "infographic",
            "ui design", "ux", "visual design", "color palette", "typography", "css",
            "wireframe", "mockup", "illustration", "image generation", "pixel art",
            "architecture diagram", "mermaid", "drawio", "chart type", "plot type",
            "schematic", "matplotlib", "seaborn", "plotly",
        ], weight: 2.0),

        Rule(category: .researchWriting, keywords: [
            "paper", "manuscript", "literature review", "citation", "bibliograph", "arxiv",
            "peer review", "rebuttal", "grant", "proposal", "patent", "thesis", "survey",
            "related work", "camera-ready", "submission", "conference", "journal",
            "research idea", "novelty", "abstract", "latex", "bibtex", "preprint",
        ], weight: 2.0),

        Rule(category: .devWorkflow, keywords: [
            "debug", "refactor", "unit test", "test-driven", "code review", "git", "worktree",
            "pull request", "commit", "brainstorm", "implementation plan", "spec",
            "subagent", "dispatching", "workflow for coding", "clean architecture",
            "verification", "linting", "migration", "codebase",
        ], weight: 2.0),
    ]

    /// Chooses the category with the highest weighted keyword score.
    /// Returns `.other` when nothing matches.
    public static func categorize(name: String, description: String, tags: [String] = []) -> Category {
        // Name and tags are stronger signals than a long description.
        let weighted = (name + " " + tags.joined(separator: " ")).lowercased()
        let body = description.lowercased()

        var best: (category: Category, score: Double) = (.other, 0)
        for rule in rules {
            var hits = 0.0
            for keyword in rule.keywords {
                if weighted.contains(keyword) { hits += 1.5 }
                else if body.contains(keyword) { hits += 1.0 }
            }
            guard hits > 0 else { continue }
            let score = hits * rule.weight
            if score > best.score {
                best = (rule.category, score)
            }
        }
        return best.category
    }
}
