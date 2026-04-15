# Benchmark Implementation Guide — BioMate Evaluation Harness
**Date:** 2026-04-01  
**Purpose:** Step-by-step integration guide for each external benchmark into BioMate's existing test harness. Assumes familiarity with `backend/lib/galaxy/ai/test_harness/`.

---

## Harness Architecture Recap

BioMate's existing test harness at `backend/lib/galaxy/ai/test_harness/` provides:

```
test_harness/
├── benchmark_suite.py      # BenchmarkSuite, BenchmarkScenario, checkpoint/resume
├── evaluators.py           # BaseEvaluator, ToolEvaluator, WorkflowEvaluator, ScientificEvaluator, CompositeEvaluator
├── metrics_collector.py    # JobMetrics, ResourceUsage, QualityMetrics
├── results_analyzer.py     # ResultsAnalyzer, ComparisonReport, StatisticalResult
├── user_context.py         # UserBenchmarkContext, EvaluationTask, EvaluationCriteria
├── sgi_bench_adapter.py    # SGIBenchDataLoader, SGIScorer — ALREADY INTEGRATED
└── validate_sgi_bench.py   # Validation utilities
```

**Extension pattern for a new benchmark:**
1. Create `<benchmark_name>_adapter.py` alongside `sgi_bench_adapter.py`
2. Implement `BenchmarkAdapter` interface: `load_tasks()` → list of `EvaluationTask`, `score(task, agent_response)` → float
3. Register a new `BenchmarkScenario` in `benchmark_suite.py` (or a separate runner script)
4. Write results to `BenchmarkResultsDB` for statistical analysis via `results_analyzer.py`

The `CompositeEvaluator` in `evaluators.py` allows stacking multiple evaluators — a new benchmark adapter slots in as an additional `ScientificEvaluator` subclass.

---

## Implementation Plan Per Benchmark

---

### IMPL-1: BiomniEval1 (BM-3) — PARTIALLY DONE

**Status:** Loader already exists at `/home/yzhang/biomate/Biomni/biomni/eval/biomni_eval1.py`  
**Gap:** Not yet wired into `BenchmarkSuite`; no runner script; no results stored in `BenchmarkResultsDB`

**Data source:**
```bash
# Requires HuggingFace access (Apache 2.0, no auth needed)
pip install datasets pandas pyarrow
python -c "from biomni.eval.biomni_eval1 import BiomniEval1; e = BiomniEval1()"
# Downloads ~50MB parquet from hf://datasets/biomni/Eval1/
```

**How evaluation works:**
```python
evaluator = BiomniEval1()
# For each task instance:
score = evaluator.evaluate(
    task_name="gwas_causal_gene_opentargets",  # or any of the 7 task types
    task_instance_id=42,                        # integer, task-specific index
    user_answer="BRCA1"                         # string, format depends on task
)
# Returns float 0.0 or 1.0 (binary)
```

**BioMate integration — new file to create:**
`backend/lib/galaxy/ai/test_harness/biomni_eval1_adapter.py`

```python
# Pseudocode — adapter wrapping existing BiomniEval1 loader
class BiomniEval1Adapter:
    """Bridges BiomniEval1 to BioMate's BenchmarkSuite."""

    BIOINFORMATICS_TASKS = [
        "gwas_variant_prioritization",
        "gwas_causal_gene_opentargets",
        "screen_gene_retrieval",
        "rare_disease_diagnosis",
        "patient_gene_detection",
    ]

    def load_tasks(self) -> List[EvaluationTask]:
        """Load all instances for bioinformatics-relevant tasks."""
        evaluator = BiomniEval1()
        tasks = []
        for task_name in self.BIOINFORMATICS_TASKS:
            subset = evaluator.df[evaluator.df["task_name"] == task_name]
            for _, row in subset.iterrows():
                tasks.append(EvaluationTask(
                    task_id=f"biomni_eval1_{task_name}_{row['task_instance_id']}",
                    domain=EvaluationDomain.LIFE_SCIENCE,
                    task_type=SGITaskType.REASONING,
                    question=row["question"],
                    ground_truth=row["answer"],
                    metadata={"task_name": task_name, "instance_id": row["task_instance_id"]}
                ))
        return tasks

    def score(self, task: EvaluationTask, agent_response: str) -> float:
        """Route to BiomniEval1's task-specific reward function."""
        return self.inner_evaluator.evaluate(
            task.metadata["task_name"],
            task.metadata["instance_id"],
            agent_response
        )
```

**Runner script:** `backend/scripts/run_biomni_eval1.py`
- Load all 5 bioinformatics task types (~200 instances)
- For each: call BioMate's `/api/chat` endpoint with the question
- Extract answer from BioMate response
- Score with `BiomniEval1.evaluate()`
- Save to `BenchmarkResultsDB` with scenario `"biomni_eval1_bioinformatics"`

**Estimated effort:** 1 day  
**Compute:** ~200 LLM API calls; ~$5–10 in API costs; ~2h wall time

---

### IMPL-2: BixBench / BixBench-Verified-50 (BM-1/BM-2)

**Status:** Not integrated  
**Data source:**
```bash
git clone https://github.com/Future-House/BixBench
cd BixBench
pip install -e .
# Dataset is included in repo under bixbench/data/
```

**How evaluation works:**
- Each scenario is a directory: `scenario_id/` with `data/` files + `questions.json`
- `questions.json` has `[{id, question, answer, answer_type}]`
- Agent must be able to read files in `data/` and answer the question
- Scoring:
  - `answer_type == "multiple_choice"`: exact match against option letter
  - `answer_type == "open_answer"`: LLM judge call — `gpt-4o` compares agent answer to ground truth

**BioMate integration approach:**
- BixBench was designed for Docker-based agents with file system access
- BioMate is a web service — two options:
  1. **REST API mode:** Send question + file contents as base64 in the BioMate chat API; agent reads and analyzes
  2. **Tool mode (preferred):** Mount BixBench data directory as accessible to BioMate's execution backend; pass file paths in the question

**New file:** `backend/lib/galaxy/ai/test_harness/bixbench_adapter.py`

```python
# Pseudocode
class BixBenchAdapter:
    """Loads BixBench scenarios and scores BioMate responses."""

    def __init__(self, bixbench_path: str, variant: str = "original"):
        # variant: "original" | "verified50"
        self.path = Path(bixbench_path)
        self.variant = variant

    def load_tasks(self) -> List[EvaluationTask]:
        tasks = []
        for scenario_dir in self.path.glob("scenarios/*/"):
            questions = json.load(open(scenario_dir / "questions.json"))
            for q in questions:
                tasks.append(EvaluationTask(
                    task_id=f"bixbench_{scenario_dir.name}_{q['id']}",
                    domain=EvaluationDomain.LIFE_SCIENCE,
                    task_type=SGITaskType.DRY_EXPERIMENT,
                    question=q["question"],
                    ground_truth=q["answer"],
                    metadata={
                        "answer_type": q["answer_type"],
                        "data_dir": str(scenario_dir / "data"),
                        "scenario": scenario_dir.name,
                    }
                ))
        return tasks

    def score(self, task: EvaluationTask, agent_response: str) -> float:
        if task.metadata["answer_type"] == "multiple_choice":
            # Extract option letter from agent_response
            return 1.0 if extract_mc_answer(agent_response) == task.ground_truth else 0.0
        else:
            # LLM judge
            return llm_judge_score(
                question=task.question,
                ground_truth=task.ground_truth,
                agent_answer=agent_response
            )
```

**LLM judge:** Use Anthropic Claude claude-haiku-4-5-20251001 as judge (cost-efficient; consistent with BioMate's existing Haiku usage pattern in `routes.ts`). Prompt: compare agent answer to ground truth, return "correct" or "incorrect".

**For BixBench-Verified-50:** Phylo has not released the verified dataset publicly as of April 2026. Options:
1. Request from Phylo (contact via phylo.bio)
2. Self-curate: run both original BixBench and identify questions with wrong/ambiguous ground truth using an LLM, then build our own verified subset
3. Report scores on original BixBench + note that Phylo's Verified-50 addresses ground truth issues

**Estimated effort:** 2 days (excluding BixBench-Verified-50 dataset acquisition)  
**Compute:** ~300 LLM judge calls + ~300 BioMate calls; ~$20–30 in API costs

---

### IMPL-3: BioAgentBench (BM-4)

**Status:** Not integrated  
**Data source:** Released alongside paper arXiv:2601.21800; check GitHub associated with paper for download link.

**How evaluation works:**
- 3 pipeline types: RNA-seq, variant calling, metagenomics
- Each pipeline has a baseline task + 4 perturbation variants
- **Input:** task description string + input file paths
- **Evaluation:** domain-specific output validation:
  - RNA-seq: top DE genes overlap with known list; output file format valid
  - Variant calling: variant count in expected range; VCF format valid; Ti/Tv ratio ~2.0–2.1 for WGS
  - Metagenomics: top taxa match expected community; diversity metric in range
- **Robustness scoring:** run same task under each of 4 perturbations; record whether BioMate detects the perturbation, reports it, and either recovers or fails gracefully (vs. silently producing wrong output)

**BioMate's prereq validation and approval gate are directly testable here:**
- Corrupted input perturbation → does prereq validator catch it?
- Missing intermediate output → does the approval gate surface it?
- Prompt bloat → does domain routing still select correct workflow?

**New file:** `backend/lib/galaxy/ai/test_harness/bioagentbench_adapter.py`

Key addition vs other adapters: `score_robustness()` method that runs all 4 perturbations and returns a `RobustnessReport` with per-perturbation pass/fail + failure mode classification:
- `SILENT_FAILURE` — wrong output, no error reported
- `DETECTED_UNRECOVERED` — error reported but pipeline aborted
- `DETECTED_RECOVERED` — error reported and pipeline succeeded with correct output (BioMate's target behavior)
- `FALSE_ALARM` — error reported on a valid input

**Estimated effort:** 3 days  
**Compute:** 3 pipelines × 5 variants = 15 runs; each run ~5–15 min; ~2h total compute

---

### IMPL-4: ScienceAgentBench (BM-5)

**Status:** Not integrated  
**Data source:**
```bash
git clone https://github.com/OSU-NLP-Group/ScienceAgentBench
# Dataset: 102 tasks in JSON; associated paper datasets in separate download
```

**How evaluation works:**
- Each task: `{task_id, paper_title, task_description, dataset_path, gold_program_path}`
- Agent generates a Python program; program is auto-executed in sandboxed Python environment
- Output compared to gold standard output (numerical tolerance for floats; exact for strings)
- **BioMate approach:** Feed `task_description` + dataset file paths to BioMate; ask it to generate and execute a Python script; capture output; compare to gold

**BioMate's Bioconductor KB is directly relevant** for the bioinformatics subset (~30 of 102 tasks): KB-grounded generation should produce higher function citation accuracy (88.2% KB-grounded vs 71.4% LLM-only, already measured).

**New file:** `backend/lib/galaxy/ai/test_harness/sciagentbench_adapter.py`

```python
# Pseudocode
class SciAgentBenchAdapter:
    BIOINFORMATICS_TASK_IDS = [...]  # filter to bioinformatics subset

    def score(self, task, agent_response) -> float:
        # Extract code from agent_response (look for ```python block)
        code = extract_code_block(agent_response)
        # Execute in sandboxed subprocess with timeout=120s
        result = run_sandboxed(code, working_dir=task.metadata["dataset_path"])
        # Compare to gold output
        return compare_outputs(result.stdout, task.ground_truth, tolerance=1e-4)
```

**Estimated effort:** 2 days  
**Compute:** ~30 bioinformatics tasks × ~60s each = ~30 min

---

### IMPL-5: SGI-Bench (BM-6) — MOSTLY DONE

**Status:** Data loaded, adapter written, 20-sample validation passed. **Gap: not yet run against live BioMate LLM API.**

**How to run full evaluation:**
```bash
# Existing validation script
cd backend/lib/galaxy/ai/test_harness/
python validate_sgi_bench.py  # runs 20 samples with mock responses

# To run with live API:
# 1. Ensure ANTHROPIC_API_KEY is set in backend/.env
# 2. Run the full 503-sample evaluation:
python -m galaxy.ai.test_harness.run_sgi_bench_full \
    --discipline life \
    --n_samples 503 \
    --output results/sgi_bench_life_$(date +%Y%m%d).json
```

**New file needed:** `backend/lib/galaxy/ai/test_harness/run_sgi_bench_full.py` — a thin runner that:
1. Calls `SGIBenchDataLoader.load_samples(discipline="life", max_samples=503)`
2. For each sample, calls BioMate's `/api/chat` endpoint
3. Calls `SGIScorer.score(sample, response)` → `{criterion: float}` dict
4. Aggregates by task type and saves to `BenchmarkResultsDB`

**Estimated effort:** 0.5 days  
**Compute:** 503 samples × avg 2 LLM calls = ~1,000 calls; ~$10–15; ~3h wall time

---

### IMPL-6: BioML-bench (BM-7)

**Status:** Not integrated  
**Data source:**
```bash
git clone https://github.com/science-machine/biomlbench
```

**How evaluation works:**
- 4 domain sub-tasks: protein engineering, single-cell omics, biomedical imaging, drug discovery
- Each: agent receives a specification document + dataset; produces predictions
- Predictions submitted to automated scoring (AUROC, Spearman)
- The single-cell omics and drug discovery subtasks are most relevant to BioMate

**BioMate integration:**
- Focus on **scRNA-seq** and **drug discovery** subtasks initially
- For each task: pass specification to BioMate chat, receive a pipeline execution plan + results
- Extract quantitative predictions from BioMate's output (cell state labels for scRNA-seq; ADMET predictions for drug discovery)
- Score with BioML-bench's grading scripts

**Estimated effort:** 3 days  
**Compute:** ~20 tasks across 2 domains; moderate (depends on Nextflow execution for drug discovery)

---

### IMPL-7: PharmaBench (BM-9)

**Status:** Not integrated  
**Data source:**
```bash
git clone https://github.com/mindrank-ai/PharmaBench
# Contains 11 datasets as CSV/SDF files with SMILES + labels
```

**How evaluation works:**
- Standard ML benchmark: train split provided; test split used for evaluation
- Agent must build or select a model that predicts the ADMET property
- For BioMate: the evaluation is about **workflow selection + execution accuracy**, not model training
- Approach:
  1. Given a compound SMILES and property type (e.g., "hERG cardiotoxicity"), BioMate selects the correct ADMET workflow
  2. Workflow runs a prediction pipeline (ML model or cheminformatics tool)
  3. Compare predictions to PharmaBench ground truth
  4. Metric: ROC-AUC per dataset; average across 11 datasets

**New file:** `backend/lib/galaxy/ai/test_harness/pharmabench_adapter.py`

**Estimated effort:** 3 days (plus ADMET pipeline setup if not already done)  
**Compute:** 11 datasets; small molecules; fast ML inference; ~1h total

---

### IMPL-8: HeurekaBench (BM-8)

**Status:** Not integrated  
**Data source:** Contact EPFL MLBio Lab (brbiclab.epfl.ch) or check for public release; paper is ICLR 2026

**How evaluation works:**
- sc-HeurekaBench: 22 papers → 50 OEQs + 50 MCQs per paper
- MCQ: exact match scoring
- OEQ: LLM judge with rubric (coherence, correctness, depth)
- Input to agent: paper abstract/excerpts + question
- BioMate's domain specialist routing and Bioconductor KB are relevant here

**Plan:** Request dataset from EPFL MLBio Lab; implement adapter following same pattern as BiomniEval1 adapter.

**Estimated effort:** 1.5 days (once dataset obtained)

---

### IMPL-9: Galaxy Workflow Retrieval Benchmark (BM-10)

**Status:** BioMate already has a retrieval system; benchmark dataset not formally obtained  
**Data source:** arXiv:2511.01757 — contact authors for dataset; alternatively reconstruct using Galaxy's public workflow library + BERTopic annotations

**How evaluation works:**
- Task: given a natural-language query, retrieve the correct Galaxy workflow
- BioMate evaluation: run the query through `unified_workflow_search.py` (the same two-stage LLM search already implemented)
- Metric: Top-1, Top-3, Top-5 accuracy + MRR@5

**Connection to existing benchmark:**
The BioMate retrieval benchmark at `bioconductor_skill/skill_generation/20260303_retrieval_benchmark.py` already measures Hit@1/3/5 and MRR@5 on 50 curated (task → package) pairs. This can be extended by:
1. Expanding from 50 → 150 queries (cross-domain routing benchmark BM-BIOMATE-3 from benchmark strategy doc)
2. Adding the Galaxy-specific workflow corpus from the Nov 2025 paper
3. Running head-to-head: BioMate two-stage search vs BM25 baseline vs dense-only

**Estimated effort:** 1 day (if retrieval benchmark dataset can be obtained) + 2 days to extend the existing retrieval benchmark

---

## Shared Infrastructure Components

### Component A: BioMate API Client for Evaluation

Create `backend/lib/galaxy/ai/test_harness/biomate_eval_client.py`:

```python
# Pseudocode
class BioMateEvalClient:
    """HTTP client that submits evaluation tasks to BioMate and extracts answers."""

    def __init__(self, base_url: str, user_token: str):
        self.base_url = base_url
        self.token = user_token

    def ask(self, question: str, context_files: List[str] = None) -> str:
        """Send a question to BioMate, wait for response, return answer text."""
        # POST /api/chat/stream with question
        # Stream response until [DONE]
        # Return assembled response text

    def run_workflow(self, question: str, wait_for_terminal: bool = True) -> WorkflowResult:
        """Ask BioMate to run a workflow; wait for terminal state; return outputs."""
        # POST /api/chat → get workflow card
        # POST /api/workflows/runs/{id}/confirm
        # Poll /api/workflows/runs/{id}/status until terminal
        # GET /api/workflows/runs/{id}/output_files
        # Return WorkflowResult(status, outputs, cost, audit_trail)
```

This client wraps BioMate's existing API surface (`routes.ts` endpoints) and is reused by all benchmark adapters.

### Component B: LLM Judge

Create `backend/lib/galaxy/ai/test_harness/llm_judge.py`:

```python
def llm_judge_score(question: str, ground_truth: str, agent_answer: str,
                    model: str = "claude-haiku-4-5-20251001") -> float:
    """Binary LLM judge: is agent_answer equivalent to ground_truth for this question?"""
    # Uses Anthropic API with a structured judge prompt
    # Returns 0.0 or 1.0
```

Use `claude-haiku-4-5-20251001` for cost efficiency (same as BioMate's existing Haiku usage).

### Component C: Benchmark Results Dashboard

Extend `results_analyzer.py` with a `generate_competitive_report()` function that produces a markdown table showing BioMate's scores vs competitor scores from the landscape doc.

---

## Priority Order for Implementation

| Priority | Benchmark | Effort | Why first |
|---|---|---|---|
| P0 | BiomniEval1 (IMPL-1) | 1 day | Already partially done; establishes a comparable score vs Biomni |
| P0 | SGI-Bench full run (IMPL-5) | 0.5 days | Already validated; just needs live API wiring |
| P0 | Retrieval benchmark extension (IMPL-9 partial) | 1 day | Existing 50-task benchmark just needs expansion to 150 |
| P1 | BixBench (IMPL-2) | 2 days | Most cited benchmark; establishes BioMate's position vs 17% baseline |
| P1 | BioAgentBench (IMPL-3) | 3 days | Tests BioMate's unique robustness story |
| P2 | ScienceAgentBench (IMPL-4) | 2 days | ICLR venue; bioinformatics subset directly testable |
| P2 | PharmaBench (IMPL-7) | 3 days | Required for drug discovery paper |
| P3 | BioML-bench (IMPL-6) | 3 days | Establishes scRNA-seq and drug discovery comparison vs Biomni |
| P3 | HeurekaBench (IMPL-8) | 1.5 days | Needs dataset from EPFL first |
| P3 | Galaxy Workflow Retrieval (IMPL-9 full) | 3 days | Needs dataset from paper authors |

**Total estimated effort: ~20 developer-days** for P0+P1+P2 implementations.

---

## Running the Harness

```bash
# Example: run BiomniEval1 on BioMate
cd /home/yzhang/biomate/backend

# 1. Start BioMate backend
bash start_backend.sh &

# 2. Run evaluation
python -m galaxy.ai.test_harness.runners.biomni_eval1_runner \
    --biomate-url http://localhost:8080 \
    --user-token $EVAL_USER_TOKEN \
    --tasks gwas_variant_prioritization gwas_causal_gene_opentargets rare_disease_diagnosis \
    --output results/biomni_eval1_$(date +%Y%m%d).json

# 3. Generate report
python -m galaxy.ai.test_harness.results_analyzer \
    --input results/biomni_eval1_*.json \
    --competitors docs/papers/20260401_COMPETITOR_BENCHMARK_LANDSCAPE.md \
    --output results/competitive_report_$(date +%Y%m%d).md
```
