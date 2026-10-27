# Workflow UI run-data (for Claude Design)

**Date:** 2026-10-26. **Answers:** `WORKFLOW_UI_DATA_REQUEST.md` — real run data to fill the
results / outputs / record / report screens for 8 workflows, plus the flow-cytometry default gating
and per-workflow end-to-end validation status.

**Design's rule honored:** every number below is cited to the on-disk artifact it came from. Where no
real run artifact exists, it is marked **NEEDS A RUN** — nothing is invented. Gaps are listed per
workflow and collected at the end so you know exactly what to leave unlabeled / pending.

Canonical real-artifact directory for the tutorial runs:
`reference/claude_design/tutorials/assets/live/_raw/` (use the `tutorials/` copy — some `*_v2*`
copies of the DESeq2 files are placeholder-templated with the literal value `"n"`; do not use those).

---

## 0. Two discrepancies to resolve before you show these screens

1. **Flow-cytometry default gating is NOT the debris→singlets→CD3→CD4/CD8 cascade.** The real
   workflow default (`analyze_flow_cytometry_immunophenotyping`, DB id 10612) is a **single scatter
   gate**: `lymphocytes = FSC-A between 50,000–150,000 AND SSC-A between 10,000–80,000`
   (`backend/biomni_workflows/nextflow_nfcore/subworkflows/cell_biology/analyze_flow_cytometry_immunophenotyping/main.nf:15-16`).
   The CD3+/CD4+/CD8+ cascade and its percentages in the walkthrough are **illustrative placeholders**
   (`np.random.uniform` demo branch, lines 128-131), not the shipped default. → Either show the real
   single-gate default, or label the cascade as an example strategy the user supplies.

2. **`survival_analysis_km` is a trial-DESIGN workflow, not a data KM/Cox analysis.** It computes
   power / sample-size / O'Brien-Fleming boundaries from assumptions (median, HR) and emits
   `km_curves.csv`, `sample_size.json`, `power_table.csv`, `trial_design_report.json` — it does **not**
   produce log-rank p, hazard ratios, or `cox.zph`. The KM/Cox statistics you asked for come from a
   **different** workflow (Bioconductor `survival`, the `lung` dataset). See §S4.

---

## 1. End-to-end validation status (all 8)

| Workflow | Validated E2E? | Evidence |
|---|---|---|
| S1 NCA (`nca_pknca`) | **Yes** | `docs/20260708_REAL_WORKFLOW_EXEC_FAILURES.md` — ran to `succeeded`, all 3 steps, real PKNCA 0.12.1 output on S3 |
| S2 PBPK (`pbpk_simulation`) | **Yes** | `docs/20260418_DRUG_DEV_BATCH_TEST_RESULTS.json` — AWS Batch `succeeded`, run_id `3f4f61ee-9370-4a70-9401-9e7967c522b5` |
| S4 survival (`survival_analysis_km`) | **Yes** (trial-design) | `docs/20260507_WORKFLOW_PRICING_TABLE.md:302-310` — 4/4 Batch steps, 55.5 s |
| qPCR ΔΔCq (`NormqPCR`) | **Yes** | DB `real_exec_status='ok'` (id 14339, provisional) |
| M2 DE (`DESeq2`) | **Yes** | DB `ok` on ids 12966/12967/12968/13161 (real_exec_at 2026-06-09); bare `deseq2` id 11253 is `exec_error` |
| M3 accession routing | **Yes** (capability/live) | `docs/20261005_ACCESSION_TO_WORKFLOW_CAPABILITY.md` — live 2026-10-05; some sub-chains spec-only |
| BOIN (`clinical_trial_simulation`) | **Yes** | `docs/20260507_WORKFLOW_PRICING_TABLE.md:266` + 24/24-passing set |
| Cross-domain routing | **Yes** (benchmark) | `evaluation/datasets/public_export/leaderboard.csv` routing cols + result JSONLs |

> **Caveat for the design team:** for the four drug-dev workflows (NCA, PBPK, survival_KM, BOIN) the
> DB `real_exec_status` column is `None` — it was never back-filled. The real-Batch evidence is in the
> dated docs above. Trusting the DB column alone would wrongly read them as "not validated."

---

## 2. Per-workflow data

### S1 — NCA (`nca_pknca`) — PARTIAL (full table on S3, not committed)
**Real run** (`docs/20260708_REAL_WORKFLOW_EXEC_FAILURES.md`, status `succeeded`, 3 steps): PKNCA
0.12.1, **6 subjects, single oral dose**; reported **t½ 4.64 h**, **Cmax ≈ 1926**. Output CSV schema
(`…/nca_pknca/main.nf:352`): `subject_id, AUClast, AUCinf, Cmax, Tmax, t_half, CL_F, Vd_F, dose, route`.
**Extrapolated-fraction gate (criterion):** AUC-extrapolated % ≤ 20 (FDA default; 30 early-discovery,
15 NDA/BLA) — `main.nf:328`, `qc_evaluator.py:73`.
- **NEEDS A RUN / S3 fetch:** the per-subject rows (AUClast/AUCinf/Tmax/CL_F/Vd_F) and `nca_summary.json`
  and the measured AUC-extrap value are on S3, not committed; `results/nca_pknca/` locally is empty.

### S2 — PBPK (`pbpk_simulation`) — PARTIAL
**Real per-compound Cmax predictions (15 compounds)** —
`evaluation/datasets/public_export/results/biomate_product/pbpk_benchmark_sameitem.jsonl` (predicted
Cmax µM): Aspirin 24.25 · Caffeine 13.68 · Ibuprofen 28.59 · Metformin 69.62 · Warfarin 0.574 ·
Midazolam 1.92 · Verapamil 3.60 · Atorvastatin 2.02 · Sildenafil 3.88 · Propranolol 3.45 · Diazepam
0.608 · Ketoconazole 5.26 · Theophylline 27.26 · Loratadine 0.311 · Clozapine 12.77. (3/15 within 2-fold;
analysis `docs/20260827_BIOMATE_PBPK_SAME_ITEM_RESULT.md`.)
**Four QC gates — real run** `research_repos/flagship_paper/data/e4_logs/biomate/e4-pbpk-001.json`
(overall GOLD, pass): `auc_fold_error` measured **1.4** (thr 2.0, within 2-fold FDA 2018) ·
`mass_balance` measured **0.02** (thr 0.05, recovery err) · `tmax_fraction` measured **0.45** (thr 0.8) ·
4th gate `cl_min` (CL ≥ 0.01 L/h) — **measured value NEEDS A RUN** (not in the e4 log). A real FAIL
example: `e4-pbpk-002.json` (mass_balance 0.12 halt, tmax_fraction 0.92 halt).
**Aspirin defaults** (`…/pbpk_simulation/main.nf`): CLint `45` µL/min/mg (l.32); fu_plasma literal
`0.05` (l.30) but **auto-estimated from logP → ≈0.37** when left at default (l.126-134); renal CL `5`
mL/min (l.33).
- **NEEDS A RUN:** a single complete parameter set (Cmax+AUC+Tmax+t½+CL+Vss+F together) — only Cmax
  exists per-compound; AUC/Tmax/CL/Vss/F are produced by `pbpk_simulation` (`pk_profile.csv` +
  `nca_parameters.json`) but no instance is committed. (Biologic alt, different workflow
  `fcrn_antibody_pk`, `data/validation/results/test1f/test1f_summary.json`: t½ 21 d, CL 0.18 mL/h/kg,
  Vd 0.07 L/kg, Cmax 190.48 µg/mL, AUC_inf 138501.5 — use only if a biologic example is wanted.)

### S4 — Survival — NEEDS A RUN (and workflow-identity fix, see §0.2)
**Column mapping (real, from the Bioconductor `survival` workflow def)**
`…/subworkflows/bioconductor/survival/_interpretation.json`: KM `survfit(Surv(time, status) ~ sex,
data = lung)`; Cox `coxph(Surv(time, status) ~ age + sex + ph.ecog, data = lung)`; PH test
`cox.zph(fit)`. So time→`time`, event→`status`, group→`sex`, covariates→`age + sex + ph.ecog`, dataset
`lung`.
- **NEEDS A RUN:** summary-table rows, median survival per group, log-rank p, HR + CI, and `cox.zph`
  are **not** committed anywhere. (The s4 walkthrough's "HR 0.62 [0.44,0.88] / log-rank p 0.004 /
  median ≈ 30 mo" are design-mockup placeholders — do not cite as real.) I can run the `survival`
  workflow on the `lung` dataset to produce all of these as real values — say the word.

### qPCR ΔΔCq (`NormqPCR`) — REAL ✓
**Output files** (`…/assets/live/_raw/`): `qpcr_ddCq_single_paired.csv` ·
`qpcr_ddCq_multiple.csv` (with 2^-ddCt min/max CIs) · `qpcr_relative_expression_plot.png/.pdf`.
**Fold-change (= `2^-ddCt`; ΔΔCq = −log2 of it), verbatim rows** (treated vs control):
Actb = **1.000** (reference/normalizer) · Ccl2 **7.01** (strong up) · Ccr9 **6.24** · Ccl7 **2.35** ·
Ccl3 **2.30** · Ccl5 **1.77** · Alpl **0.823** · Agtrl1 **0.670** · B2m **0.413** · Ccl11 **0.145** ·
Adipoq **0.136** · Ccl24 **0.0351** (strong down). (Some rows NA, e.g. Bdnf/Ccl28/Ccr3.)
With CIs (`qpcr_ddCq_multiple.csv`): Ccl2 7.47 [4.73–11.78] · Adipoq 0.151 [0.127–0.179] · Ccl24
0.037 [0.024–0.058].
**Reference gene:** Actb (Actb.Rn00667869_m1), normalizer (2^-ddCt = 1.000). Stability check is
**qualitative** ("reference looks flat across conditions").
- **NEEDS A RUN:** a numeric geNorm/NormFinder M-value stability score (not emitted on disk).

### M2 — DE (`DESeq2`, GSE52778) — REAL ✓
**Output files** (`…/assets/live/_raw/`): `deseq_results_top200.csv` ·
`deseq_dex_vs_untreated_volcano.png/.pdf` · `deseq_dex_vs_untreated_PCA.png/.pdf` ·
`deseq_qc_metrics.json` (run-quality report).
**Run-quality report (verbatim, `deseq_qc_metrics.json`):** process `DESEQ2_DIFFERENTIAL_ANALYSIS`,
domain transcriptomics, **n_genes_tested 34371**, **n_significant 1242**, pval_cutoff 0.05,
fc_cutoff 2, gate `deseq2_differential_expression` passes:true
("1242 genes significant at padj<0.05, |FC|>=2"), harness `0.3.0-deseq2-val`.
**Top rows (gene / log2FC / padj):** ENSG00000152583.12 +4.636 1.75e-116 · ENSG00000179094.15 +3.192
7.65e-54 · ENSG00000173838.11 +4.015 1.44e-49 · ENSG00000179593.15 +16.558 6.96e-49 ·
ENSG00000125148.6 +2.180 3.35e-47 · ENSG00000120129.5 +2.947 3.35e-47 · ENSG00000148175.12 +1.419
2.31e-46 · ENSG00000134686.18 +1.380 4.39e-46. **Top down:** ENSG00000196517.11 −2.195 1.44e-40 ·
ENSG00000178695.5 −2.510 1.97e-38 · ENSG00000145777.14 −2.837 4.21e-31.
- **NEEDS A RUN:** the up-vs-down split of the 1,242 (only the total is on disk; top-200 CSV can't
  recompute it). Independent live Batch DESeq2 proof exists but on a different dataset (GSE227835,
  run_id `4dbcc0cf-…`, `docs/20261006_REAL_USECASE_E2E_RESULTS.md`).

### M3 — Accession routing — REAL ✓ (routing); fetch names need a run
Source: `docs/20261005_ACCESSION_TO_WORKFLOW_CAPABILITY.md` (live capture 2026-10-05) +
`evaluation/datasets/public_export/accession_routing/`.
**Resolve GSE52778:** GEO series → **Geo Data Connector (#10672)**, param `accession`; modality
`bulk_rnaseq`; organism human, platform GPL11154, archive GEO.
**Resolve an SRR:** SRR1039508 → **nf-core/fetchngs (#12704)**, param `input` (SRA run). (Benchmark also:
SRR1278968→bulk_rnaseq, SRR8599150→scrna_seq.)
**Three routed workflows (filled params), verbatim:** (1) "GSE2034 microarray DE good vs poor" →
Affymetrix microarray DE → `study_type=affy`; (2) "GSE52778 bulk RNA-seq DE, dex vs untreated" →
nf-core/rnaseq → differentialabundance(DESeq2) → GSEA → `genome=GRCh38`; (3) "GSE52778 GSEA" →
fgsea + clusterProfiler (GO/KEGG/Reactome) → `species=Homo sapiens, organism=hsa`.
**Fetched outputs (type):** GEO → series matrix (GEOquery); SRA → raw FASTQ + samplesheet (fetchngs).
- **NEEDS A RUN:** concrete fetched filenames (actual `.fastq.gz`/samplesheet names). Also: the
  SRA→fetchngs→Batch end-to-end leg is a documented known-broken path (routing works; full Batch run
  unconfirmed).

### BOIN (`clinical_trial_simulation`) — REAL ✓ (design); per-cohort DLTs need a run
**Example trial CT-001** (`evaluation/datasets/boin_benchmark/cases.yaml`):
dose levels **[10, 20, 40, 80, 150, 300] mg**; target DLT rate φ **0.25**; true DLT rate per level
[0.02, 0.05, 0.10, 0.20, 0.28, 0.40]; **selected MTD = level 5 = 150 mg** (model prediction "150"
matches, `…/results/sft/boin_benchmark.jsonl`). PK: CL 10 L/h, Vd 70 L, ka 1.5/h; Emax (0.9 / EC50
2000 nM / E0 0.02); 1000 sims.
**Cohort size & thresholds** (`…/clinical_trial_simulation/main.nf`): cohort **3**, max 30; BOIN
boundaries (Liu & Yuan 2015) λ_e = φ−0.1φ = **0.225**, λ_d = φ+0.1(1−φ) = **0.325**; rule: DLT/n ≤ λ_e
escalate, ≥ λ_d de-escalate, else stay.
- **NEEDS A RUN:** observed per-cohort DLT counts (generated stochastically at runtime, not stored). I
  can run one simulation to produce a real cohort-by-cohort escalation trace — say the word.

### Cross-domain routing — REAL ✓ (request + answer); scored top-3 needs a run
**Example request** (`evaluation/datasets/cross_domain_routing/queries.yaml`, id rna_003):
"Process 30 bulk RNA-seq samples from a clinical trial and produce a gene counts matrix" → domain
`rna_seq`, correct `nf-core/rnaseq` (disqualified: scrnaseq, differentialabundance). Real routed
prediction = **nf-core/rnaseq** (`…/results/biomate_dev/cross_domain_routing_c2ir.jsonl`).
Aggregate routing accuracy (`…/leaderboard.csv`): BioMate engine-free C2 **0.965**; frontier LLMs jump
~+35–40 pp with the catalog (Opus 5 0.615 bare → 0.990 harness).
- **NEEDS A RUN:** a scored **top-3 candidate list with similarity scores** is not persisted (the
  benchmark stores a single `{id, prediction}`). I can capture BioMate's live retrieval layer
  (`UnifiedWorkflowSearch`) on one request to produce a real ranked top-3 — say the word.

---

## 3. Gaps that need a fresh run (collected)
| # | Workflow | Missing (real value) | Cheap to run? |
|---|---|---|---|
| 1 | NCA | per-subject table + summary JSON + measured AUC-extrap % (on S3) | S3 fetch or re-run |
| 2 | PBPK | one complete param set (Cmax+AUC+Tmax+t½+CL+Vss+F); `cl_min` gate value | Batch run (costs) |
| 3 | Survival | median/group, log-rank p, HR+CI, cox.zph (run Bioconductor `survival` on `lung`) | **yes, cheap** |
| 4 | qPCR | numeric geNorm/NormFinder stability M-value | yes |
| 5 | M2 DESeq2 | up-vs-down split of the 1,242 | yes (recompute from full table) |
| 6 | M3 | concrete fetched filenames | needs fetchngs run |
| 7 | BOIN | per-cohort observed DLT trace | **yes, cheap** |
| 8 | Routing | scored top-3 with similarity scores | **yes, cheap** (retrieval capture) |

**Offer:** items 3, 7, 8 (and 4, 5) are cheap/local and I can fill them with real values on request;
items 1, 2, 6 need an S3 fetch or a paid Batch run — confirm before I launch those.

---

## 4. Fresh run results (2026-10-26) — real AWS Batch runs

### item 8 — Cross-domain routing: REAL top-3 with scores ✓
Live BioMate workflow search, query *"Process 30 bulk RNA-seq samples from a clinical trial and
produce a gene counts matrix"*:
| rank | workflow | domain | score |
|---|---|---|---|
| 1 | `differentialregulation_bulk_rna_seq_pipeline` | transcriptomics | 56 |
| 2 | `nf-core/rnaseq` | transcriptomics | 52 |
| 3 | `decoupler_pathway_activity_bulk_rnaseq` | transcriptomics | 49 |
(4th `nf-core/differentialabundance` 48, 5th `scshapes` 48.) Real live scores. Note the router edges
differential-regulation above nf-core/rnaseq for this phrasing.

### item 7 — BOIN: REAL run ✓ (run_id `c93845cd…`, clinical_trial_simulation, design=BOIN, 1000 sims)
**Thresholds** (`BOIN_decision_table.json`): target DLT φ **0.25**, λ_escalate **0.225**, λ_deescalate
**0.325**, rule "DLT/n ≤ 0.225 escalate · ≥ 0.325 de-escalate · else stay".
**Dose-escalation table** (`dose_escalation_results.csv`, real):
| level | dose mg | true DLT rate | Cmax nM (median) | P(selected) % | pred. efficacy |
|---|---|---|---|---|---|
| 1 | 10 | 0.138 | 297.4 | 64.6 | 0.233 |
| 2 | 20 | 0.223 | 594.8 | 29.0 | 0.348 |
| 3 | 40 | 0.362 | 1189.7 | 5.9 | 0.485 |
| 4 | 80 | 0.510 | 2379.4 | 0.4 | 0.613 |
| 5 | 150 | 0.644 | 4461.4 | 0.1 | 0.704 |
| 6 | 300 | 0.753 | 8922.7 | 0.0 | 0.769 |
| 7 | 400 | 0.788 | 11897.0 | 0.0 | 0.788 |
**Operating characteristics** (`operating_characteristics.json`): P(correct MTD) **0.29**, P(underdose)
**0.646**, P(overdose) **0.064**, **true MTD = 20 mg**, 1000 sims. **Recommended Phase-II dose = 40 mg QD**
(RR 47.9%, P-success 1.0).
**Design note for the deck:** this workflow emits **1000-simulation operating characteristics** (per-dose
true-DLT + P-selected), **not** a single cohort-by-cohort DLT escalation trace. If the deck wants a
"cohort 1 → 0/3 DLT → escalate" style trace, that's a per-trial realization the workflow doesn't export;
use the OC table + thresholds above.

### item 3 — Survival (KM/Cox): REAL run ✓ (runs `e8ecd88d` KM + `1724a679` Cox)
**Data:** ImmPort **SDY2195 (ALE06)**, 102 patients, treatment arm **Withdrawal (52) vs Maintenance
(50)**, 31 events; input `patient_clinical_data.csv` columns mapped `time=time_days, status=event,
group=arm`. (The data KM/Cox workflows require an uploaded clinical table — they do NOT auto-run on R's
`lung`; the input filename must be exactly `patient_clinical_data.csv`.)
**Kaplan-Meier** (`survival_summary_table.csv`, real `survfit`): final survival **Maintenance 0.77**
(@393 d), **Withdrawal 0.60** (@434 d) — withdrawal arm worse, as expected. **Median survival = Not
Reached** in either arm (event rate 31/102 keeps both curves above 0.5).
**Cox PH** (`cox_hazard_ratios.csv` / `.command.out`, real `coxph(Surv(time,status) ~ group)`):
**HR Withdrawal vs Maintenance = 1.83 [95% CI 0.88–3.83]**, coef 0.607, z 1.62, p **0.106**; likelihood-
ratio & **score (log-rank) test p = 0.1** → arm difference not significant at 0.05; concordance 0.57.
**cox.zph** (`cox_zph_test.csv`): group χ² 0.569, df 1, **p = 0.45**; GLOBAL p 0.45 → **proportional-
hazards assumption holds**. Outputs: `kaplan_meier_curves.pdf`, `survival_summary_table.csv`,
`cox_hazard_ratios.csv`, `cox_coefficients.csv`, `cox_zph_test.csv`, `cox_zph_plots.pdf`.
**Design note:** the KM workflow emits the `survfit` summary + curve PDF but **not** a separate log-rank
p-value or printed median — use the Cox **score/log-rank p = 0.1** for significance and "Not Reached"
for the medians. Swap the dataset for a public cohort (e.g. `lung`) before publishing if the ImmPort
source isn't wanted on-screen.

### item 5 — DESeq2 up/down split: PARTIAL — real top-200 split; full-1242 not reproducible as the displayed number
**Delivered (real):** of the on-disk **top-200** DESeq2 rows (`deseq_results_top200.csv`), the split is
**137 up (log2FC>0) / 63 down**.
**Why not the full 1,242 split of the displayed headline:** only the top-200 is saved on disk, and the
original full results (all 34,371 genes) aren't committed. I **did** attempt a fresh DESeq2 run on the
committed airway/GSE52778 counts (`airway_counts.csv`, 63,677 genes × 8 SRR samples, re-labelled
dex vs untrt): runs `7a8c013c` → `609a7f18` → `…`. Two things make this a weak substitute:
(1) a fresh run yields **self-consistent but different totals** (its own N-tested / M-significant), so its
split would **not** correspond to the "34,371 / 1,242" number Design currently shows; and
(2) the runnable `validation_deseq2_raw_counts` requires **two separate declared inputs** (`cts` **and**
`coldata`) whose keys/format only surface by crashing — the same params-vs-inputs friction documented in
`docs/20261026_PARAMS_VS_INPUTS_GAP.md`. **Recommendation:** either keep 34,371/1,242 with the top-200
split as the shown direction (mostly up), or re-run DESeq2 end-to-end on airway and show that run's own
totals **and** split together (coherent, but new numbers). Say which and I'll finish the run.

### item 4 — qPCR geNorm stability: BLOCKED on input (raw Ct matrix not on disk)
Only the ddCq **outputs** (`qpcr_ddCq_*.csv`) are committed, not the raw per-gene/per-sample **Ct**
matrix that NormqPCR's geNorm needs. Producing a numeric geNorm/NormFinder M-value requires sourcing or
re-deriving the Ct input, then running the NormqPCR workflow.
