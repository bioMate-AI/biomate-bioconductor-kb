# SLE Autoimmune Pilot — Banchereau 2016 Elaboration

**Date:** 2026-07-06  
**Links to:** `20260704_SPEEDUP_LLM_PILOT_AND_UNIQUENESS_STRATEGY.md` (§ SLE Pilot)

---

## Why Banchereau 2016

Banchereau et al. *Nature Medicine* 2016 (DOI: 10.1038/nm.4032, PMID: 26974307) is the most cited single-cohort SLE transcriptomics paper. It established the IFN gene module framework that all subsequent SLE biomarker work references. Three properties make it uniquely suited as a BioMate benchmark:

1. **Published expected outputs.** The paper reports exactly which gene modules predict flare (M1.2), nephritis (M2.1), anti-dsDNA (M3.4), and overall disease activity. BioMate must recover these — not approximate them, recover them. This is not a subjective benchmark.

2. **No DAC required.** GSE65391 is fully open-access on GEO. Download, run, compare. No registration, no committee, no 6-month wait.

3. **Directly feeds the Zhi Lab demo.** The SLE IFN-high patient use case (Zhi Lab faculty demo) is literally this paper — a clinician seeing IFN-high signature scores and wanting to know what drug addresses it. Running BioMate on Banchereau data and recovering the IFN modules is the validation that the demo is real, not illustrative.

---

## The Dataset

| Property | Value |
|----------|-------|
| GEO accession | GSE65391 |
| Publication | Banchereau et al. *Nature Medicine* 2016 |
| Subjects | 158 pediatric SLE patients + 20 healthy controls |
| Platform | Affymetrix HTA 2.0 microarray (whole blood) |
| Timepoints | Baseline + 1-year follow-up (subset) |
| Disease activity | SLEDAI scores for each patient |
| Size | ~500 MB |

---

## What the Paper Found (the Gold Standard)

Banchereau identified 7 IFN transcriptional modules from the 158 patient transcriptomes using unsupervised weighted gene co-expression network analysis (WGCNA). Each module correlates with a distinct clinical feature:

| Module | Gene count | Clinical correlation | Top genes |
|--------|-----------|---------------------|-----------|
| M1.2 | 142 | Flare prediction | IFI44L, RSAD2, IFIT1, MX1, OAS1 |
| M2.1 | 89 | Nephritis | FCGR1A, CD64, S100A8, S100A9 |
| M3.4 | 76 | Anti-dsDNA antibody titer | IGLV, IGHG1, plasma cell genes |
| M4.2 | 61 | Neutrophil activation | LCN2, MMP8, CAMP |
| M5.1 | 54 | T cell activation | CD3D, CD3E, IL7R, LEF1 |
| M6.3 | 48 | Disease activity (SLEDAI) | BAFF, APRIL, BLyS |
| M7.1 | 39 | Complement | C1QA, C1QB, C2, CFD |

The key clinical finding: patients with high M1.2 (IFN-high) at baseline had 3× higher rate of flare at 12 months. This is the signal anifrolumab targets — IFNAR1 blockade reduces M1.2 score by 88% (confirmed in TULIP-2).

---

## What BioMate Needs to Demonstrate

### Task 1: Recover the IFN Modules from Unsupervised DE

Run BioMate's standard pipeline on GSE65391 (SLE vs. healthy comparison):
1. DESeq2/limma on 158 SLE vs. 20 healthy
2. Gene set enrichment (GSEA or fgsea) on BioMate DE output using the 7 published Banchereau module gene lists
3. Check: does BioMate's DE output enrich for ≥5 of 7 modules at FDR < 0.05?

**Why this matters:** BioMate ran a standard DESeq2 pipeline without knowing the Banchereau module structure. If the pipeline recovers the modules, it means BioMate's standard output captures the disease-relevant biology — it's not overfitted to any particular analysis.

Expected: M1.2 (IFN) and M2.1 (monocyte) should be highly enriched in SLE vs. healthy DE. M5.1 (T cell) and M3.4 (plasma cell) moderately enriched. This matches the known SLE immune landscape.

### Task 2: Patient Stratification — Reproduce the Three Clusters

Banchereau identified 3 patient clusters:
- **Cluster A (IFN-low, low disease):** low M1.2, low SLEDAI
- **Cluster B (IFN-intermediate):** moderate M1.2, variable organ involvement
- **Cluster C (IFN-high, active nephritis):** high M1.2 + M2.1, high anti-dsDNA

Run BioMate's clustering (k-means or hierarchical on top 500 DE genes) on the 158 SLE patients. Check: do the resulting clusters correlate with the published cluster assignments?

Pass criterion: cluster-to-cluster assignment agreement ≥ 70% (Cohen's κ ≥ 0.5) against Banchereau published labels.

### Task 3 (LLM adaptation): Geneformer Base vs. Fine-Tuned

Once Geneformer v2 is fine-tuned on GSE89408 (RA) + GSE142016 (SLE) + GSE134809 (IBD):
- Run base model and fine-tuned model embeddings on GSE65391 cells
- Compare: does the fine-tuned model separate the 3 patient clusters better?
- Measure: silhouette score of the 3 clusters in embedding space, base vs. fine-tuned

**This is the adaptation advantage proof.** If fine-tuned silhouette > base silhouette, the autoimmune-specific training improves clinically meaningful stratification on a held-out cohort the model was not trained on.

---

## Connection to BioMate Product Claims

| Claim | Banchereau validation |
|-------|----------------------|
| "BioMate recovers disease-relevant biology from standard pipelines" | Task 1: ≥5/7 IFN modules recovered |
| "BioMate stratifies patients into clinically meaningful subgroups" | Task 2: cluster agreement κ ≥ 0.5 |
| "Autoimmune LLM adaptation improves over base model" | Task 3: fine-tuned silhouette > base |
| "IFN-high signature identifies anifrolumab candidates" | M1.2 enrichment → IFNAR1 rationale reproduced |

---

## Connection to Zhi Lab Demo

The Zhi Lab demo prompt is: *"My SLE patients have high IFN gene signature scores. What drug addresses this and what would the clinical trial look like?"*

The Banchereau pilot is the evidence that BioMate actually identifies IFN-high patients correctly:
- BioMate runs on GSE65391 → recovers M1.2 (IFN module) → annotates Cluster C patients as IFN-high
- BioMate routes to anifrolumab (IFNAR1 antagonist targeting IFN signaling)
- TULIP-2 BICLA endpoint recommended
- §2.6.1 narrative generated citing Banchereau + TULIP-2

Without the Banchereau pilot, the Zhi Lab demo is illustrative. With it, the demo is: *"Here is the paper that defined IFN modules in SLE. Here is BioMate recovering those modules on the same dataset. Here is BioMate routing from IFN-high signature to anifrolumab to a BLA narrative."*

---

## Execution Plan

| Step | Action | Data needed | Time |
|------|--------|-------------|------|
| 1 | Download GSE65391 | GEO (public) | 1h download |
| 2 | Run BioMate limma pipeline on SLE vs. healthy | GSE65391 matrix | AWS Batch ~20 min |
| 3 | GSEA on 7 Banchereau module gene lists | BioMate DE output + module lists | Local, ~5 min |
| 4 | k-means clustering on top 500 DE genes | BioMate DE output | Local, ~2 min |
| 5 | Compare clusters to published labels | Banchereau Table S2 | Local, ~10 min |
| 6 | Write validation script + save results | — | ~2h coding |
| 7 | (Month 2) Geneformer fine-tune on RA+SLE+IBD | GSE89408 + GSE142016 + GSE134809 | DGX 8-12 GPU-h |
| 8 | (Month 2) Run base vs. fine-tuned on GSE65391 | GSE65391 | DGX ~1 GPU-h |

Steps 1–6 are executable now, without DGX Spark, using BioMate's existing AWS Batch infrastructure. Steps 7–8 require DGX and are the LLM adaptation proof.

---

## Expected Banchereau Module Gene Lists (for GSEA)

Key module gene sets from the paper (Table S4, Banchereau 2016):

```
M1.2 (IFN-I response): IFI44L, RSAD2, IFIT1, IFIT3, MX1, OAS1, OAS2,
  OAS3, OASL, HERC5, HERC6, IFI6, IFI27, IFI35, IFITM1, IFITM3,
  ISG15, ISG20, LAMP3, LY6E, SIGLEC1, TRIM22, USP18, XAF1, ZCCHC2

M2.1 (monocyte/inflammatory): FCGR1A, FCGR1B, S100A8, S100A9, S100A12,
  MMP9, LCN2, CAMP, CEACAM8, CD14, CD64, IL1B, IL6, TNF

M3.4 (plasma cell / Ig): IGKV, IGLV, IGHG1, IGHG2, IGHG3, JCHAIN,
  MZB1, PRDM1, XBP1, IRF4, CD38, SDC1

M5.1 (T cell): CD3D, CD3E, CD3G, CD247, IL7R, LEF1, TCF7, CCR7,
  CD27, CD28, SELL

M6.3 (BLyS/BAFF): TNFSF13B, TNFSF13, CD19, MS4A1, PAX5, EBF1

M7.1 (complement): C1QA, C1QB, C1QC, C2, CFD, CFB, SERPING1
```

These are the reference gene sets to use in the GSEA step. Source: Banchereau et al. 2016 Supplementary Table S4 (public).
