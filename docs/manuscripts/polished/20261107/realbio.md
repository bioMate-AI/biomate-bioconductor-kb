# RealBio benchmarks catalog-assisted bioinformatics workflow selection and parameter extraction

**Authors:** [To be completed]

**Affiliations:** [To be completed]

**Correspondence:** [Name and email to be completed]

*Preprint · author-review revision · 7 November 2026*

## Abstract

Reliable bioinformatics assistance requires selecting suitable workflows, specifying their parameters and recognizing failures. These capabilities are difficult to compare when task definitions and scoring procedures differ across systems. Here we present RealBio, a benchmark of five workflow-related tasks evaluated with deterministic scoring. The suite comprises 200 routing requests, 170 parameter-extraction items, 100 failure-category items, 40 workflow-generation items and 100 quality-control decisions. Its principal comparison evaluates language models with and without a workflow catalog. In the reported results, a locally served nine-billion-parameter model improves from 0.180 to 0.905 routing accuracy, while Claude Opus 5 improves from 0.615 to 0.990. The catalog condition provides candidate labels and, where available, descriptions; it measures selection with answer-space coverage rather than retrieval from an unrestricted collection. Raw parameter-extraction F1 ranges from 0.499 to 0.805 among the reported language models. These results identify candidate information as a substantial contributor to workflow selection on this task set. They establish a reproducible basis for studying individual workflow decisions, while leaving successful execution and generalization to independently curated tasks to be evaluated separately.

## Introduction

A bioinformatics assistant must translate an analytical request into a workflow, select valid parameters and respond appropriately when an analysis fails. Correct decisions at these stages are necessary for useful automation, although they do not by themselves demonstrate a scientifically valid analysis. Evaluation should therefore distinguish selecting an operation from executing it successfully.

Existing benchmarks address complementary parts of this problem. SWE-bench evaluates code changes against tests [1], MLE-bench evaluates machine-learning engineering on competition tasks [2], and ScienceAgentBench evaluates programs, execution results and costs for scientific tasks [3]. CORE-Bench studies computational reproducibility [4], PaperBench assesses research replication using structured rubrics and a model-based judge [5], and BixBench evaluates biological data analysis [6]. RealBio focuses on workflow-level decisions with explicit reference answers and deterministic scoring. It does not claim to replace these execution-oriented evaluations or to introduce the first knowledge-assisted benchmark.

The principal experimental question is how providing a workflow catalog changes selection accuracy for the same model. We distinguish this catalog-assisted condition from unrestricted retrieval, from rule-assisted parameter extraction and from complete agent execution. This separation determines what the observed gains can support.

## Results

### Catalog information improves routing accuracy

The reported routing results improve for every language model with paired entries (Table 1; Fig. 1). BioMate 9B base improves from 0.180 to 0.905, and Claude Opus 5 improves from 0.615 to 0.990. Catalog-assisted accuracy spans 0.735–0.990 across the reported language models, rather than converging to a uniformly high level. These are descriptive comparisons on 200 requests; they do not establish equivalence between model families.

**Table 1. Reported RealBio results.** Routing uses 200 items, parameter extraction 170, failure-category classification 100 and quality-control (QC) decisions 100. Values reproduce the source manuscript and stored leaderboard. Parameter F1 is the benchmark-defined aggregate key–value score. An em dash indicates an unavailable result or an inapplicable condition. Catalog provenance varies across rows, as described in Methods. The Biomni scaffold receives a catalog in both columns, so its entries are not a direct-versus-catalog experiment. The retrieval-system row is a separate system result.

| Model (version) | Routing, direct | Routing, catalog | Parameter F1 | Failure category | QC action |
|---|---|---|---|---|---|
| Claude Opus 5 | 0.615 | 0.990 | 0.805 | 0.870 | 0.330 |
| GPT-6.1-sol-pro | 0.590 | 0.985 | 0.718 | 0.870 | 0.450 |
| Gemini 3.1 Pro | 0.580 | 0.975 | 0.757 | 0.880 | 0.630 |
| Kimi K3 | 0.495 | 0.970 | 0.672 | 0.770 | 0.360 |
| GLM-5.3-prime | 0.375 | 0.955 | 0.682 | 0.820 | 0.550 |
| GLM-5.2 | 0.400 | 0.950 | 0.691 | 0.830 | 0.440 |
| GPT-5.6-luna | 0.355 | 0.950 | 0.667 | 0.830 | 0.340 |
| DeepSeek V4-pro | 0.415 | 0.850 | 0.691 | 0.800 | 0.420 |
| Qwen3.5-27B | 0.240 | 0.935 | 0.719 | — | — |
| BioMate 9B (on-prem, base) | 0.180 | 0.905 | 0.703 | 0.870 | 0.430 |
| Qwen3.5-9B | 0.120 | 0.830 | 0.600 | — | — |
| Qwen2.5-7B | 0.140 | 0.735 | 0.499 | — | — |
| BioMate 9B (on-prem, fine-tuned) | 0.285 | 0.810 | 0.716 | 0.850 | 0.430 |
| Biomni (A1 scaffold) | 0.950 | 0.950 | 0.746 | 0.950 | 0.500 |
| BioMate retrieval system (no model) | 0.965 | — | — | — | — |

![Routing accuracy under direct and catalog-assisted conditions.](figures/realbio_routing.png)

**Figure 1. Routing accuracy with and without candidate context.** The retained source figure shows a subset of the models in Table 1; the fine-tuned BioMate model is tabulated only. Grey points denote direct responses and blue points denote responses with candidate context. Connecting lines pair results for a model, and annotations show rounded absolute differences. These are catalog-selection results, not estimates of deployed retrieval recall or workflow execution success.

Models with lower direct scores often show larger absolute improvements. Because accuracy is bounded above by one, this association can arise from available headroom; it does not demonstrate an inverse relationship between model capability and the value of context. Serving differences and incomplete run metadata also limit causal interpretation of the paired contrasts.

### Parameter extraction and rule-assisted processing measure different configurations

Raw-model parameter F1 ranges from 0.499 to 0.805 in Table 1. A separate offline rule-layer experiment reports F1 of 0.703 for BioMate 9B base, 0.470 for rules alone and 0.843 for their combination. These values can be reproduced, but the experiment constructs its allowable parameter schema from expected and forbidden answer keys and uses a separate value-equivalence implementation. Consequently, the combined score is an exploratory result under answer-informed schema constraints, not a validated estimate of production performance. The combined configuration also produces 27 forbidden-field violations, compared with 53 for the raw model; improved aggregate F1 does not imply error-free parameter handling.

### Workflow generation and failure classification have distinct endpoints

Workflow generation contains two 20-item subsets: analysis-category selection and tool enumeration. For tool enumeration, the stored subset summary reports success when at least half of the reference tools are recovered. This thresholded success rate is 0.95 for Claude Opus 5 and 0.35 for Qwen2.5-7B; their mean tool recalls are approximately 0.817 and 0.366, respectively. These metrics should not be interchanged. The separate subset evaluation is not merged with the legacy aggregate workflow-generation leaderboard, whose result files require reconciliation.

Failure-category accuracy ranges from 0.770 to 0.950 across reported systems, whereas QC-action accuracy ranges from 0.330 to 0.630 (Table 1). Failure-category recognition does not establish that a proposed repair executes successfully. Similarly, agreement with an author-defined QC action does not establish that the underlying threshold is appropriate for every assay or biological context.

### A small additional audit probes rule coverage

A deterministic audit correctly fills 15 of 17 expected parameter values in covered probe classes and records no forbidden-field violations. The denominator counts expected values, not independently sampled biological analyses. Two additional out-of-coverage organism values are left unfilled. This behaviour avoids unsupported filling but still represents missing expected answers. The audit is small and author-created; it cannot exclude benchmark-specific tuning or establish independent generalization. Earlier held-out routing gains are not used as confirmatory evidence here because the manuscript lacks a complete matched run specification and denominator for those comparisons.

## Discussion

RealBio provides a concrete setting for separating workflow selection from other components of bioinformatics assistance. The most strongly supported observation is that supplying the answer space and candidate context substantially improves routing accuracy on the evaluated requests. This observation motivates careful catalog design and transparent reporting of the information supplied to a model.

The experiment does not isolate the effect of descriptions from that of exposing candidate labels. A names-only control with the same catalog and serving configuration would be needed for that attribution. An operational retrieval evaluation would additionally require a frozen catalog independent of test labels, per-query retrieval, recall measurements and scoring of every request, including retrieval misses. The previously cited approximate end-to-end value of 0.80 is not treated as an estimate for the 200-item routing experiment because its correspondence to this dataset has not been established.

The benchmark currently emphasizes recognition and structured selection. Future execution-grounded evaluation should test generated configurations and repairs in held-out workspaces, with biological and computational output checks. Independent annotation, ambiguity adjudication, prospective task collection and paired uncertainty estimates would strengthen claims beyond the present author-curated sample. Publicly inspectable scoring improves auditability but does not establish freedom from author bias or contamination.

## Methods

### Task composition and reference answers

The five tasks contain 610 items in total. Routing references specify an expected workflow and optional acceptable alternatives. Parameter references specify expected key–value pairs and fields that must remain unfilled. Failure items use fixed repair categories, workflow generation uses category labels or reference tool sets, and QC items specify an expected action. The items are described in the source manuscript as synthetic analysis requests. Complete item-level source attribution, annotation roles and independent adjudication remain to be documented.

### Input conditions and catalog construction

The direct condition supplies the request without a candidate menu. The documented described-catalog runner builds a sorted set of workflow names from the benchmark's correct labels and appends available workflow descriptions, truncated to 120 characters. This is a fixed, benchmark-derived catalog; it is not a query-specific retrieval test. Correct-label coverage is therefore supplied by construction in this runner. Other stored results include earlier catalog variants, and a full run manifest is required before claiming uniform conditions across all paired rows.

The leaderboard prefers described-catalog predictions and falls back to names-only catalog predictions when necessary. The separate GPT-5.6 row with a names-only condition and Qwen3.8-Max row with problematic direct responses are omitted from the manuscript comparison, as in the source draft. GPT-5.6-luna is a distinct retained row. The Biomni scaffold and retrieval-only system are reported as contextual system results, not matched language-model ablations.

### Deterministic scoring and missing responses

Routing accepts normalized workflow names and specified alternatives. The parameter score counts correct key–value matches as true positives, missing or incorrect expected values as false negatives, and unexpected keys as false positives. An incorrect value on an expected key is not additionally counted as a false positive; this is a benchmark-specific F1 convention. Forbidden-field violations are recorded separately. Value matching includes defined aliases and selected numeric-range rules rather than unrestricted semantic equivalence.

The routing scorer skips absent prediction identifiers, whereas an empty prediction attached to an identifier is scored as incorrect. The described-catalog runner retries empty or failed calls and writes a prediction for each requested item. Coverage, retry counts, failures and effective denominators must therefore accompany the finalized release; the scorer alone does not enforce complete coverage. Deterministic scoring removes a model judge but does not eliminate implementation or reference-label errors.

### Statistical interpretation and model provenance

Results are descriptive point estimates. The benchmark does not provide a basis for inferring population-level equivalence from small score differences. A final statistical analysis should resample paired requests and report task-specific uncertainty, with run variability analysed separately. Model names are retained as recorded in the result artifacts; exact provider identifiers, evaluation dates, revisions, prompts and inference budgets require a frozen run manifest. Locally served results do not include complete per-call token accounting.

## Data and code availability

The benchmark materials and evaluation code have been assembled for release. The source draft specifies CC-BY-4.0 for benchmark materials; the final code license, public repository and archival identifier require author confirmation. Public availability is not asserted until those identifiers are supplied. The release should include versioned items, scorer implementations, prompts, catalog snapshots, per-item predictions and coverage metadata.

## Ethics and competing interests

The source manuscript describes synthetic requests without human-subjects data or personally identifiable information. RealBio is intended for evaluating workflow decisions and is not a clinical decision tool. The authors developed the benchmark, its scorer and one evaluated system. Author contributions, funding and the formal competing-interest declaration remain to be completed.

## References

1. Jimenez, C. E. et al. SWE-bench: Can Language Models Resolve Real-World GitHub Issues? *ICLR* (2024). https://arxiv.org/abs/2310.06770
2. Chan, J. S. et al. MLE-bench: Evaluating Machine Learning Agents on Machine Learning Engineering. Preprint (2024). https://arxiv.org/abs/2410.07095
3. Chen, Z. et al. ScienceAgentBench: Toward Rigorous Assessment of Language Agents for Data-Driven Scientific Discovery. *ICLR* (2025). https://arxiv.org/abs/2410.05080
4. Siegel, Z. S. et al. CORE-Bench: Fostering the Credibility of Published Research Through a Computational Reproducibility Agent Benchmark. Preprint (2024). https://arxiv.org/abs/2409.11363
5. Starace, G. et al. PaperBench: Evaluating AI's Ability to Replicate AI Research. Preprint (2025). https://arxiv.org/abs/2504.01848
6. Mitchener, L. et al. BixBench: a Comprehensive Benchmark for LLM-based Agents in Computational Biology. Preprint (2025). https://arxiv.org/abs/2503.00096
