# Four-Dimension Evaluation Framework — Plan

**Date:** 2026-04-27  
**Status:** Planning → Implementation

Beyond raw accuracy, BioMate evaluations must measure four orthogonal quality dimensions for every benchmark. This document defines each dimension, the measurement methodology, the implementation plan, and how results feed into the comparison matrix.

---

## The Four Dimensions

### 1. Performance (existing)
Standard accuracy score per task. Already fully implemented in `ResultsStore` and all adapters. Reported as mean score ± std per benchmark/subtask.

### 2. Average Time Cost
**Definition:** Wall-clock latency from request submission to final response, per task. Reported as mean ± std and p95.  
**Why it matters:** Directly determines user-perceived responsiveness and batch throughput. A system that scores 95% but takes 10 min/task is unusable interactively.  
**Current state:** `latency_sec` tracked per row in ResultsStore. Only mean is reported today.  
**Gap:** No std/p95 reporting; no comparison across benchmarks or models in a unified table.

### 3. Stability (Multi-Run Consistency)
**Definition:** Given the same task input, how consistently does the model produce the same answer across N independent runs? Measured as:
- **Consistency rate:** % of tasks where all N runs agree (same score bucket: correct/incorrect)
- **Score variance:** std of score across N runs per task, averaged over tasks
- **Cohen's κ (kappa):** inter-run agreement beyond chance, for binary tasks

**Why it matters:** An LLM that scores 70% but with high variance might score 50% or 85% on any given day — unreliable for production or scientific reporting.  
**Subset:** 20% of each benchmark's tasks (stratified by subtask type), run N=3 times each.  
**Current state:** Consistency benchmark exists (`evaluation/datasets/consistency_benchmark/`) but is not per-benchmark.  
**Gap:** No systematic multi-run testing across BiomniEval1, LABBench, BixBench, SGI-Bench.

### 4. Hallucination Rate in Important Steps
**Definition:** Percentage of responses where the model makes a verifiably false, fabricated, or unsupported factual claim at a designated "important step."  
**Important steps (by task type):**

| Task type | Important step | Hallucination definition |
|-----------|---------------|-------------------------|
| Workflow routing | Workflow selection | Model asserts a workflow name/ID that doesn't exist in DB |
| Parameter extraction | Parameter value assignment | Model asserts a file path, param value, or unit not present in user input |
| BiomniEval1 gwas_causal | Gene identification | Model names a gene with false rationale (e.g., cites a false GWAS study) |
| BiomniEval1 rare_disease | Disease + OMIM ID | Model fabricates an OMIM ID that doesn't exist |
| BiomniEval1 patient_gene | ENSG ID | Model outputs an ENSG ID with wrong format or non-existent ID |
| LABBench CloningScenarios | MCQ rationale | Model selects an answer and gives a rationale that contradicts established biology |
| SGI-Bench | Scientific claim | Model cites a paper/finding not supported by literature in context |
| Results/findings | Report generation | Model asserts quantitative results not present in workflow output |

**Measurement method:** LLM-as-judge (Claude Haiku, fast + cheap) classifies each response as:
- `grounded` — claim is supported by task context or verifiable knowledge
- `hallucinated` — claim is provably false or fabricated (wrong OMIM ID, non-existent gene function, invented citation)
- `unverifiable` — claim cannot be assessed without external lookup; excluded from rate

**Hallucination rate = hallucinated / (grounded + hallucinated)**  
(unverifiable responses are excluded from denominator)

**Current state:** Not implemented.

### 5. Financial Cost (existing, extending)
**Definition:** API token cost (financial) + amortized hardware cost per task.  
**Current state:** `cost_usd` tracked per row; `cost_summary()` in ResultsStore.  
**Gap:** No ±std; no per-step cost breakdown; not yet in unified comparison table across all benchmarks.

---

## Implementation Plan

### Phase 1: Infrastructure (core files) — implement now

#### File 1: `evaluation/core/hallucination_detector.py`
LLM-as-judge component using Claude Haiku.

```
HallucinationDetector
  .classify(response, task_context, step_type) 
      → HallucinationResult(label, confidence, explanation, tokens_used)
  
  .batch_classify(responses, contexts, step_type)
      → List[HallucinationResult]

Step types: "gene_identification", "disease_identification", "ensg_lookup",
            "mcq_rationale", "workflow_selection", "parameter_extraction",
            "scientific_claim", "findings_report"

Each step type has a tailored judge prompt:
- Structured JSON output: {"label": "grounded|hallucinated|unverifiable", "reason": "...", "confidence": 0.0-1.0}
- Verifiable checks where possible (ENSG format regex, OMIM ID range check)
- Fallback to semantic judge for rationale/claim types
```

#### File 2: `evaluation/core/stability_runner.py`
Multi-run wrapper for any benchmark adapter.

```
StabilityRunner
  .run(adapter, tasks, n_repeats=3, sample_fraction=0.2)
      → StabilityReport(
          consistency_rate,    # % tasks where all N runs agree
          mean_score_variance, # avg std of score across runs per task
          kappa,               # Cohen's κ inter-run agreement
          per_task_results,    # {task_id: [score_run1, score_run2, score_run3]}
          total_cost_usd,
          total_latency_sec,
        )
```

#### File 3: Update `evaluation/core/results_store.py`
Add two new columns to `results` table:
- `hallucination_label TEXT` — grounded/hallucinated/unverifiable/null
- `repeat_id INTEGER` — 0 for original run; 1,2,... for stability repeats

#### File 4: `evaluation/runners/run_stability.py`
CLI runner: sample 20% of any benchmark, run N times, store results with `repeat_id`, report StabilityReport.

```bash
python runners/run_stability.py --benchmark biomni_eval1 --n-repeats 3 --sample 0.2
python runners/run_stability.py --benchmark labbench --n-repeats 3 --sample 0.2
```

#### File 5: `evaluation/runners/run_hallucination_audit.py`
CLI runner: loads stored `agent_response` from existing result DBs, runs hallucination judge on each, writes `hallucination_label` back to DB.

```bash
python runners/run_hallucination_audit.py --db results/biomni_eval1_v20/eval_results.db
python runners/run_hallucination_audit.py --db results/labbench_v22/eval_results.db --all
```

#### File 6: `evaluation/scripts/generate_eval_report.py`
Reads any result DB, computes all 4 dimensions, outputs unified report:

```
Dimension       | Value          | Comparison
----------------|----------------|-----------------------------------
Performance     | 64.6% ± 8.2%   | BiomniEval1 paper: GPT-4o ~65%
Time/task       | 39.5s ± 12.1s  | Not reported in literature
Stability       | 91.3% consist. | TruthfulQA GPT-4: 89% (Kuhn 2023)
Hallucination   | 8.4% rate      | Med-HALT GPT-4: 23% (Pal 2023)
Financial cost  | $0.00194/task  | SciAgentBench GPT-4o: $0.011/task
```

---

## Sampling Strategy for Stability & Hallucination Audits

| Benchmark | Full N | Stability subset (20%) | Repeats | Total calls | Est. cost |
|-----------|--------|----------------------|---------|-------------|-----------|
| BiomniEval1 | 223 | 45 tasks | 3× | 135 | ~$0.26 |
| LABBench CS | 33 | 7 tasks | 3× | 21 | ~$0.03 |
| BixBench | 30 | 6 tasks | 3× | 18 | ~$0.01 |
| SGI-Bench | 367 | 74 tasks | 3× | 222 | ~$2.34 |
| Routing | 120 | 24 tasks | 3× | 72 | ~$0.26 |

Hallucination audit runs once per stored response (no extra LLM calls for correct MCQ answers — only check wrong answers and non-MCQ tasks):

| Benchmark | Responses to judge | Est. calls | Est. cost (Haiku) |
|-----------|--------------------|------------|-------------------|
| BiomniEval1 | 223 | 223 | ~$0.02 |
| LABBench CS | 33 | 33 | ~$0.003 |
| SGI-Bench | 367 | 367 | ~$0.04 |
| Routing | 120 | 120 | ~$0.01 |

---

## Hallucination Judge Prompt Design

**For gene identification tasks (gwas_causal, rare_disease):**
```
You are a biology fact-checker. Given a question and a model response, determine 
if the response contains hallucinated claims.

Question: {question}
Model response: {response}
Expected answer type: {gene symbol / disease name + OMIM ID}

Check for:
1. Does the model name a gene/disease that is biologically plausible for this question?
2. If an OMIM ID is given, does it match the stated disease name (OMIM IDs are 6-digit numbers)?
3. Does the rationale cite mechanisms consistent with known biology, or does it contain invented pathways/studies?

Respond with JSON only:
{"label": "grounded|hallucinated|unverifiable", "reason": "<one sentence>", "confidence": 0.0-1.0}
```

**For MCQ rationale tasks (CloningScenarios, ProtocolQA):**
```
You are a molecular biology expert. A model answered a multiple-choice biology question.
Evaluate if the model's rationale contains hallucinated claims.

Question: {question}
Model answer: {response}
Correct answer: {ground_truth}

A hallucination is a claim in the rationale that is demonstrably false (wrong enzyme function,
wrong reaction product, wrong biological process). Selecting the wrong answer is NOT 
automatically a hallucination — the model may have misunderstood the question but used 
valid biology. Only flag claims that contradict established molecular biology.

Respond with JSON: {"label": "grounded|hallucinated|unverifiable", "reason": "...", "confidence": 0.0-1.0}
```

---

## Published Baselines (from literature survey, 2026-04-27)

### Hallucination Rate Baselines

| Paper | arXiv | Metric | Model | Rate | Domain |
|-------|-------|--------|-------|------|--------|
| TruthfulQA (Lin 2022) | 2109.07958 | % truthful responses | GPT-3 175B | 58% truthful (= 42% hallucinated) | General, adversarial 817-question |
| HaluEval (Ji 2023) | 2305.11747 | % hallucinated | ChatGPT | **19.5%** | QA/dialogue/summarization |
| FActScore (Min 2023) | 2305.14251 | % atomic facts supported | ChatGPT | 58% supported (= 42% unsupported) | Biography, Wikipedia-grounded |
| SAFE (Wei 2024) | 2403.18802 | Atomic fact precision | GPT-4 | ~76% | Long-form generation |
| Med-HALT (Pal 2023) | 2307.15343 | % hallucinated (medical) | GPT-3.5 | Notable; exact % in paper | Medical QA/recall |
| MedHallu (Yao 2025) | 2502.14302 | Hallucination detection F1 | GPT-4o | F1=0.625 (hard tier only) | Biomedical PubMedQA |
| **HealthBench (OpenAI 2025)** | — | % hallucinated (physicians) | GPT-4o | **15.8%** | Clinical conversations |
| **HealthBench** | — | % hallucinated | GPT-5 (thinking) | **1.6%** | Clinical conversations |
| HalluLens (Bang 2025) | 2504.17550 | Extrinsic hallucination | Frontier models | Substantial across all tasks | General; LongWiki, PreciseQA |
| AgentHallu (Liu 2026) | 2601.06818 | Step localization accuracy | Best model | **41.1%** overall; **11.6%** tool-use | Multi-step agents, 7 frameworks |
| AgentProp-Bench (2026) | 2604.16706 | Propagation probability | GPT-4o | **62%** bad→wrong | Tool-calling pipelines |
| BioKGBench (Yu 2024) | 2407.00466 | KG-verified hallucination | 13 LLMs | 90+ errors in benchmark ground truth | Biomedical KG |

**Key gap:** No biology-specific benchmark reports hallucination rate as a primary labeled metric.
BioMate would be among the first to report measured hallucination rates for biology AI agents.

### Stability / Consistency Baselines

| Paper | arXiv | Metric | Finding |
|-------|-------|--------|---------|
| SelfCheckGPT (Manakul 2023) | 2303.08896 | N-sample paraphrase agreement | AUC-PR outperforms grey-box; N=3–10 samples per question |
| "Hallucinations in Variance" (2026) | 2601.07058 | Semantic Stability = mean paraphrase-consistency | Formal definition: accuracy and stability must be reported together |
| ReliabilityBench (2026) | 2601.06112 | pass^k, robustness at ε, fault tolerance at λ | Success drops from 96.9% (ε=0) to 88.1% (ε=0.2) on agent tasks |
| BixBench (2025) | 2503.00096 | 5 replicas per config | Variance implicit but not reported as metric |

**Standard metrics to adopt:**
- **Consistency rate** = % tasks where all N runs agree (our primary metric)
- **Semantic Stability** = mean paraphrase-consistency (cite arXiv 2601.07058)
- **pass^k** = % of tasks solved on all k independent attempts (cite arXiv 2601.06112)
- **Cohen's κ** = inter-run agreement beyond chance

**Key gap:** No biology benchmark formally reports run-to-run consistency. BioMate would be first.

### Financial Cost Baselines

| Paper | arXiv | Benchmark | Explicit $/task |
|-------|-------|-----------|----------------|
| ScienceAgentBench (Chen 2025) | 2410.05080 | 102 science tasks | GPT-4o: $0.011 · Claude-3.5-S: $0.017 · o1-preview: $0.221 · OpenHands: $0.958 |
| All other bio benchmarks | — | — | **Not reported** (BixBench notes "significant costs"; Biomni ran 12.5% subset due to budget) |

### Time Per Task Baselines

| Paper | Time/task | Notes |
|-------|-----------|-------|
| ScienceAgentBench | ~10 min (agent) | Human: 2.5–3 h |
| LABBench CloningScenarios | 10–60 min (human) | Model time not reported |
| BixBench | 24–48 h total / ~N tasks | Mean per-task not reported |
| All others | Not reported | — |

**Key gap:** No biology benchmark reports mean ± std time per task. BioMate is first.

---

## Timeline

- **Phase 1** (today): Implement files 1–6 above
- **Phase 2** (after gemma4 finishes): Run hallucination audit on all existing result DBs
- **Phase 3**: Run stability tests on BiomniEval1 + LABBench (highest priority)
- **Phase 4**: Update comparison matrix with all 4 dimensions

---

*Related docs:*
- `docs/20260427_PUBLISHED_BENCHMARK_COST_SURVEY.md`
- `docs/20260427_BIOMATE_VS_PUBLISHED_COMPARISON.md`
