# BioMate: Speed-Up, LLM Pilot, and Cross-Domain Uniqueness Strategy

**Date:** 2026-07-04  
**Context:** Answers to three open strategic questions from prior sessions.  
**Links to:** `20260701_BIOMATE_AUTOIMMUNE_STRATEGY_AND_LLM_TRAINING.md`, `20260701_BIOMATE_SYSTEM_VALIDATION_PLAN.md`

---

## 1. Further Speed-Up

Three levers in priority order:

### 1-A: Tiered Model Routing (highest impact)

Today every chat message hits the same model regardless of task complexity. Routing by task type gives 3–5× latency reduction on the 80% of calls that are routing and param-filling:

| Task | Current | Proposed | Expected latency |
|------|---------|----------|-----------------|
| Workflow routing + param extraction | Sonnet 4.6 | Haiku 4.5 | ~0.8s (from ~4s) |
| Biological interpretation paragraph | Sonnet 4.6 | Sonnet 4.6 | unchanged |
| §2.6 IND narrative generation | Sonnet 4.6 | gemini-3.5-flash or Opus | longer but better quality |
| Simple disambiguation | Sonnet 4.6 | Haiku 4.5 | ~0.5s |

Implementation: add a `task_complexity` classifier in `galaxy-assistant.ts` — route on `workflow_type` from `parseActions`. Routing and param tasks already have `workflow_type === 'workflow_generation'`; these can be Haiku without quality loss.

### 1-B: Nextflow Process-Level Parallelism

The ADMET ensemble (Test 8-A) already runs 3 tools in parallel. Apply the same pattern to:

- **DE ensemble** (Test 8-C): DESeq2 + edgeR + limma-voom in parallel, not sequential. Current sequential runtime ~18 min; parallel ~7 min (limited by slowest tool).
- **GWAS → scRNA → eQTL chain** (Test 1-A): coloc and scGWAS can overlap — coloc needs only GWAS summary stats; scGWAS runs on the single-cell reference panel independently. Current sequential; parallel saves ~12 min per run.
- **ADMET + PBPK**: ADMET ensemble and PBPK model setup can run simultaneously; PBPK only needs ADMET output at the exposure calculation step, not during model initialization.

Implementation: Nextflow `parallel` channel operators; no backend changes required.

### 1-C: Reference Data Pre-Indexing

Eliminate 3–8s API round-trips that currently block every target prioritization run by caching static lookups on the Galaxy backend:

| Data | Current | Cached as | Size |
|------|---------|-----------|------|
| GWAS Catalog loci (top 50 autoimmune) | Live API call | SQLite table | ~2 MB |
| DICE eQTL scores (20 top RA loci × 8 immune cell types) | Live API call | JSON fixture | ~500 KB |
| ChEMBL approved drug counts (top 1,000 targets) | Live API call | SQLite table | ~5 MB |
| OpenTargets association scores (RA panel) | Live API call | Parquet cache | ~20 MB |

Cache invalidation: nightly cron job refreshes from live APIs. Cache TTL: 24h.
Implementation: `backend/lib/galaxy/webapps/galaxy/api/reference_cache.py` (new module).

### 1-D: Nextflow `-resume` for QC-Loop Reruns (60–80% latency reduction on partial reruns)

**Added 2026-07-06.** The auto-loop QC gate reruns a workflow after remediation (e.g., hERG gate fires → structural modification → re-ADMET). Today every rerun starts from scratch. Nextflow's built-in `-resume` flag caches completed process outputs by input hash and skips any process whose inputs are unchanged.

Concrete impact on the ADMET auto-loop:
- First run: ADMET ensemble (3 tools) + PBPK = ~18 min
- hERG gate fires; structural modification changes only the SMILES
- Rerun with `-resume`: RDKit featurization reruns (SMILES changed); Chemprop model inference reruns; PBPK reruns — but any upstream steps with unchanged inputs (file staging, reference data loading) are cached
- Expected rerun time: ~6–8 min (60–65% reduction)

For the DE ensemble QC loop (batch correction gate fires → ComBat-seq → re-DE):
- ComBat-seq output changes; downstream DESeq2 must rerun
- But edgeR and limma-voom jobs that completed before the gate fired can be resumed if inputs are the same
- Expected rerun time: ~5 min instead of ~18 min (72% reduction)

Implementation: pass `-resume` flag in `nextflow_executor.py` `run_nextflow()` call when `run_mode == 'autoloop_rerun'`. Nextflow work directory must be retained between runs (currently deleted on completion — change to retain for 24h).

### 1-E: AWS Batch Array Jobs for Compound Libraries (50× throughput on ADMET screening)

**Added 2026-07-06.** Today each compound in an ADMET screen is submitted as a separate Batch job, each with its own job startup overhead (~30–60s per job for container pull + init). For a 1,000-compound library this means 1,000 sequential job submissions or 1,000 concurrent jobs each paying full startup cost.

AWS Batch array jobs submit N tasks as a single job definition with a job index environment variable (`AWS_BATCH_JOB_ARRAY_INDEX`). The container starts once per compute instance and processes its assigned compound index. Result: startup cost paid once per instance, not once per compound.

| Library size | Current (individual jobs) | Array jobs | Speedup |
|-------------|--------------------------|-----------|---------|
| 100 compounds | ~60 min (60s startup × 100) | ~3 min | 20× |
| 1,000 compounds | ~600 min | ~12 min | 50× |
| 10,000 compounds | Not feasible | ~90 min | >100× |

Implementation:
1. `nextflow_executor.py`: detect when `input_type == 'compound_library'` and `n_compounds > 10`; switch job submission to `submit_job(arrayProperties={'size': n})` 
2. ADMET Nextflow process: read `$AWS_BATCH_JOB_ARRAY_INDEX` to select compound from input list
3. Aggregation step: collect all array task outputs into single results JSON

This directly enables the TL1A PPI fragment screen (Test 5-B) and any virtual screening workflow at scale.

---

## 2. Pilot LLM Adaptation to Autoimmune

Four-layer plan from the strategy, scoped to a **4–6 week pilot on DGX Spark**. Priority order: Layer 3 first (highest demo value, fastest to train), then Layer 4, then Layer 1.

### Layer 3 — Clinical Trial Design LLM (Priority 1)

**Model:** Llama 3.1 8B with LoRA  
**Compute:** ~30 min/epoch at 53,657 tokens/sec on DGX Spark; 3 epochs total  
**Data:** 50 FDA autoimmune NDA/BLA label summaries (all public domain)

| Drug | Indication | MOA | FDA endpoint |
|------|-----------|-----|-------------|
| Baricitinib | RA | JAK1/2 | ACR20 Week 12 |
| Upadacitinib | RA, PsA, AD | JAK1 | ACR20 Week 12 / IGA 0/1 Week 16 |
| Dupilumab | AD, Asthma, CRSwNP | IL-4/IL-13 | IGA 0/1 Week 16 |
| Anifrolumab | SLE | IFNAR1 | BICLA Week 52 |
| … (46 more) | | | |

**Baseline (zero-shot gemini-3.5-flash):** 75% exact match, 85% combined (Test 4-B).  
**Target after LoRA:** ≥85% exact. The 3 known failures (ixekizumab, risankizumab, ustekinumab) are all trainable with 5 examples each — psoriasis PASI 90 vs IGA 0/1 confusion and "response" vs "remission" distinction.

**Training signal:** (indication + MOA) → (primary endpoint + timepoint). Contrastive pairs for the 3 failure modes.

### Layer 4 — Workflow Routing LLM (Priority 2)

**Model:** Contrastive fine-tune on the existing embedding model (BGE-large or the routing model in `galaxy_ai_tools.db`)  
**Compute:** Minimal — embedding model only, no autoregressive generation  
**Data:** 200 annotated (prompt → correct workflow) pairs

Sources:
- Test 4-B failures: 3 psoriasis cases where model confused endpoint scale → add to routing training as disambiguation examples
- Test 2-A holdout set (100 prompts, annotated correct workflow)
- Operator session traces from dev: extract confirmed workflow selections as positive labels

**Target:** routing accuracy ≥85% on held-out set (current estimated ~80% from Test 7-A multi-domain prompt).

### Layer 1 — Cell State Model (Priority 3, requires PEAC DAC access)

**Model:** Geneformer v2 fine-tune  
**Compute:** ~8–12 GPU-hours on DGX Spark (110M params, BF16)  
**Data:**
- GSE89408 RA synovial RNA-seq (152 samples, already downloaded)
- GEO GSE142016 SLE PBMC RNA-seq (Nehar-Belaid et al. 2020)
- GSE134809 IBD ileal biopsies scRNA-seq (Cho et al. 2019, already downloaded)

**Task:** Fine-tune on RA/SLE/IBD cell state labels; evaluate patient stratification AUC on held-out samples vs. Diallo et al. 2025 (93.3% monocyte-focused anti-TNF response signature).

**Blocker:** True response-labeled cohort requires PEAC (EGA EGAS00001001755) DAC approval. GSE89408 provides cell states but not anti-TNF response labels. Initial pilot runs on GSE89408 cell state fine-tuning only; PEAC cohort needed for AUC benchmark.

**Signal:** Does the model learn RA-specific Treg vs. monocyte distinctions that a general scRNA model misses? Key diagnostic: does PTPN22 expression rank higher in Treg vs. monocyte in the fine-tuned vs. base model?

### Layer 2 — Target Prioritization GNN (Deferred to Month 3)

Requires full RA GWAS training run (Ishigaki 2022 GCST90132223, already downloaded) + Open Targets clinical precedence labels as positive training signal. Compute: ~4 GPU-hours. Deferred until Layer 3 and 4 are validated.

### SLE Autoimmune Pilot — Banchereau 2016 as Gold Standard (Added 2026-07-06)

**Why this is the fastest path to demonstrating model adaptation advantage:**

Banchereau et al. *Nature Medicine* 2016 (DOI: 10.1038/nm.4032, PMID: 26974307) is the landmark SLE transcriptomics paper — 158 pediatric SLE patients, 7 IFN gene modules, published patient stratification that predicts flare and organ damage. The data is on GEO (GSE65391). The published expected outputs (IFN module scores, flare-correlated clusters) are the gold standard against which BioMate's outputs can be directly compared.

**What makes this ideal as a pilot benchmark:**

1. Published expected output — IFN module 1 (M1.2) correlates with nephritis; Module 3 (M3.4) with disease activity. BioMate must recover these cluster-to-module assignments.
2. No DAC required — GEO public access.
3. Directly relevant to the Zhi Lab demo — SLE IFN signature stratification is the exact use case.
4. Cross-validates the Layer 1 cell state model — if the fine-tuned Geneformer recovers Banchereau IFN modules better than the base model, adaptation advantage is demonstrated.

**Protocol:**
1. Download GSE65391 (Banchereau 2016, 158 SLE + 20 healthy PBMC, microarray)
2. Run BioMate DESeq2/limma pipeline on SLE vs. healthy comparison
3. Run gene set enrichment on BioMate DE output using the 7 published Banchereau IFN module gene lists
4. Compare: does BioMate's unsupervised DE output recover the published Module 1.2 vs 3.4 distinction?
5. Run Geneformer base model vs. fine-tuned model — which better separates the 3 patient clusters (low/medium/high disease activity)?

**Pass criterion:** BioMate DE output enriches for ≥5 of 7 Banchereau IFN modules (p < 0.05 by GSEA). Demonstrates that BioMate can reproduce a landmark published finding on an independent dataset — proof of biological validity, not just benchmark gaming.

---

## 3. Cross-Domain Multi-Specialty Use Case — Proving Uniqueness

### The Core Claim

*"No published system does workflow orchestration + QC judgment + IND generation across 5+ scientific domains in one session. A CRO charges \$1.5–3M and 4–6 months for this package. BioMate generates it in one session."*

### The "RA from Scratch" Canonical Demo

**⚠️ Demo integrity requirement (2026-07-06):** This demo must run through BioMate's production chat interface — not assembled from separate validation scripts. Each step must be triggered by a real BioMate routing decision, execute a real workflow on AWS Batch, and return real output to the user. A demo assembled from cached script outputs is not acceptable and would not survive a faculty question like "can I try it myself?"

**Current status:** Steps 1–6 are individually validated. They have NOT been run as a connected single BioMate session. Test 1-H (scGWAS cell-type) ran on SCZ smoke data, not RA GWAS. The full connected demo is the remaining prep work before the Zhao Lab call.

**What needs to happen before this demo is ready:**
1. Test 1-H upgrade: run scGWAS on Ishigaki 2022 RA GWAS → confirm PTPN22 → Treg (in progress)
2. Stage a single BioMate chat session on dev that routes the full prompt through all 6 steps with live AWS Batch execution
3. Capture real screenshots of each workflow card completing in the BioMate UI

Single user prompt → 6-step cross-domain chain:

```
"I'm studying rheumatoid arthritis. Find me a druggable target, 
predict ADMET for a compound against it, and generate an IND package."
```

| Step | Specialty | BioMate action | Evidence | Ready for live demo? |
|------|-----------|---------------|----------|----------------------|
| 1 | Statistical genetics | coloc/SMR on GWAS → PTPN22/TYK2/IL6R ranked | Test 1-A PASS | ✓ (runs on AWS Batch) |
| 2 | Single-cell immunology | scGWAS → Treg cell type for PTPN22 | Test 1-H — SCZ smoke only | ✗ RA GWAS upgrade in progress |
| 3 | Structural biology | PDB 6NZR → TYK2 JH2 binding pocket | Test 5-A PASS | ✓ |
| 4 | Cheminformatics | ADMET ensemble → hERG 80µM, PPBR 86.9% | Test 8-A PASS | ✓ |
| 5 | Clinical pharmacology | PBPK → synovial Cmax 220 ng/mL | Test 5-A PASS | ✓ |
| 6 | Regulatory science | §2.6.1 narrative + DOCX download | Test 4-A PASS | ✓ |

**No competitor covers all 6 steps:**

| Competitor | What they do | What they miss |
|-----------|-------------|---------------|
| FutureHouse | Hypothesis generation, single-domain analysis | Cannot chain GWAS → ADMET → PBPK; no IND doc |
| Seven Bridges | CWL/WDL workflow infrastructure | No AI interpretation, no routing, no narrative generation |
| DNAnexus | WDL workflow infrastructure | Same gap as Seven Bridges |
| Schrödinger | Small-molecule physics + structure | Requires expert-supplied structure; cannot start from "RA" |
| BenchSci | Literature mining for reagent selection | No computational execution; no GWAS/scRNA/PBPK |

**The differentiating layer:** BioMate is the only platform that bridges the gap between a wet-lab immunologist's natural-language question and a regulatory-ready output — without the researcher needing to know which tool to use, how to configure it, or how to interpret the output.

### Three Faculty-Audience Demos (Tailored)

#### Zhao Lab (GWAS / computational genetics audience)
**Prompt:** "I have RA GWAS summary statistics. Which immune cell type carries the PTPN22 risk? Is it a druggable target?"

**BioMate chain:**
1. GWAS locus prioritization → PTPN22 rs2476601, p=1.2×10⁻¹⁵²
2. scGWAS cell-type assignment → Treg / naïve CD4+ T cells (not monocytes)
3. eQTL colocalization → DICE immune panel, PP4 = 0.87 in Treg
4. Druggability scoring → ChEMBL 0 approved drugs (early-stage target), OpenTargets tractability "small molecule" tier
5. Output: ranked target scorecard + suggested compound classes

**Why it's unique:** Zhao Lab can run GWAS; they cannot run scGWAS → eQTL → druggability → clinical compound suggestion in the same session without BioMate.

#### Zhi Lab (autoimmune clinician / translational audience)
**Prompt:** "My SLE patients have high IFN gene signature scores. What drug addresses this and what would the clinical trial look like?"

**BioMate chain:**
1. IFN signature → routes to anifrolumab (IFNAR1 antagonist)
2. ADMET → MW 148 kDa (expected, mAb class), BBB non-penetrant (correct), not hERG-liable
3. Endpoint recommendation → BICLA at Week 52 (TULIP-2 precedent)
4. §2.6.1 narrative → IFNAR1 mechanism, Type I IFN blockade, TULIP-2 47% vs 31% BICLA, IFN gene signature −88%
5. DOCX download → pre-IND format

**Why it's unique:** A clinician describes a patient phenotype in natural language and receives an IND-ready document. No other platform makes this accessible to a non-computational researcher.

#### Drug Discovery Faculty (novel target / early-stage)
**Prompt:** "TL1A is an IBD GWAS hit. Can BioMate take me from GWAS to a fragment screen to an IND package?"

**BioMate chain:**
1. IBD GWAS → TNFSF15 (TL1A) locus top-10 by significance
2. eQTL → intestinal macrophage primary cell type (DICE)
3. PDB pocket analysis → Leu77/Arg79/Gln81 hotspot (2RE9)
4. AutoDock Vina virtual screen → ≥5 hits MW<350 Da, ΔG < −6 kcal/mol
5. ADMET → hERG + hepatotox + solubility filters
6. §2.6.1 narrative + power calculation → IND-ready output

**Why it's unique:** An early-stage target goes from GWAS locus to IND package in one session. This is Test 5-B (not yet run) + Test 4-A integrated. The closest CRO workflow costs $500K–$1.5M and 3–4 months for just the PPI + ADMET steps.

### Validation Coverage of Uniqueness Claims

| Uniqueness claim | Validation test | Status |
|-----------------|----------------|--------|
| Multi-domain chain (GWAS→scRNA→ADMET→PBPK) | Test 7-A | PASS |
| AI interpretation vs. Seven Bridges/DNAnexus | Test 7-B | PASS |
| Target-agnostic vs. Schrödinger | Test 7-C | PASS (literature-based) |
| IND narrative generation | Tests 4-A, 4-B | PASS |
| Endpoint recommendation accuracy | Test 4-B | PASS (75% exact) |
| Citation verifier (no hallucination) | Test 8-B | PASS |

**Note on Schrödinger comparison (2026-07-05):** Direct software access is not available (commercial license required). Test 7-C was redesigned as a published-evidence comparison — Schrödinger's required inputs documented from ≥3 published primary sources (Wang et al. *JCTC* 2015; Harder et al. *JCTC* 2016; Friesner et al. *JMC* 2004). BioMate's capability documented from existing passing tests (1-A, 5-A, 7-A, 4-A). PASS verdict is based on the structural asymmetry: Schrödinger's starting point (known target + scaffold) is BioMate's output.

**Faculty call framing for Schrödinger:** Position as complementary, not competitive — "BioMate identifies what to design; Schrödinger refines how to design it." This lands better with a computational chemistry audience and avoids a direct-displacement argument we cannot back with a live comparison.

---

## Action Items

| Priority | Item | Owner | Timeline |
|----------|------|-------|---------|
| 1 | Layer 3 LoRA training data assembly (50 NDA labels) | LLM team | Week 1 |
| 2 | Layer 4 routing annotation (200 prompt-workflow pairs) | Eng | Week 1 |
| 3 | Reference cache module (`reference_cache.py`) | Backend | Week 2 |
| 4 | Tiered routing in `galaxy-assistant.ts` | Frontend/Backend | Week 2 |
| 5 | PEAC DAC access application (Layer 1 blocker) | PI | Month 1 |
| 6 | DGX Spark Layer 3 training run | LLM team | Week 3 |
| 7 | Layer 3 benchmark vs. Test 4-B baseline | Validation | Week 4 |
