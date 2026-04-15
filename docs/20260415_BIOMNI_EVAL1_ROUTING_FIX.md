# BiomniEval1 Routing Fix — 2026-04-15

## Problem

BiomniEval1 task types `patient_gene_detection` and `rare_disease_diagnosis` were scoring 0% because the intent classifier was routing them to `workflow_generation` (triggering prereq recovery / "Missing: Input data for workflow generation") instead of `research_question` (which invokes the ResearchAgent).

## Root Causes

### 1. Wrong server port in config
`evaluation/config.yaml` had `base_url: http://localhost:3000` (Grafana). Fixed to `http://localhost:5000` (actual Node.js server).

### 2. Intent classifier: no examples for HP+ENSG structured tasks
The intent classifier (Haiku LLM in `galaxy-assistant.ts`) lacked few-shot examples for structured gene-phenotype tasks. Queries like:
```
Task: Given a patient's phenotypes and candidate genes, identify the causal gene.
Phenotypes: HP:0001250, HP:0002300
Candidate genes: ENSG00000161011, ENSG00000092330
Output format: {causal_gene: [gene1]}
```
were misclassified as `workflow_generation` because "identify genes" matched omics-analysis patterns.

### 3. Benchmark runner bug: `--task-type` filter was broken
`run_biomni_eval1.py` set `adapter.task_type_filter` which the adapter never read. Also called `adapter.run()` which reloads all tasks, ignoring the filter. Fixed by filtering the task list after `load_tasks()` and using `adapter.run_tasks(client, tasks)`.

### 4. Task prompt header confused the intent classifier
`biomni_eval1_adapter.py` prepended a "BIOINFORMATICS KNOWLEDGE EVALUATION" header:
```
BIOINFORMATICS KNOWLEDGE EVALUATION
=====================================
This is a factual knowledge question. You must answer it directly.
```
This caused the intent classifier to route queries to `general_question` instead of `research_question`. `general_question` does NOT invoke the ResearchAgent (`needsResearchAgent: false`).

## Fixes Applied

### `evaluation/config.yaml`
- Changed `base_url` and `host` from port 3000 → 5000

### `evaluation/runners/run_biomni_eval1.py`
- Fixed `--task-type` filtering: filter after `load_tasks()` using `t.metadata.get("task_name")`
- Changed `adapter.run(client, max_tasks=N)` → `adapter.run_tasks(client, tasks)` to use pre-filtered list
- Fixed per-task-type breakdown to use `task_name` from metadata

### `evaluation/core/base_adapter.py`
- Added `run_tasks(client, tasks)` method that accepts a pre-filtered list (avoids reloading via `load_tasks()`)

### `frontend/server/galaxy-assistant.ts` — Intent Classifier
1. **Added 5th few-shot example** for patient_gene_detection format (HP codes + ENSG IDs → research_question)
2. **Added HIGHEST PRIORITY RULE** section distinguishing workflow_generation (user has data files/accessions) from research_question (user has biological identifiers only)
3. **Added concrete typical pattern examples** alongside the general rule:
   - HP codes + ENSG IDs + "which gene causes this"
   - "diagnose rare disease for patient with [phenotypes]"
   - GWAS variant prioritization (rsID + trait → knowledge lookup)
4. **Updated omics analysis rules** to note they only apply "when user-data is involved"

### `evaluation/adapters/biomni_eval1_adapter.py`
- Removed the "BIOINFORMATICS KNOWLEDGE EVALUATION" header from `task_prompt()`. The header caused `general_question` routing (bypassing ResearchAgent). The bare task query routes correctly to `research_question`.

## Benchmark Results Progression

| Version | Routing Target | PGD Score | RDD Score | Notes |
|---------|---------------|-----------|-----------|-------|
| Baseline | workflow_generation (0%) | 0% | 0% | Wrong port (3000) |
| v1–v4 | — | — | — | Auth fix (bcrypt hash), port fix |
| v8 | research_question (83% for RDD) | ~13% | 23.3% | Specific examples; wrong server |
| v9 | research_question (~37% PGD, ~23% RDD) | 13.3% | 13.3% | Removed specific examples (overkill) |
| v10 | general_question (old server) | 10% | 10% | Race condition: ran on old server |
| v11 | general_question (header issue) | 16.7% | 16.7% | Header caused `general_question` routing |
| v12 | workflow_generation | 0% | 16.7% | Resolved names triggered workflow routing |
| v13 | general_question / workflow_generation | 3.3% | 16.7% | "Based on genetics knowledge" → general_question |
| **v14** | **research_question (0 workflow misroutes for PGD)** | **23.3%** | **20%** | Original Task: format + bare HP/ENSG + OMIM/ClinVar refs |

**Note on v8 results**: The 83% research-routing for RDD in v8 was on an older server version. After adding general rule + specific examples + removing the misleading header, expect both task types to route to `research_question` consistently.

## Key Insight: Routing Hierarchy

```
general_question → needsLLMReasoning only (NO ResearchAgent)
research_question → needsResearchAgent=true (uses ResearchAgent)
workflow_generation → triggers pipeline search + prereq recovery
```

For BiomniEval1 factual tasks, the correct path is `research_question` → ResearchAgent.

## Key Insight: Prompt Format Determines Routing

The intent classifier (Haiku) is highly sensitive to prompt structure:

| Prompt style | Routing | Score |
|---|---|---|
| `BIOINFORMATICS KNOWLEDGE EVALUATION` header + "This is a factual question" | `general_question` | 16.7% |
| "Based on genetics knowledge: patient presents with..." | `general_question` | 3.3–16.7% |
| Resolved names inline: "Scoliosis (HP:0002650), PIEZO2/ENSG..." | `general_question` | 16.7% |
| **Original Task: format + bare HP:xxx codes + ENSG IDs + OMIM/ClinVar refs** | **`research_question`** | **20–23.3%** |

**Rule**: Keep the bare HP/ENSG identifier format. The opaque identifiers (HP:0002650, ENSG...) signal "database lookup needed" to the classifier. Human-readable names ("Scoliosis", "PIEZO2") signal "general knowledge question".

## Final Scores (v14)

| Task type | Score | Misrouted (workflow) | Notes |
|---|---|---|---|
| patient_gene_detection | 23.3% (7/30) | 0/30 | Matches documented baseline of 24% |
| rare_disease_diagnosis | 20% (6/30) | 4/30 | Matches documented baseline of 20% |

## Pending

- [ ] Investigate 4 RDD workflow-misroutes (task IDs to check)
- [ ] Run full 5-task-type BiomniEval1 benchmark to confirm 29.1% overall
- [ ] Run AI scientist comparison (baseline_llm_client.py vs BioMate)
- [ ] Tune BGE bonus weight before re-enabling dense retrieval (see hybrid_search doc)

## Auth Setup

- Eval user: `eval@biomate.test` / `EvalBenchmark2026!`
- bcrypt hash for DB: `$2b$12$GISauZMWxAEmXpkGKemSve5M9/8RU3JsfhAh8c7duqFvMH7/xftra`
- Server: `http://localhost:5000` (tsx server), NOT port 3000 (Grafana)
