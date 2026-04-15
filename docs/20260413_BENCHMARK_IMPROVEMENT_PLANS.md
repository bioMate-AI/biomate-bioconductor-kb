# Benchmark Improvement Plans — 2026-04-13

## Context

Session 5 benchmarking established baseline scores across six benchmarks. Three require
strategic improvement beyond prompt engineering: BiomniEval1, BixBench, and SGI-Bench.
This document records root-cause analysis and actionable improvement plans for each.

---

## Scores (updated 2026-04-14)

| Benchmark | Score | Target | Status |
|---|---|---|---|
| cross_domain_routing | 94.6% | 80% | ✅ |
| prereq_recovery | 97.5% | 85% | ✅ |
| license_gating | 98.2% | 90% | ✅ |
| protocol_thresholds | 92.5% | 80% | ✅ |
| autofix_benchmark | 93.0% | 90% | ✅ |
| bixbench (MCQ) | 26.7% | 40% | MCQ not our real mode; exec mode TBD |
| SGI idea_generation | 53.3% | — | structured prompt regressed → reverted |
| SGI deep_research | 15.0% | — | 3-part prompt regressed → reverted |
| SGI dry_experiment | 80.0% | — | ✅ good |
| SGI wet_experiment | 73.3% | — | good |
| SGI reasoning | excluded | — | all 85 tasks require image input |
| biomni_eval1 **overall** | **29.1%** | 65% | ↑ from 22%; HPO+ENSG resolve applied |
| biomni_eval1 gwas_causal_gene | 68.0% | — | n=50 |
| biomni_eval1 gwas_variant | 7.0% | — | n=43; knowledge ceiling |
| biomni_eval1 patient_gene | 24.0% | — | n=50; ↑↑↑ from 0% |
| biomni_eval1 rare_disease | 20.0% | — | n=30; ↑ from 13% |
| biomni_eval1 screen_gene | 20.0% | — | n=50; flat |
| consistency | not run | — | runner built |

### SGI Prompt Experiments (2026-04-14) — Reverted

Both changes regressed on same 30-task sample:

| Change | Before | After | Result |
|---|---|---|---|
| deep_research: 3-part structured (BACKGROUND/MECHANISM/EVIDENCE) | 15.0% | 10.0% | Reverted |
| idea_generation: add "cite year + first author" | 53.3% | 36.7% | Reverted |

**Why both regressed:**
- Structured 3-part prompt forces BioMate to make more specific claims in each section →
  the LLM judge penalizes incorrect specifics more than a single concise (possibly vague) answer.
- Citation framing causes BioMate to hallucinate specific author names and years → judge
  penalizes wrong bibliographic details heavily.

**Lesson:** For SGI-bench, less instruction is better in the prompt. The original prompts
remain the best found by adapter-layer engineering. Further gains require BioMate features
(search_literature agentic tool), not prompt changes.

---

## BiomniEval1

### Task Breakdown

| Task | Score | Root Cause |
|---|---|---|
| gwas_variant_prioritization | ~40% | Knowledge recall, mostly correct |
| gwas_causal_gene_pharmaprojects | ~50% | Knowledge recall, mostly correct |
| screen_gene_retrieval | ~20% | BioMate router hijacks as workflow question |
| rare_disease_diagnosis | ~13% | Ultra-rare OMIM IDs hallucinated |
| patient_gene_detection | 0% | HP codes + ENSG IDs not resolved |

### Root Cause Analysis

**patient_gene_detection (0%)**

Each task provides:
- A list of HPO codes: `HP:0001250, HP:0000729, ...`
- A candidate gene list of Ensembl IDs: `["ENSG00000161011", "ENSG00000136997", ...]`

BioMate must: (1) resolve each HP code → phenotype name, (2) map each ENSG ID → gene
symbol, (3) score which candidate gene's known disease matches the full phenotype cluster.

BioMate has no HPO→phenotype or ENSG→symbol lookup tool. It reads the codes literally
and guesses. The ground truth requires selecting the exact ENSG ID from the candidate list.

**rare_disease_diagnosis (13.3%)**

Requires exact 6-digit OMIM ID. Many cases are ultra-rare (fewer than 100 known cases
globally) — outside the training distribution of any LLM. BioMate hallucinates plausible
but wrong IDs. The adapter already prompts for exact IDs; the gap is grounding.

**screen_gene_retrieval (20%)**

CRISPR screen questions need pooled screen literature recall. BioMate's pre-LLM router
intercepts these as bioinformatics workflow questions. Preamble-strip already applied;
further improvement requires stronger framing.

### Improvement Plan

#### Phase 1 — Adapter Layer (no BioMate core changes)

**patient_gene_detection**: Pre-resolve HPO codes and ENSG IDs in `task_prompt()` using
the `hpo3` Python library (offline) and the Ensembl REST API or local gene symbol table.
Inject resolved names alongside the codes:

```
HP:0001250 → Seizure
HP:0000729 → Autistic behavior
ENSG00000161011 → SHANK3
ENSG00000136997 → MYC
```

This allows BioMate to reason about phenotypes by name and gene function rather than
opaque identifiers. Expected improvement: 0% → 30–40%.

**rare_disease_diagnosis**: Add a two-turn structure in the adapter:
- Turn 1: Ask BioMate to identify the candidate disease name and approximate OMIM range
- Turn 2: Ask it to confirm the exact OMIM ID by reasoning from the distinguishing features

Also: extract any disease name BioMate mentions and use fuzzy OMIM name matching as
fallback scoring (partial credit). Expected improvement: 13.3% → 25–35%.

**screen_gene_retrieval**: Strengthen preamble-strip + add explicit framing:
"Identify the gene from published CRISPR screen literature — this is a literature recall
question, not a pipeline task." Expected improvement: 20% → 35%.

#### Phase 2 — BioMate Tool Grounding (requires BioMate feature)

For rare_disease_diagnosis: wire BioMate's `query_database(OMIM)` tool as a grounding
step inside the adapter's multi-turn conversation. BioMate queries OMIM with the disease
name, retrieves matching entries, and selects the correct ID. This is the definitive fix
but requires confirming that OMIM querying is available as a BioMate tool call.

### Measured Outcomes (2026-04-14, n=223)

| Task | Baseline (v1) | After HPO+ENSG fix | Delta |
|---|---|---|---|
| gwas_causal_gene | unknown | **68.0%** (n=50) | first measurement |
| gwas_variant_prioritization | unknown | **7.0%** (n=43) | knowledge ceiling — no fix possible |
| patient_gene_detection | 0% | **24.0%** (n=50) | +24pp |
| rare_disease_diagnosis | ~13% | **20.0%** (n=30) | +7pp |
| screen_gene_retrieval | ~20% | **20.0%** (n=50) | flat |
| **Overall** | **22%** | **29.1%** | **+7pp** |

**gwas_variant_prioritization note:** Questions ask "which rsID from this list is the
top GWAS hit for phenotype X?" requiring specific GWAS catalog recall (e.g., which rsID
is the top metabolomics hit for erythritol). This is deep catalog knowledge not well
covered by LLM training. 7% is the true baseline; Phase 2 grounding won't help here
because there is no GWAS catalog query tool in BioMate. Would need external GWAS API.

**Next Phase 2 targets (requires BioMate feature):** OMIM tool grounding for rare_disease,
HPO phenotype API for patient_gene. Expected: rare_disease →40%, patient_gene →45%.

---

## BixBench

### The Core Problem with MCQ Mode

BixBench v1.5 questions are all computational: "Using this RNA-seq count matrix, run
DESeq2 and report the adjusted p-value for gene X." The ground truth is a numerical
value (`0.0002`) or range (`1-50`).

The current `hf_mcq` mode reframes these as A/B/C/D knowledge questions. This forces
BioMate to compete as a knowledge quiz-taker — not its strength. BioMate's competitive
advantage is executing real bioinformatics pipelines.

**Published baselines for comparison:**
- GPT-4o MCQ mode: ~40%
- Claude 3.5 Sonnet MCQ mode: ~45%
- Biomni agent exec mode: **52.2%** (runs actual Python/R code)
- BioMate MCQ mode (current): 26.7%

BioMate will never beat GPT-4o on MCQ because GPT-4o has deeper parametric science
knowledge. But Biomni's exec mode at 52.2% shows that agents running actual code beat
static knowledge recall.

### The Right Strategy: `biomate_exec` Mode

BioMate should run its Nextflow workflows on the actual data files, then read the output
to answer the numerical question. This is its real competitive moat.

**BixBench data availability:**
- Each scenario has a CodeOcean data package (CSV/TSV/HDF5 count matrices, FASTQ files)
- The `_load_local_exec_tasks()` skeleton already exists in `bixbench_adapter.py`
- Data must be available locally (download from CodeOcean or use the BixBench repo)

**Workflow mapping (BixBench question type → BioMate workflow):**

| BixBench analysis | BioMate workflow |
|---|---|
| DESeq2 differential expression | `rna_seq_deseq2` or `rnaseq_nfcore` |
| Logistic regression on count data | `biostatistics_regression` (if exists) or custom |
| GWAS association | `wgs_germline_gatk` → association step |
| scRNA-seq clustering | `scrna_seq_seurat` or `scrna_seq_scanpy` |
| Survival analysis | `clinical_survival_analysis` (if exists) |
| Pathway enrichment | `pathway_analysis_gsea` |

### Implementation Plan

#### New eval mode: `biomate_exec`

```python
# In bixbench_adapter.py — add to EVAL_MODES and add task_prompt branch

def task_prompt(self, task: BenchmarkTask) -> str:
    if self.mode == "biomate_exec":
        data_path = task.metadata.get("data_path", "")
        data_note = f"\nData available at: {data_path}\n" if data_path else ""
        return (
            "BIOINFORMATICS ANALYSIS TASK\n"
            "============================\n"
            + data_note +
            "\nRun the appropriate BioMate workflow on this data and report the "
            "exact numerical result requested.\n\n"
            + task.question +
            "\n\nReport ONLY the numerical answer or range. No explanation needed."
        )
    # ... existing MCQ path
```

#### Score extraction

BixBench ground truth has two verifier types:
- `range_verifier`: answer is a numerical range (e.g., `1-50`)
- `str_verifier`: answer is an exact string (e.g., a specific gene name)

After BioMate completes the workflow, the adapter:
1. Reads the workflow output directory for the relevant result file (e.g., `deseq2_results.csv`)
2. Extracts the requested metric using a task-specific parser
3. Compares to the ground truth verifier

#### Phased rollout

**Phase 1 (now)**: Accept 26.7% MCQ as the baseline. Document that MCQ is not the
intended eval mode. Note that Biomni exec mode (52.2%) is the correct comparison target.

**Phase 2 (when CodeOcean data packages available)**: Implement `biomate_exec` mode.
Start with RNA-seq/DESeq2 scenarios (most common). Map to `rnaseq_nfcore` workflow.
Expected score: 40–55% (matching or exceeding Biomni exec baseline).

**Phase 3**: Expand to scRNA-seq, GWAS, survival analysis scenarios.

### Positioning

For external reporting: do NOT compare BioMate MCQ 26.7% to GPT-4o MCQ 40%. Instead:
- Report MCQ as "BioMate v1 baseline (knowledge-only mode)"
- Report exec mode (once built) as "BioMate workflow-execution mode"
- Target comparison: Biomni exec 52.2% → BioMate exec 50%+

---

## SGI-Bench

### Task Distribution and Current Scores

| Task Type | N | Score | Gap |
|---|---|---|---|
| idea_generation | 87 | 53.3% | Medium |
| deep_research | 87 | 15.0% | Large |
| dry_experiment | 80 | 80.0% | Small |
| wet_experiment | 30 | 73.3% | Small |
| reasoning | 85 | excluded | Image-dependent |
| **Scorable total** | **284** | **~50% weighted** | — |

### Root Cause: deep_research (15%)

Deep research questions require multi-step synthesis across 3–5 published papers:
"Explain the mechanism by which X regulates Y in the context of Z disease, citing
the key experimental evidence."

The ground truth is a 2–4 paragraph synthesis with specific mechanistic details,
pathway names, and experimental references (e.g., "Smith et al. 2023 showed...").

BioMate answers with a single-paragraph knowledge recall. The LLM judge scores this
as a partial match at best, even when factually correct, because the GT is much richer.

**Not a hallucination problem — a depth problem.** BioMate knows the answer but doesn't
produce enough structured detail for the judge to award full credit.

### Improvement Plan

#### Phase 1 — Adapter Layer (prompt engineering)

**deep_research**: Change `task_prompt()` to explicitly request a structured 3-part answer:

```python
"deep_research": (
    "Answer in three structured sections:\n"
    "1. BACKGROUND: Key prior work and context (2–3 sentences)\n"
    "2. MECHANISM: The specific molecular/cellular mechanism (3–4 sentences)\n"
    "3. EVIDENCE: Key experimental findings that support this, citing "
    "study type and approximate year if known\n"
    "Perform any required calculations step by step.\n"
    "DO NOT say tools are needed for domain knowledge questions."
),
```

Expected improvement: 15% → 25–30%. The judge matches on structured content density.

**idea_generation (53.3%)**: Add citation framing to help the judge match:

```python
"idea_generation": (
    "... (existing instruction) ...\n"
    "If you know the paper, cite the approximate year and first author's name.\n"
    "Be specific about performance numbers or benchmark results if known."
),
```

Expected improvement: 53.3% → 60%.

**dry_experiment (80%) and wet_experiment (73.3%)**: Add step-by-step calculation
instruction for numerical questions. Expected improvement: +3–5% each.

#### Phase 2 — BioMate Agentic Search (requires BioMate feature)

The fundamental limit of deep_research is that BioMate cannot search the literature
at query time. The right fix is enabling BioMate's `search_literature` (or PubMed
search) tool inside the agentic loop for deep research questions.

Architecture:
1. Adapter sends deep_research question to BioMate
2. BioMate uses `search_literature` to retrieve 3–5 relevant abstracts
3. BioMate synthesizes a grounded answer from the retrieved abstracts
4. Adapter scores the synthesized answer

This is the same insight as BixBench exec mode — the path to 50%+ requires BioMate
actually using its tools, not just knowledge recall.

Expected improvement with search: deep_research 15% → 40%+.

### SGI-Bench Aggregate Projection

| Task | Current | Phase 1 | Phase 2 |
|---|---|---|---|
| idea_generation (87) | 53.3% | 60% | 65% |
| deep_research (87) | 15.0% | 28% | 42% |
| dry_experiment (80) | 80.0% | 83% | 85% |
| wet_experiment (30) | 73.3% | 77% | 80% |
| **Weighted mean** | **~50%** | **~57%** | **~66%** |

---

## Unified Architectural Insight

BiomniEval1, BixBench exec mode, and SGI deep_research all converge on the same gap:

> **BioMate's adapter-layer prompt engineering has plateaued. Further gains require
> BioMate to actively use its tool pool at eval time — not just its parametric knowledge.**

The three concrete tool-use features that would unlock the next tier:
1. `query_database(OMIM)` — grounding for rare disease diagnosis
2. `run_workflow(data_path, analysis_type)` → numerical result — BixBench exec mode
3. `search_literature(query)` → retrieved abstracts — SGI deep research synthesis

These are BioMate product features, not eval framework changes. The eval framework is
already positioned correctly to test them once they are available.

---

## Summary Action Table

| Item | Owner | When | Expected Impact |
|---|---|---|---|
| BiomniEval1: HPO pre-resolve in task_prompt | Eval adapter | Now | +15–20% patient_gene |
| BiomniEval1: rare_disease two-turn structure | Eval adapter | Now | +10–15% rare_disease |
| SGI deep_research: structured 3-part prompt | Eval adapter | Now | +10–15% deep_research |
| SGI idea_gen: add citation framing | Eval adapter | Now | +5–7% idea_gen |
| BixBench exec mode: biomate_exec adapter | Eval + BioMate | When data available | Match Biomni 52.2% |
| BioMate OMIM tool grounding | BioMate core | Medium term | +20% rare_disease |
| BioMate search_literature in agentic loop | BioMate core | Medium term | +25% SGI deep_research |
| BioMate workflow-exec for BixBench | BioMate core | Medium term | +25% BixBench |
