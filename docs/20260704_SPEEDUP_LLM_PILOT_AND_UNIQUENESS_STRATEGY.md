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

---

## 3. Cross-Domain Multi-Specialty Use Case — Proving Uniqueness

### The Core Claim

*"No published system does workflow orchestration + QC judgment + IND generation across 5+ scientific domains in one session. A CRO charges \$1.5–3M and 4–6 months for this package. BioMate generates it in one session."*

### The "RA from Scratch" Canonical Demo

Single user prompt → 6-step cross-domain chain:

```
"I'm studying rheumatoid arthritis. Find me a druggable target, 
predict ADMET for a compound against it, and generate an IND package."
```

| Step | Specialty | BioMate action | Evidence already run |
|------|-----------|---------------|----------------------|
| 1 | Statistical genetics | coloc/SMR on GWAS → PTPN22/TYK2/IL6R ranked | Test 1-A PASS |
| 2 | Single-cell immunology | scGWAS → Treg cell type for PTPN22 | Test 1-H PASS |
| 3 | Structural biology | PDB 6NZR → TYK2 JH2 binding pocket | Test 5-A PASS |
| 4 | Cheminformatics | ADMET ensemble → hERG 80µM, PPBR 86.9% | Test 8-A PASS |
| 5 | Clinical pharmacology | PBPK → synovial Cmax 220 ng/mL | Test 5-A PASS |
| 6 | Regulatory science | §2.6.1 narrative + DOCX download | Test 4-A PASS |

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
