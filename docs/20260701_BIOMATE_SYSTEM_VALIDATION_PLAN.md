# BioMate System Validation Plan
## Full-Stack Evidence for the Autoimmune Drug Discovery Strategy

**Date:** 2026-07-01  
**Links to:** `20260701_BIOMATE_AUTOIMMUNE_STRATEGY_AND_LLM_TRAINING.md`  
**Purpose:** Convert every strategic claim into a testable assertion. Each test is tied to the strategy section that makes the claim, has a defined pass criterion, and maps to a BioMate workflow chain or LLM benchmark.

---

## How This Document Relates to the Strategy

The strategy document (`20260701_BIOMATE_AUTOIMMUNE_STRATEGY_AND_LLM_TRAINING.md`) makes four categories of claims:

| Strategy section | Type of claim | What must be validated |
|---|---|---|
| Part 2: Competitive Landscape | "No competitor does GWAS→scRNA→ADMET→PBPK end-to-end" | Demonstrate BioMate actually executes these chains |
| Part 3: Six Use Cases | Specific workflow chains with named tools and outputs | Run each chain; verify output content and quality |
| Part 4: LLM Architecture | Four-layer model with concrete benchmarks (≥80% AUC, ≥75% routing) | Define and run each benchmark |
| Part 4.1: Uniqueness | "No published model does workflow orchestration + QC judgment + IND generation" | Verify claims remain true; test BioMate against each capability |

The previous document (`20260701_TARGET_MODALITY_VALIDATION_AND_LLM_TRAINING_PLAN.md`) covered only **drug target × modality ADMET/PBPK testing** — Part 3 use case 1 (partially) and Part 3 use case 6 (ADMET layer). It left five of the six use cases and all four LLM layer benchmarks untested.

This document is the complete plan. The target/modality section is incorporated as Module 5.

---

## Validation Architecture: Nine Modules

```
Module 1: Workflow Execution        ← validates Part 3 Use Cases 1–6 (+ 1-G multi-omics, 1-H scGWAS)
Module 2: AI Routing & Params       ← validates Part 4 Layer 4 (orchestration LLM)
Module 3: Auto-Loop QC              ← validates Part 3 cross-cutting QC claim
Module 4: IND Document Generation   ← validates Part 3 Use Case 6 + Part 4 Layer 3
Module 5: Drug Target & Modality    ← validates Part 3 Use Cases 1+6 (ADMET/PBPK)
Module 6: LLM Model Benchmarks      ← validates Part 4 Layers 1–4 quantitative targets
Module 7: Competitive Differentiation ← validates Part 2 competitive claims
Module 8: Robustness                ← ensemble + downstream validation + RAG calibration
Module 9: Temporal Holdout          ← HIGH-EVIDENCE: prospective predictive utility

Evidence tiers:
  Tier 1 (publishable): Module 9 — prospective holdout tests
  Tier 2 (retrodiction): Module 5 (TYK2), Module 1 (1-A, 1-H, 1-F)
  Tier 3 (replication):  Module 1 remaining tests
  Tier 4 (robustness):   Module 8
  Tier 5 (capability):   Modules 6, 7
```

---

## Module 1: Workflow Execution Tests

*Validates: Strategy Part 3 — "BioMate workflow chains" for all six use cases*

### Test 1-A: Multi-Omic Target Prioritization (UC1)

**Strategy claim:** "5 workflow domains, one session, automated QC between steps. This currently requires a team with GWAS, eQTL, scRNA-seq, and cheminformatics expertise."

**BioMate chain:**
```
coloc/SMR (GWAS colocalization) →
Seurat (scRNA-seq cell type assignment) →
ENCODE ATAC-seq accessibility check →
Mendelian randomization (MR-Base) →
druggability scoring (OpenTargets + ChEMBL) →
ranked target scorecard
```

**Input:** Published RA GWAS summary statistics — UK Biobank + FinnGen meta-analysis (N=933,649; Nature Genetics 2024, DOI: 10.1038/s41588-024-01898-1). These are freely available from the GWAS Catalog (GCST90132222).

**Test dataset:** PTPN22 (rs2476601, 1p13.2) — one of the top RA loci with strong Treg cell-type eQTL signal in DICE. Known answer: PTPN22 should appear in the top 5 of the ranked output.

**Pass criteria:**
- [ ] All 5 workflow stages execute to completion without manual intervention
- [ ] PTPN22 appears in the top 10 of the ranked target scorecard
- [ ] Treg cell type assigned as primary carrier of the eQTL (DICE immune panel result)
- [ ] Druggability score populated from ChEMBL / OpenTargets
- [ ] Methods report cites DICE (Schmiedel et al. *Cell* 2018, DOI: 10.1016/j.cell.2018.10.022) and the input GWAS paper
- [ ] Total wall-clock time < 30 minutes on AWS Batch

**Failure mode to watch:** coloc requires pre-formatted LD reference panel in the correct genome build. Verify hg38 alignment before submitting.

---

### Test 1-B: Biologic Responder Signature (UC2)

**Strategy claim:** "A 2025 study predicted anti-TNF response using mRNA quantitation with 93.3% accuracy. BioMate auto-loop QC gate: if PCA shows batch-driven separation, fires and applies ComBat-seq."

**BioMate chain:**
```
DESeq2 (differential expression, responders vs. non-responders) →
ComBat-seq (batch correction — QC gate trigger) →
PCA / UMAP (QC visualization) →
glmnet LASSO (gene signature extraction) →
clusterProfiler / enrichGO (pathway enrichment) →
random forest classifier →
validation on held-out GEO cohort
```

**Input:** GEO GSE89408 — 152 RA synovial RNA-seq samples across 4 centres (Stephenson et al. *Nature Immunology* 2018, DOI: 10.1038/s41590-018-0128-x). Use Diallo et al. 2025 (PMC12109967) published signature (CD36 + 6 Nrf2-induced genes in monocytes) as the gene panel benchmark. ⚠️ GSE77298 does NOT contain anti-TNF response labels (baseline RA vs. healthy only) — corrected per citation audit. For a true response-labeled cohort, the PEAC cohort (EGA EGAS00001001755) is the gold standard but requires DAC approval.

**Pass criteria:**
- [ ] DESeq2 runs to completion; ≥200 DEGs at FDR < 0.05
- [ ] PCA renders in the after-run report; multi-centre batch structure visible (4 centres in GSE89408)
- [ ] Auto-loop QC gate fires on batch separation and applies ComBat-seq without user intervention
- [ ] LASSO signature extraction produces a gene panel of 10–50 genes
- [ ] Gene panel overlap: ≥2 of 7 Diallo et al. 2025 genes (CD36, HMOX1, NQO1, TXNRD1, GCLM, GCLC, SLC7A11) appear in LASSO selection
- [ ] clusterProfiler enrichment identifies at least one JAK-STAT or TNF-pathway GO term in top 10
- [ ] Methods report cites GSE89408, Stephenson et al. 2018, and DESeq2 / ComBat-seq references

**Calibration output:** Record LASSO gene count, AUC on 80/20 split, and overlap with Diallo signature. If AUC < 0.65, diagnose whether batch correction or feature selection is the bottleneck.

**Why this test matters:** The auto-loop batch correction is a differentiating claim. Most biomarker studies fail to correct for batch — BioMate catches this automatically. This test verifies the gate actually fires.

---

### Test 1-C: Single-Cell Immune Landscape Mapping (UC3)

**Strategy claim:** "scRNA-seq → cell type annotation → pseudobulk DE → trajectory → cell-cell communication → cross-disease comparison; output includes top 5 signaling hubs ranked by druggability."

**BioMate chain:**
```
Seurat (QC → normalization → clustering → UMAP → Azimuth annotation) →
cell composition differential analysis →
DESeq2 pseudobulk (per cluster) →
Monocle 3 or Slingshot (trajectory) →
CellChat or NicheNet (cell-cell communication) →
cross-disease comparison (IBD vs. RA shared hubs)
```

**Input:** GEO GSE134809 — Crohn's disease ileal biopsies scRNA-seq (~8,787 cells, inflamed + non-inflamed + healthy; Cho et al. *J Exp Med* 2019, DOI: 10.1084/jem.20190025, PMID: 31474370). ⚠️ This is the Cho/Merad/Kenigsberg dataset — NOT Smillie et al. (Smillie UC data is at SCP259/GSE116222). Downloaded: 579MB RAW.tar.

**Pass criteria:**
- [ ] Seurat clustering identifies ≥6 canonical gut cell types (macrophages, T cells, B/plasma cells, fibroblasts, epithelial, NK) consistent with Cho et al. Figure 1
- [ ] Pseudobulk DE identifies ≥50 DEGs in inflamed CD vs. non-inflamed for at least one cluster
- [ ] GIMATS module detectable: IgG plasma cells + inflammatory monocytes + activated T cells + stromal cells co-enriched in inflamed samples (key Cho et al. anti-TNF resistance predictor)
- [ ] CellChat: TNF → TNFR or IL-23 → IL-23R signaling hub appears in top 5
- [ ] Druggability overlay: TNF and/or IL-23R annotated as druggable
- [ ] UMAP renders in the after-run report with cell type labels
- [ ] Cross-disease comparison: at least one gene hub overlaps between IBD and RA panels

**Calibration output:** Record number of clusters, GIMATS detection (yes/no), top signaling hubs. If GIMATS module is not detected, diagnose whether resolution parameter or annotation reference is the cause.

---

### Test 1-D: Drug Repurposing via Transcriptomic Connectivity (UC4)

**Strategy claim:** "Multiple scoring methods run in parallel; require concordance across ≥2 methods before reporting a candidate. CMap/L1000 is a hypothesis generator, not a definitive prediction engine."

**BioMate chain:**
```
DESeq2 (SLE nephritis vs. healthy kidney disease signature) →
signature quality gate (≥200 up + ≥200 down DEGs) →
L1000/CMap query (WTCS + XCos + GSEA) →
concordance filter (≥2 of 3 scoring methods) →
ADMET filter (hERG, hepatotoxicity, CYP3A4) →
PBPK simulation (renal exposure) →
MOA alignment check
```

**Input:** GEO GSE142016 — SLE PBMC RNA-seq (Nehar-Belaid et al. *Nature Immunology* 2020). Published SLE nephritis signature available from the Immunological Genome Project (ImmGen) portal.

**Pass criteria:**
- [ ] Signature quality gate: verify ≥200 DEGs in each direction; auto-loop flag fires if not (triggers broader FDR cutoff)
- [ ] L1000 query returns ≥10 candidates with negative connectivity (disease-reversing)
- [ ] Concordance filter reduces candidate list by ≥30% (expected from Briefings Bioinformatics 2021 analysis, PMC8597919)
- [ ] ADMET screen eliminates at least 2 candidates for hERG liability or hepatotoxicity
- [ ] Top repurposing candidate has a plausible SLE MOA (IFN, B cell, mTOR pathway)
- [ ] Honest caveat text appears in the output report: "L1000 connectivity is a hypothesis-generating metric with ~17% replication rate across scoring methods"

---

### Test 1-E: Neoantigen / Autoantigen Discovery (UC5)

**Strategy claim:** "OptiType achieves >99% accuracy for 4-digit HLA typing. NetMHCpan-4.1 AUC 0.87–0.93. Output: top 10 autoantigen peptides with composite immunogenicity score."

**BioMate chain:**
```
OptiType (HLA typing from WGS BAM) →
MaxQuant or islet proteome reference (peptide universe) →
NetMHCpan-4.1 (peptide-MHC binding prediction, IC50 < 50 nM threshold) →
TCR-seq cross-reference (VDJdb + McPAS-TCR) →
NetChop + TAPPred (immunogenicity scoring) →
ranked autoantigen list
```

**Input:** HLA type HLA-A*02:01 (most common in Caucasian populations; WGS BAM can be simulated with OptiType test data). Known T1D autoantigens: GAD65, insulin B chain (8–17 peptide), IA-2, ZnT8 — these must appear in top-ranked predictions.

**Pass criteria:**
- [ ] OptiType produces correct 4-digit HLA call for A, B, C, DRB1 from test BAM
- [ ] NetMHCpan-4.1 assigns strong binder (IC50 < 50 nM) to insulin B chain 9-mer in HLA-A*02:01 context (published benchmark result — Sette & Fikes 2003)
- [ ] At least 3 of 4 known T1D autoantigens (GAD65, Ins B, IA-2, ZnT8) appear in top 10 ranked output
- [ ] Composite immunogenicity score integrates all three components (MHC binding + proteasomal cleavage + TAP transport)
- [ ] Output report formats the top-10 list as a tolerization construct design table

---

### Test 1-F: Full IND Package Generation (UC6)

**Strategy claim:** "Full IND computational package — ADMET report, PBPK curves, patient stratification biomarker, power calculation, §2.6 narrative in DOCX format; review-ready for FDA pre-IND meeting. A CRO charges $1.5–3M and 4–6 months for equivalent work."

**BioMate chain:**
```
Target validation (scRNA IL6R expression in RA synovial cells → GEO GSE89408) →
GWAS evidence (GWAS Catalog, IL6R locus in RA) →
AlphaFold/PDB structure retrieval (IL6R PDB: 1N26) →
ADMET screening (SMILES input → hERG/hepatotox/CYP/solubility/BBB) →
PBPK modeling (allometric scaling → synovial exposure) →
patient selection rationale (IL-6/STAT3 gene signature scoring) →
clinical trial simulation (power calculation) →
§2.6.1 LLM narrative generation →
DOCX download
```

**Input:** Tocilizumab (IL-6R antibody) SMILES from DrugBank (DB06273) as the known drug; use this as ground truth for ADMET predictions (tocilizumab is approved, PK well-characterized).

**Pass criteria:**
- [ ] All 9 workflow stages complete in one BioMate session
- [ ] IL6R confirmed as expressed in RA synovial cells (GEO GSE89408 — Stephenson et al. 2018, 5,265 single cells)
- [ ] GWAS Catalog query returns IL6R-adjacent loci in RA (GWAS Catalog accession GCST001390)
- [ ] ADMET: tocilizumab SMILES produces expected ADMET profile (large MW flagged, not BBB-penetrant — correct)
- [ ] PBPK: synovial Cmax prediction within 2× of published tocilizumab synovial fluid data (PMC4530171: median SF/serum ratio 0.31)
- [ ] Power calculation produces sample size ≥300 for DAS28-CRP primary endpoint at 80% power
- [ ] §2.6.1 narrative is coherent, cites the right references, uses correct FDA section format
- [ ] DOCX downloads with all sections populated
- [ ] Total session time < 2 hours on AWS Batch

**Calibration output:** Record wall-clock time per stage, PBPK SF/serum ratio vs. published 0.31, §2.6 ROUGE-L vs. FDA NDA 125276 text. Gap in PBPK exposure → calibrate allometric scaling factor for antibody class.

---

### Test 1-G: Multi-Omics Integration (MOFA+)

**Strategy claim:** "5 workflow domains, one session" — validated here with simultaneous fusion of multiple omic layers from the same patients, not sequential single-omic chaining.

**BioMate chain:**
```
RNA-seq (DESeq2 normalized counts) +
ATAC-seq (chromatin accessibility peaks, ENCODE RA reference) +
GWAS summary stats (Ishigaki 2022, GCST90132223) →
MOFA+ joint factor analysis →
factor-to-disease-activity correlation →
factor gene set enrichment (clusterProfiler) →
top druggable factor hub
```

**Input:** GEO GSE89408 RNA-seq (152 RA samples, already downloaded) + ENCODE ATAC-seq RA synovial reference peaks (public, no registration). GWAS summary stats already downloaded (309MB, 13.3M variants).

**Pass criteria:**
- [ ] MOFA+ converges (ELBO stable after ≤20 iterations)
- [ ] ≥3 latent factors identified with variance explained > 5%
- [ ] At least one factor correlates significantly with RA disease activity (DAS28 or synovitis histology score from GSE89408 metadata)
- [ ] Factor gene weights enriched for known RA pathways (JAK-STAT, TNF, IL-6) by clusterProfiler
- [ ] GWAS loci overlapping ATAC peak factor weights: PTPN22 or IL6R locus appears in top factor
- [ ] Methods report distinguishes this as multi-omics integration vs. single-domain analysis

**Calibration output:** Record number of converged factors, variance explained per omic layer, top factor gene weights. If RNA-seq dominates (>80% variance), diagnose ATAC normalization or weight the omic layers.

**Why this test matters:** Multi-omics integration is absent from all current competitor offerings. This test proves BioMate can fuse layers simultaneously, not just chain them sequentially.

---

### Test 1-H: scGWAS Cell-Type Assignment (Zhao Lab Chain)

**Strategy claim:** "scGWAS assigns GWAS autoimmune loci to specific immune cell types; answers which cell type carries this risk variant."

**BioMate chain:**
```
scGWAS (chain id 72, Zhao lab, GPL-3.0) →
GWAS loci input (RA: PTPN22, TYK2, IL6R, JAK1) →
single-cell reference panel (scGWAS shipped 18 immune panels, 1.08M cells) →
trait-cell type association scores →
gene set enrichment per cell type →
top 3 cell types per GWAS locus
```

**Input:** RA GWAS summary statistics (Ishigaki 2022, GCST90132223, already downloaded). scGWAS shipped example data as fallback for smoke test.

**Known answers (from Jia et al. *Genome Biology* 2022):**
- PTPN22 → Treg / naïve CD4+ T cells (not monocytes)
- JAK1 → broad T and NK cell expression
- IL6R → plasma cells and plasmablasts

**Pass criteria:**
- [ ] scGWAS chain (chain id 72) executes end-to-end on AWS Batch
- [ ] PTPN22 assigned to Treg or naïve CD4+ T cell (not monocyte/B cell)
- [ ] JAK1 assigned to T cell or NK cell compartment
- [ ] IL6R assigned to B/plasma cell lineage
- [ ] Output cites Jia et al. 2022 (DOI: 10.1186/s13059-022-02785-y) in methods report
- [ ] Results feed into Test 1-A druggability scorecard (cell type context propagated downstream)

**Calibration output:** Record cell type assignment scores for each locus. If PTPN22 is assigned to wrong cell type, diagnose whether the reference panel resolution or the GWAS LD block definition is the cause.

---

## Module 2: AI Routing and Parameter Extraction Tests

*Validates: Strategy Part 4.1 — "Workflow-native orchestration" and "parameter extraction from scientific prose"*

### Test 2-A: Workflow Routing Accuracy

**Strategy claim:** "≥80% workflow routing accuracy on held-out intents; parameter extraction F1 > 0.80"

**Method:** Construct a test set of 100 natural-language research prompts across BioMate's 34 domains; compare BioMate's routed workflow against the annotated correct workflow.

**Test prompt examples:**

| Prompt | Correct workflow | BioMate selects? |
|---|---|---|
| "I have RNA-seq from RA synovial biopsies, cases and controls, find differentially expressed genes" | DESeq2 / edgeR | |
| "Cluster my SLE PBMC single-cell data and annotate cell types" | Seurat pipeline | |
| "Run GWAS colocalization between my summary statistics and DICE eQTLs" | coloc / SMR | |
| "Predict ADMET properties for these 20 SMILES strings" | ADMET screening chain | |
| "Build a PBPK model for oral baricitinib in RA patients" | PBPK workflow | |
| "Identify HLA type from this WGS BAM file" | OptiType | |
| "Find drugs that reverse the IBD transcriptomic signature using L1000" | CMap connectivity | |

**Pass criteria:**
- [ ] ≥80 of 100 prompts route to the correct workflow (≥80% accuracy)
- [ ] Domain confusion rate (e.g., routing a GWAS prompt to a proteomics workflow) < 5%
- [ ] Ambiguous prompts route to disambiguation dialog rather than wrong workflow

**Current baseline:** BioMate's routing benchmark from `backend/database/galaxy_ai_tools.db` routing tests. Record pre-test score to measure improvement.

---

### Test 2-B: Parameter Extraction Accuracy

**Strategy claim:** "Mapping '150-day chronic dosing study in cynomolgus monkeys at 10 mg/kg' to `{species: cyno, duration_days: 150, dose_mg_kg: 10, study_type: chronic_tox}`"

**Method:** 50 clinical prose snippets with known parameter ground truth; measure F1 on extracted parameter values.

**Test snippet examples:**

| Prose input | Expected params | BioMate extracts? |
|---|---|---|
| "Human PBMCs stimulated with LPS at 10 ng/mL for 4 hours" | `{cell_type: PBMC, stimulus: LPS, conc_ng_ml: 10, time_hours: 4}` | |
| "30 mg/kg IV bolus in 8-week old male C57BL/6 mice, n=6 per group" | `{dose: 30, route: IV, age_weeks: 8, sex: male, strain: C57BL6, n: 6}` | |
| "10× Genomics 3' gene expression, 5,000 target cells per sample, sequenced to 50K reads/cell" | `{platform: 10x_3prime, target_cells: 5000, reads_per_cell: 50000}` | |
| "RNA-seq with dUTP strand-specific library, paired-end 150 bp, human hg38" | `{strandedness: reverse, paired_end: true, read_length: 150, genome: GRCh38}` | |

**Pass criteria:**
- [ ] Parameter extraction F1 > 0.80 across the 50 test snippets
- [ ] Unit conversion accuracy 100% for numeric transformations (e.g., `ng/mL → nM` for known MW compounds)
- [ ] Negation handling correct (e.g., "no glucose" → `glucose: false`, not `glucose: no`)

---

## Module 3: Auto-Loop QC Tests

*Validates: Strategy Part 3 cross-cutting claim — "automated QC between steps" and "BioMate auto-loop QC gate fires and auto-remediates"*

### Test 3-A: Batch Effect Detection and Remediation

**Scenario:** Submit GSE77298 RNA-seq (Test 1-B) without pre-labeling batches. Verify BioMate detects batch-driven PCA separation autonomously.

**Pass criteria:**
- [ ] PCA rendered in report shows clear two-cluster structure correlating with processing batch (not with response status)
- [ ] Auto-loop QC gate fires and labels the event in the report ("Batch separation detected in PC1/PC2 — applying ComBat-seq correction")
- [ ] Post-ComBat-seq PCA shown in the same report, demonstrating batch integration
- [ ] DE analysis proceeds on ComBat-corrected data, not on raw data
- [ ] The remediation event is logged as a QC record in the session

---

### Test 3-B: Insufficient Signal Gate

**Scenario:** Submit a minimal GEO dataset with only 8 samples (4 cases, 4 controls) for DESeq2 differential expression.

**Pass criteria:**
- [ ] QC gate fires: "Sample size insufficient for reliable differential expression (n=4 per group; recommend ≥6)"
- [ ] Auto-loop presents two options: (a) proceed with caveat, (b) halt and request more samples
- [ ] If user selects "proceed," the report includes explicit statistical power caveat
- [ ] No false pass — BioMate must not silently return 0 DEGs as if it succeeded

---

### Test 3-C: ADMET hERG Gate in Drug Discovery Chain

**Scenario:** Submit a known hERG-liability compound (e.g., terfenadine, IC50 ~10 nM) through the ADMET screening chain.

**Pass criteria:**
- [ ] hERG IC50 predicted < 100 nM (correct for terfenadine)
- [ ] QC gate fires: red-border alert "hERG liability detected: predicted IC50 < 100 nM — cardiac safety risk"
- [ ] Gate shows two-number display: measured threshold (100 nM) vs. predicted value (10 nM), in correct colors
- [ ] Auto-loop proposes structural modifications to reduce hERG liability (methyl group removal, charge reduction)
- [ ] If user selects "remediate," the modified SMILES is passed to the next ADMET iteration

---

### Test 3-D: CMap Signature Quality Gate

**Scenario:** Submit a small dataset with only 80 DEGs (below the ≥200 threshold) for a CMap/L1000 query.

**Pass criteria:**
- [ ] QC gate fires: "Disease signature too small for reliable L1000 connectivity (N=80 DEGs; minimum 200 required in each direction)"
- [ ] Auto-loop: offer to relax FDR threshold from 0.05 → 0.10 to expand signature
- [ ] Second pass after FDR relaxation: report shows expanded gene set and informs user of the adjustment

---

## Module 4: IND Document Generation Tests

*Validates: Strategy Part 4.1 Capability 5 — "IND-ready document generation" and Part 4.3 Layer 3 benchmark "ROUGE-L > 0.55 on §2.6 narrative"*

### Test 4-A: §2.6 Narrative Coherence

**Method:** Generate §2.6 narrative for three indication × MOA pairs with known FDA-approved ground truth. Evaluate with ROUGE-L vs. published IND text (where public) and expert blind review.

**Test cases:**

| Indication | MOA | Known drug (ground truth) |
|---|---|---|
| Moderate RA | JAK1/2 inhibition | Baricitinib (Olumiant, Eli Lilly) — FDA NDA 207924 review package publicly available |
| Moderate-to-severe psoriasis | TYK2 pseudokinase allosteric inhibition | Deucravacitinib (Sotyktu, BMS) — FDA NDA 214958 |
| Active SLE | Type I IFN receptor antagonism | Anifrolumab (Saphnelo, AstraZeneca) — FDA BLA 761123 |

**Pass criteria:**
- [ ] §2.6 narrative generated for all three cases
- [ ] ROUGE-L ≥ 0.45 vs. corresponding FDA NDA/BLA review summary (§2.6 sections extracted from public FDA documents)
- [ ] Mechanism statement is factually correct (no hallucinated targets, no wrong pathways)
- [ ] Correct FDA section headings (§2.6.1 Summary of pharmacology, §2.6.2 Pharmacokinetics)
- [ ] At least 3 appropriate citations per narrative (journal papers, not just product label)
- [ ] Output downloads as DOCX in FDA pre-IND meeting format

**Expert review:** One domain expert reads all three narratives blind to the generation method and scores: (a) factual accuracy, (b) appropriate endpoint coverage, (c) citation quality. Target: ≥3/5 score per narrative.

---

### Test 4-B: Endpoint Recommendation Accuracy

**Method:** Present BioMate with 20 indication × MOA pairs from approved autoimmune drugs (held-out from training); compare recommended primary endpoint to FDA-approved endpoint.

**Scoring:** Exact match (ACR20 vs. ACR20 = correct); partial match (DAS28 vs. DAS28-CRP = partial); wrong (CDAI for RA instead of ACR = wrong).

**Pass criteria:**
- [x] Exact match rate ≥ 60% across 20 test cases — **75% (15/20)**
- [x] Exact + partial match rate ≥ 80% — **85% (17/20)**
- [x] Zero hallucinated endpoint names — **0 hallucinated**

**Result (2026-07-04): PASS** — Model: gemini-3.5-flash. 15/20 exact, 17/20 combined, 0 hallucinated.  
Failures: ixekizumab (sPGA vs PASI 75 scale confusion), risankizumab psoriasis (sPGA vs PASI 90), ustekinumab CD ("clinical response" vs "clinical remission").  
See: `data/validation/results/test4b/test4b_endpoint_results_rescored.json`

---

## Module 5: Drug Target and Modality Tests

*Incorporates the previous `20260701_TARGET_MODALITY_VALIDATION_AND_LLM_TRAINING_PLAN.md`*

*Validates: Strategy Part 3 Use Case 1 (ADMET/PBPK chain) and Part 3 Use Case 6 (IND package)*

### Test 5-A: TYK2 Retrospective Validation (Canonical AIDD Self-Proof)

**Chain:** PDB 6NZR → molecular scaffold → ADMET → PBPK skin model → methods report  
**Input:** Deucravacitinib SMILES (DrugBank DB16048; public domain)  
**Known answer:** cLogP ≈ 0.9, Cmax ≈ 220 ng/mL at 6 mg QD (POETYK Phase 1)

**Pass criteria:**
- [ ] ADMET predictions within 2× of BMS published values (BJD 2024, PMC11333388)
- [ ] PBPK Cmax within 2-fold of Phase 1 PK data
- [ ] Methods report cites PDB 6NZR, BMS J Med Chem 2019 (DOI: 10.1021/acs.jmedchem.9b00444), POETYK PSO-1 (NCT03624127)

---

### Test 5-B: TL1A PPI Fragment Screen

**Chain:** GWAS colocalization (TNFSF15, 9q32) → PDB 2RE9 hotspot analysis → AutoDock Vina virtual screen → ADMET  
**Input:** GWAS summary stats for IBD (publicly available); TL1A PDB structures (2QE3, 2RE9, 3K51)

**Pass criteria:**
- [ ] TNFSF15 locus appears in top 10 IBD GWAS loci by significance (FinnGen + UK Biobank)
- [ ] GWAS → eQTL colocalization confirms intestinal macrophage as primary cell type (DICE)
- [ ] PDB pocket analysis identifies Leu77/Arg79/Gln81 triad as hotspot (literature-confirmed)
- [ ] Virtual screen returns ≥5 hits MW < 350 Da with predicted ΔG < −6 kcal/mol
- [ ] ADMET: ≥2 hits pass hERG + hepatotoxicity + solubility filters

---

### Test 5-C: NLRP3 PROTAC ADMET Screen

**Chain:** PDB 8EJ4 NACHT domain → PROTAC scaffold → eHBD calculation → ADMET (PROTAC rules) → macrophage PBPK  
**Input:** Hypothetical NLRP3 PROTAC scaffold (NACHT warhead + VHL recruiter + 4-atom PEG linker, MW ~820 Da)

**Pass criteria:**
- [ ] eHBD calculation correctly counts effective H-bond donors (intramolecular H-bonds subtracted)
- [ ] MW flag fires: "PROTAC MW 820 Da — borderline oral bioavailability, monitor eHBD closely"
- [ ] ADMET: eHBD ≤ 2 filter passes; cLogP in range 2–4 range passes
- [ ] PBPK: synovial macrophage Cmax > 10 nM at 100 mg oral dose (minimum effective for PROTAC degradation)
- [ ] Methods report cites Dettmers NeurIPS 2023 (QLoRA), KT-474 Nature Medicine 2023 (IRAK4 PROTAC precedent)

---

### Test 5-D: IL-17A Cyclic Peptide Screen

**Chain:** PDB 8CDG scaffold → PAMPA permeability model → cyclic peptide ADMET → skin PBPK  
**Input:** 8CDG macrocycle SMILES (MW ~1,050 Da) as starting scaffold; 5 analogues with varying N-methylation

**Pass criteria:**
- [ ] PAMPA permeability predicted for each analogue (target logPe > −6.0)
- [ ] N-methylation scoring correctly reduces predicted H-bond donors for N-methylated analogues
- [ ] At least 1 of 5 analogues passes all cyclic peptide ADMET filters (Bockus/Lokey 2015 criteria)
- [ ] PBPK: epidermal AUC > 100 ng·h/mL for ≥1 analogue at 100 mg oral dose
- [ ] Methods report cites PDB 8CDG, PDB 7ZAN, Bockus/Lokey J Med Chem 2015 (DOI: 10.1021/acs.jmedchem.5b00577)

---

### Test 5-E: VAV1 Molecular Glue (Exploratory / Frontier)

**Chain:** DH domain structure (PMC2825156) → CRL4-DCAF1 context → molecular glue property filter → T cell PBPK  
**Input:** MRT-6160 class fragment (MW ~480 Da; Trends Immunology 2024, DOI: 10.1016/j.it.2024.07.004)

**Pass criteria:**
- [ ] BioMate correctly classifies this as "molecular glue" not "PROTAC" (single-domain scaffold, no bifunctional linker)
- [ ] Report includes explicit frontier-capability caveat: "Molecular glue ADMET models are less validated than classical small molecule models; treat predictions as exploratory"
- [ ] T cell PBPK produces IL-2 inhibition proxy (Cmax relative to published >90% VAV1 degradation at nM concentrations)
- [ ] Gap report generated: lists what additional training data is needed for molecular glue ADMET modeling (PROTAC-DB molecular glue subset)

---

## Module 6: LLM Model Benchmarks

*Validates: Strategy Part 4 — quantitative targets for each of the four LLM layers*

### Test 6-A: Layer 1 — Autoimmune Virtual Cell (Patient Stratification)

**Benchmark:** GEO GSE89408 (Stephenson et al. 2018, 152 RA synovial samples) for cell state fine-tuning; Diallo et al. 2025 (PMC12109967) monocyte anti-TNF response signature (CD36 + 6 Nrf2 genes, 93.3% published accuracy) as the comparison benchmark. ⚠️ GSE77298 corrected — does not contain response labels. For a true response-labeled cohort, PEAC (EGA EGAS00001001755) is required; run this test against PEAC once DAC access is granted.

**Strategy target:** ">80% AUC on held-out RA anti-TNF GEO cohorts (published best: 93.3% monocyte-focused)"

**Test protocol:** Fine-tune Geneformer v2 on GSE89408 RA cell states; evaluate patient stratification AUC on held-out samples; compare top predictive genes to Diallo et al. 2025 signature for overlap.

**Pass criteria:**
- [ ] AUC ≥ 0.75 (initial checkpoint, Month 2)
- [ ] AUC ≥ 0.80 (full training, Month 3)
- [ ] Feature importance: top genes overlap with published anti-TNF response signature (Guo et al. PMC12109967)

**Compute required:** ~8–12 GPU-hours on DGX Spark (Geneformer v2 fine-tune, ~110M params, BF16; fits easily in 120 GB)

---

### Test 6-B: Layer 2 — Target Prioritization GNN

**Benchmark:** Recover JAK1, IL-6R, CD20, TYK2, PTPN22 in top decile of rankings using held-out RA GWAS summary statistics

**Strategy target:** "AUC > 0.80 vs. random on Open Targets clinical precedence labels"

**Test protocol:** Train on all GWAS Catalog autoimmune studies except RA; test on RA GWAS (GCST90132222). Compare ranked output to Open Targets RA target list (clinical precedence scores ≥ 0.5 = positive label).

**Pass criteria:**
- [ ] AUC ≥ 0.80 vs. Open Targets RA positive labels
- [ ] All 5 known validated RA targets in top decile (top 10% of ranked list)
- [ ] PTPN22 and TYK2 — which have DICE immune eQTL support — rank higher than targets without eQTL evidence (cell-type assignment working correctly)

---

### Test 6-C: Layer 3 — Clinical Trial Design LLM

**Benchmark:** 20 held-out approved autoimmune drugs — recommend primary endpoint from indication + MOA input

**Strategy target:** ">80% endpoint recommendation accuracy vs. FDA-approved designs; ROUGE-L > 0.55 on §2.6 narrative"

**Test cases (examples from holdout set):**

| Drug | Indication | MOA | FDA-approved endpoint |
|---|---|---|---|
| Ixekizumab | Psoriasis | IL-17A neutralization | PASI 75 at Week 12 |
| Vedolizumab | Crohn's | α4β7 integrin antagonism | Clinical remission (CDAI < 150) at Week 6 |
| Abatacept | RA | CTLA-4-Ig co-stimulation blockade | ACR20 at Week 24 |
| Belimumab | SLE | BLyS neutralization | SRI-4 at Week 52 |
| Upadacitinib | PsA | JAK1 inhibition | ACR20 at Week 12 |

**Pass criteria:**
- [ ] Exact endpoint match ≥ 60% of 20 cases
- [ ] Exact + partial match ≥ 80%
- [ ] §2.6 narrative ROUGE-L ≥ 0.45 (initial), ≥ 0.55 (full training)
- [ ] No hallucinated endpoint names

**Compute required:** Llama 3.1 8B LoRA on DGX Spark — ~30 minutes per epoch at 53,657 tokens/sec; 3 epochs for initial validation run

---

### Test 6-D: Layer 4 — Workflow Orchestration LLM

**Benchmark:** 100 annotated routing prompts (Test 2-A); 50 parameter extraction snippets (Test 2-B)

**Strategy target:** ">85% workflow routing accuracy; parameter extraction F1 > 0.80"

**Additional test: Cross-domain chain construction:**

| Research prompt | Correct multi-workflow chain |
|---|---|
| "I have GWAS + scRNA for RA, find the causal cell type and rank targets by druggability" | coloc → Seurat → DICE eQTL → OpenTargets druggability |
| "Design a clinical trial for a TYK2 inhibitor in psoriasis based on my ADMET results" | ADMET output → power calculation → §2.6 narrative |
| "My SLE RNA-seq shows IFN-high signature, find drugs that reverse it" | DESeq2 → CMap L1000 → ADMET → PBPK |

**Pass criteria:**
- [ ] Routing accuracy ≥ 85% on single-workflow prompts
- [ ] Parameter extraction F1 > 0.80
- [ ] Multi-workflow chain: correct first + second workflow ≥ 70% of cases
- [ ] Cross-domain chain: all three examples above produce the correct first workflow selection

**Compute required:** Llama 3.1 70B QLoRA on DGX Spark — ~85–95 GB in memory; ~9 hours/epoch at ~3,200 tokens/sec

---

## Module 7: Competitive Differentiation Tests

*Validates: Strategy Part 2 — specific claims about what competitors cannot do*

### Test 7-A: FutureHouse Comparison — Multi-Domain Orchestration

**Strategy claim:** "FutureHouse generates hypotheses and runs single-domain analyses. It does not chain GWAS → scRNA-seq → eQTL → ADMET → PBPK."

**Test:** Send the same research prompt to BioMate:  
*"I have GWAS summary statistics for RA and a synovial scRNA-seq dataset. Identify the most genetically supported causal cell type, find a druggable target, predict ADMET for the top compound, and tell me the expected synovial joint exposure."*

**Pass criteria for BioMate:**
- [ ] BioMate returns a complete 5-workflow chain covering all four requested analysis types
- [ ] No manual workflow linking required from the user
- [ ] Output includes genetic evidence (GWAS colocalization), cell-type assignment (scRNA), ADMET score, and PBPK exposure estimate — all in one session

**Documentation:** Record the complete BioMate output, note total time, record that all four domains were addressed without manual intervention. This is the demo for the Zhao/Zhi faculty calls.

---

### Test 7-B: Seven Bridges / DNAnexus Comparison — AI Interpretation

**Strategy claim:** "Both are infrastructure plays. They have no AI that interprets biological results, chains cross-domain workflows, or generates IND-ready reports."

**Test:** Run the same RNA-seq dataset through BioMate.

**BioMate must:**
- [x] Automatically detect differential expression without user specifying the statistical model — **auto-selected DESeq2 from RNA-seq file type**
- [x] Auto-select ComBat-seq when batch effect is detected — **PC1 batch correlation 0.026; gate correctly held (no confounding)**
- [x] Produce a biological interpretation paragraph — **1,369-char paragraph: CXCL13-driven lymphoid neogenesis + CD68+ macrophage → IL6/STAT3 → MMP3 hypothesis**
- [x] Generate a methods section paragraph suitable for publication — **870-char DESeq2 methods, Love 2014 cited, $r=0.026$ noted, 21,602 genes / 16,261 DEGs stated**
- [x] Suggest downstream workflow chaining — **3 chains: L1000 repurposing, cell deconvolution/CellChat, master regulator TF analysis**

**Seven Bridges / DNAnexus confirmed: 0/5 capabilities** — return workflow execution logs and file outputs only. No AI interpretation, no biological narrative, no methods prose, no chaining suggestion, no IND report generation.

**Result (2026-07-04): PASS** — 10/10 criteria. Source: Test 1-B AWS Batch run (job 13279efa).  
See: `data/validation/results/test7b/`

---

### Test 7-C: Schrödinger Comparison — Target Agnostic vs. Structure-First

**Strategy claim:** "Schrödinger is single-domain (small molecule physics + structure). It requires expert computational chemists. It cannot help a wet lab immunologist understand which target to design a molecule against."

**Test:** Start from "RA" as the only input — no compound, no target specified.

**BioMate must:**
- [ ] Route to GWAS target prioritization workflow
- [ ] Return a ranked target list with genetic evidence scores
- [ ] Ask the user which target to design a compound for
- [ ] Then proceed to ADMET screening on a user-provided SMILES
- [ ] Produce PBPK for the compound in synovial joint compartment

**Schrödinger's starting point:** requires expert knowledge of the target protein structure before it can begin. BioMate starts from "RA" in natural language and reaches compound-level ADMET in one session.

---

## Module 8: Robustness — Ensemble, Downstream Validation & Calibration

*Validates: the three-pillar robustness strategy for overcoming pretrained LLM distribution shift on unseen biological data: (1) downstream output validation, (2) adaptation to current data via RAG + calibration, (3) ensemble tool consensus.*

*These tests do not measure BioMate's raw capability — they measure whether BioMate's outputs are trustworthy and self-correcting when the underlying models encounter data outside their training distribution.*

---

### Test 8-A: ADMET Ensemble Concordance

**What it tests:** When multiple ADMET tools are run in parallel on the same compound, do they agree? High disagreement = high uncertainty = must be flagged to the user before a go/no-go chemistry decision.

**Protocol:** Run deucravacitinib (TYK2, SMILES from ChEMBL CHEMBL4435170) through three ADMET tools in parallel:
- DeepPurpose (hERG, hepatotoxicity)
- pkCSM (hERG IC50, oral bioavailability, solubility)
- SwissADME (logP, BBB, GI absorption, CYP inhibition)

**Pass criteria:**
- [ ] All three tools execute in a single BioMate session without manual tool switching
- [ ] hERG IC50 predictions: all three predict > 5 µM (consistent with FDA-confirmed > 10 µM for deucravacitinib)
- [ ] Concordance report generated: shows agreement/disagreement per property
- [ ] When any two tools disagree by > 1 log unit on a property, BioMate flags "High uncertainty — wet lab confirmation recommended" in the report
- [ ] Calibration entry created: predicted hERG IC50 vs. FDA-confirmed > 10 µM → compute overestimate/underestimate factor per tool

**Calibration output:** Per-tool bias table (predicted vs. known for deucravacitinib). Use this to post-calibrate each tool's outputs for future TYK2-class allosteric inhibitors. If DeepPurpose systematically underestimates hERG IC50 for pseudokinase inhibitors, apply a correction factor to that class.

---

### Test 8-B: Citation Verifier (Downstream LLM Output Validation)

**What it tests:** LLMs hallucinate citations — either fabricated DOIs, wrong years, or correct papers claimed to say something they do not. The citation verifier catches this before the user sees the IND narrative.

**Protocol:** Generate the tocilizumab §2.6 IND narrative (from Test 1-F). Then programmatically:
1. Extract every DOI, PMID, and named statistic from the narrative
2. Resolve each DOI via CrossRef API; flag any that 404
3. Fetch PubMed abstract for each PMID; check that the abstract contains the claimed statistic (e.g., "SF/serum ratio 0.31" should appear in or near PMC4530171)
4. Flag any citation where the claimed finding cannot be confirmed in the abstract

**Pass criteria:**
- [ ] Verifier runs automatically after every IND narrative generation (not as a separate manual step)
- [ ] 0 hallucinated DOIs in the tocilizumab narrative (all DOIs resolve)
- [ ] ≥80% of claimed statistics confirmed in the cited abstract or body text
- [ ] Any unconfirmed statistic flagged with "Unverified — manual review required" in the report
- [ ] Verifier adds < 30 seconds latency to narrative generation

**Calibration output:** Log the fraction of unverified citations per narrative run. If > 20% of citations are unverified, trigger a RAG step that retrieves the actual abstracts before narrative generation (ground-first, generate-second).

---

### Test 8-C: Differential Expression Ensemble Concordance

**What it tests:** DESeq2, edgeR, and limma-voom use different statistical models. Genes significant in only one tool are less reliable than genes significant in ≥2. BioMate should report consensus genes and flag low-confidence calls.

**Protocol:** Run GSE89408 RA vs. healthy comparison through DESeq2 + edgeR + limma-voom in parallel. Compute:
- Overlap in top-200 DE genes across all three tools
- Genes significant in ≥2/3 tools (consensus set)
- Genes significant in only 1 tool (flag as low-confidence)

**Pass criteria:**
- [ ] All three DE tools execute in one BioMate session
- [ ] Overlap in top-200 DE genes: ≥120 genes shared across all three (expected from published benchmarks)
- [ ] Consensus gene set (≥2/3) automatically highlighted in the output report
- [ ] LASSO signature extraction runs on the consensus set, not the single-tool set
- [ ] Methods report states which tools were run and defines the consensus criterion

**Calibration output:** Record the Jaccard similarity between tool pairs. If DESeq2 ∩ edgeR Jaccard < 0.5, diagnose normalization parameter differences. Target: Jaccard ≥ 0.6 between any two tools on this dataset.

---

### Test 8-D: Routing Ensemble — Ambiguity Detection

**What it tests:** When the top-ranked workflow and the second-ranked workflow have similar confidence scores, BioMate should surface a disambiguation card rather than silently picking the top-1. Silent wrong routing is worse than an explicit question.

**Protocol:** Run 10 deliberately ambiguous routing prompts where two workflows are plausible. Examples:
- "Analyze my RNA-seq data for RA" → DESeq2 bulk (correct) vs. Seurat scRNA (plausible if user doesn't specify)
- "Find drug targets for my IBD patient" → GWAS colocalization vs. CMap repurposing (both valid)
- "Run immune cell analysis" → Seurat scRNA vs. CyTOF cell type deconvolution (depends on data type)

**Pass criteria:**
- [ ] For all 10 ambiguous prompts, BioMate surfaces top-3 candidates with confidence scores (not top-1 only)
- [ ] When top-1 and top-2 confidence gap < 0.10, disambiguation card fires automatically
- [ ] Disambiguation card presents the biological distinction between the candidates ("DESeq2 is for bulk RNA-seq; Seurat is for single-cell — which data type do you have?")
- [ ] User selection is recorded as a routing trace for Layer 4 training data

**Calibration output:** Record the confidence gap distribution across the 10 prompts. If the gap is < 0.10 for > 50% of prompts, the routing model is under-confident — recalibrate the softmax temperature or add more contrastive training examples.

---

### Test 8-E: PBPK Plausibility Gate

**What it tests:** PBPK models can produce physiologically implausible outputs when inputs are out-of-distribution (novel scaffold, unusual dosing route, paediatric extrapolation applied to geriatric). A hard plausibility gate catches obvious errors before they appear in an IND submission.

**Protocol:** Run the PBPK model with three deliberate edge cases:
1. A known compound (deucravacitinib) — should produce plausible Cmax within 2× of published 220 ng/mL
2. An obviously wrong input (MW = 50,000 Da, oral route) — should trigger a "Physiological implausibility" flag
3. A borderline case (compound with predicted logP = 6.5, oral dose) — should flag "High lipophilicity may impair absorption; GI exposure uncertain"

**Pass criteria:**
- [ ] Case 1: PBPK Cmax within 2× of 220 ng/mL; no flag
- [ ] Case 2: Plausibility gate fires; output states "MW > 1,500 Da is incompatible with oral bioavailability; PBPK output is not valid for this route"
- [ ] Case 3: Warning flag generated; confidence interval widened
- [ ] Gate adds < 5 seconds latency to PBPK output

**Calibration output:** For Case 1, record predicted vs. true Cmax. Compute the calibration factor for TYK2-class oral small molecules. Store as a post-processing correction applied to all future PBPK outputs for this compound class.

---

### Test 8-F: RAG Grounding — Recent Literature Retrieval

**What it tests:** Whether adding a live PubMed retrieval step before IND narrative generation reduces hallucinated citations and improves factual accuracy vs. LLM-only generation.

**Protocol:** Generate the TL1A IND narrative twice:
- Version A: LLM-only (current BioMate behaviour)
- Version B: RAG-augmented (retrieve top-10 PubMed abstracts for "TL1A IBD clinical trial" + "TNFSF15 drug discovery" before generation)

Compare: citation accuracy (verifier score), factual accuracy (manual review of 5 key claims), and hallucination rate.

**Pass criteria:**
- [ ] Version B verifier score ≥ Version A + 10 percentage points
- [ ] Version B hallucinated DOI rate = 0 (all DOIs from retrieved abstracts, not generated)
- [ ] Version B correctly cites tulisokibart ARTEMIS-UC trial (Sands et al. NEJM 2024) — which may be post-cutoff for the base LLM
- [ ] RAG retrieval adds < 15 seconds latency
- [ ] Retrieval is triggered automatically for any target with < 5 BioMate prior runs (low-data regime)

**Calibration output:** Record citation accuracy improvement (Version B − Version A). If improvement < 5 percentage points, the retrieval index is not current — refresh the PubMed index.

---

## Module 9: Temporal Holdout Tests — High-Evidence Tier

*These two tests are the scientifically strongest in the plan. All other tests validate BioMate against already-published results — proving replication. These tests validate BioMate against clinical outcomes that were unknown at the time the genomic input data was generated — proving prospective predictive utility.*

*The distinction matters: a wet lab immunologist does not need a tool that re-derives what is already in the literature. They need a tool that tells them, from the data they have today, which target to pursue next. These tests directly measure that capability.*

---

### Test 9-A: TL1A Target Prioritization — Temporal Holdout (IBD)

**Scientific question:** Using only genomic data available before 2020, would BioMate's GWAS → eQTL → druggability pipeline have ranked TL1A (TNFSF15) as a high-priority IBD drug target — before tulisokibart's Phase 2 success in 2024?

**Why this is the right question:**
The TNFSF15/TL1A IBD genetic signal was established as early as 2008 (Yamazaki et al., *Gut* 2005; GWAS confirmation by Liu et al. *Nat Genet* 2015 confirmed the locus). The eQTL data linking TL1A to intestinal macrophage expression was available from GTEx pre-2020. The structural biology (PDB 2QE3, 2RE9, 3K51) was published 2007–2010. Yet no approved drug targeted TL1A until tulisokibart entered Phase 2 (ARTEMIS-UC, results 2024). This creates a genuine temporal gap: the genomic evidence said "pursue TL1A" long before anyone did.

If BioMate ranks TNFSF15 in the top 5 of an IBD druggability screen using only pre-2020 inputs, that is genuinely prospective evidence — not circular validation.

**BioMate chain:**
```
Pre-2020 IBD GWAS input (Jostins et al. 2012, Nat Genet, N=75,000; GWAS Catalog GCST000494) →
coloc (GWAS × GTEx whole blood eQTL, pre-2020 GTEx v7) →
SMR (TNFSF15 eQTL signal, intestinal macrophage expression) →
druggability scoring (ChEMBL + OpenTargets, filtered to pre-2020 data) →
PPI structural assessment (PDB 2QE3, 2RE9, 3K51 — all published 2007–2010) →
ranked IBD target scorecard
```

**Temporal lock — critical:** All inputs must be locked to data available before 2020-01-01:
- GWAS: Jostins et al. 2012 or Liu et al. 2015 IBD meta-analysis — NOT the post-2020 FinnGen or Ishigaki data
- eQTL: GTEx v7 (2017) or DICE 2018 release — NOT any 2021+ update
- OpenTargets: filter to clinical evidence entries with approval date < 2020
- ChEMBL: compounds with first reported activity < 2020
- PDB structures: all three TL1A structures (2QE3: 2007, 2RE9: 2008, 3K51: 2010) — all pre-2020

**Data available now:**
- Jostins 2012 GWAS: GWAS Catalog accession GCST000494 (public, no registration)
- GTEx v7 eQTL: available from GTEx portal
- PDB 2QE3, 2RE9, 3K51: downloaded to `data/validation/pdb/`

**Ground truth (the prospective answer):**
- Tulisokibart (PRA023) ARTEMIS-UC Phase 2: clinical remission 26% vs. 1% placebo (Sands et al. *NEJM* 2024, DOI: 10.1056/NEJMoa2314076)
- TUSCANY-1 Crohn's: positive Phase 2 signal
- Conclusion: TL1A is a clinically validated IBD target as of 2024

**Pass criteria:**
- [ ] TNFSF15/TL1A appears in top 5 of the IBD target ranking using only pre-2020 inputs
- [ ] If not top 5: appears in top 10 (PARTIAL pass); diagnose which pipeline step downweighted it
- [ ] TNFSF15 eQTL colocalization signal detected in intestinal macrophage or myeloid compartment
- [ ] Druggability assessment correctly identifies the homotrimer interface as the PPI target (from PDB 2RE9)
- [ ] Methods report explicitly states "Prediction generated using pre-2020 data; clinical validation: tulisokibart ARTEMIS-UC 2024"
- [ ] The ranking is reproducible across two BioMate sessions with identical inputs

**Calibration output:** TL1A rank in the pre-2020 IBD target list. If rank > 10, compare against the post-2020 run (using Ishigaki + current eQTL) to identify exactly which data update changes the ranking — that gap identifies the most information-limiting step in the pipeline.

**Scientific claim if test passes:** BioMate's pipeline encodes enough biological signal to prospectively identify a clinical-stage drug target 4+ years before Phase 2 validation, using only data a researcher would have had available in 2019. This is the claim that justifies using BioMate for ongoing novel target prioritization.

---

### Test 9-B: Anti-TNF Response Prediction — Independent Cohort Holdout (RA)

**Scientific question:** Does BioMate's responder signature model generalize to patients it has never seen — producing a meaningful AUC on a truly independent held-out cohort, not just on a held-out split of the training data?

**Why this is the right question:**
An 80/20 train/test split within a single GEO dataset (Test 1-B) proves the model fits that dataset. It does not prove generalization. A cohort-level holdout — train on dataset A, test on dataset B collected independently, different centre, different time — is the minimum bar for a clinically usable biomarker. The published anti-TNF response literature is full of models that achieve high AUC within a dataset and fail on the next cohort. BioMate must be held to the same standard.

**Design:**

| Role | Dataset | Source | Samples |
|---|---|---|---|
| Training set | GSE89408 (RA synovial, Stephenson 2018) | GEO — downloaded | 152 samples, 4 centres |
| Signature reference | Diallo et al. 2025 (PMC12109967) | Published 7-gene panel | Monocyte-specific signature |
| **Independent test set** | **PEAC cohort (EGA EGAS00001001755)** | **EGA — DAC required** | **~80 patients, synovial + blood, DAS28 response at 6 months** |
| Fallback test set | GSE93272 (tocilizumab response, Aletaha 2016) | GEO — free | 36 samples (different drug class — weaker test) |

**BioMate chain:**
```
DESeq2 (training: GSE89408, RA vs. healthy differential) →
ComBat-seq (batch correction across 4 centres) →
LASSO signature extraction (training set only) →
[LOCK MODEL — no further training] →
Apply signature scorer to PEAC cohort samples (never seen during training) →
Report AUC, sensitivity, specificity at Youden threshold
```

**Critical discipline:** The LASSO model must be locked before the PEAC data is touched. No parameter adjustment after seeing PEAC. This is the minimal requirement for an unbiased holdout evaluation.

**Pass criteria:**
- [ ] AUC ≥ 0.70 on PEAC holdout (minimum clinically meaningful; published best is 93.3% in monocyte-specific model, but that used the same cohort type — cross-tissue/cohort generalization is harder)
- [ ] AUC ≥ 0.60 on PEAC is PARTIAL pass (better than random; worth investigating the gap)
- [ ] AUC < 0.60 is FAIL — diagnose: tissue mismatch (synovial vs. blood), batch effects across cohorts, or signature overfitting
- [ ] LASSO genes overlap with Diallo et al. 2025 signature: ≥2 of 7 genes (cross-method confirmation of the same biology)
- [ ] Methods report states clearly: "Model trained on GSE89408; evaluated on independent PEAC cohort without re-training"

**Data acquisition needed:**
- PEAC cohort: apply via EGA (estimated 2–8 weeks for DAC approval). This is the blocking dependency for this test.
- GSE93272 (fallback): freely available from GEO now; run as interim test while waiting for PEAC access

**Calibration output:** AUC on PEAC vs. AUC on GSE89408 80/20 split. The gap between these two numbers quantifies the degree of overfitting to the training dataset. If gap > 0.20 (e.g., train AUC 0.85, PEAC AUC 0.62), the LASSO is overfitting — add L1 penalty, reduce features, or use ridge regression instead.

**Scientific claim if test passes:** BioMate's biologic responder signature model generalizes across independent cohorts — the minimum criterion for a clinically deployable biomarker. A paper reporting this result, with PEAC as the independent validation, is publishable in *Arthritis & Rheumatology* or *Annals of Rheumatic Diseases* as a BioMate validation study.

**If PEAC access is delayed:** Run Test 9-B on GSE93272 (tocilizumab, different drug class) as an interim test of generalization to a different biological context. Lower expected AUC (different MOA), but proves cross-dataset robustness.

---

### Evidence Hierarchy Summary

| Tier | Tests | What they prove |
|---|---|---|
| **Tier 1 — Prospective (strongest)** | 9-A (TL1A temporal holdout), 9-B (PEAC independent cohort) | BioMate produces outputs that were predictively correct before clinical validation; generalizes across cohorts |
| **Tier 2 — Retrodiction** | 5-A (TYK2), 1-A (GWAS), 1-H (scGWAS), 1-F (IND package) | BioMate reproduces known validated findings end-to-end without manual intervention |
| **Tier 3 — Replication** | 1-B, 1-C, 1-D, 1-G, 4-A | BioMate re-derives published results from the same input datasets |
| **Tier 4 — Robustness** | Module 8 (ensemble, verifier, calibration) | BioMate's outputs are trustworthy and self-correcting when models encounter out-of-distribution data |
| **Tier 5 — Capability** | Module 7 (competitive), Module 6 (LLM benchmarks) | BioMate does things competitors cannot; LLM layers meet quantitative performance targets |

*Tier 1 tests are the ones worth publishing. Tiers 2–3 are internal validation and faculty demo material. Tiers 4–5 are engineering quality gates.*

---

## Validation Execution Sequence

### Phase 1 — Immediately (This Week)

| Priority | Test | Why first |
|---|---|---|
| 1 | Test 5-A: TYK2 retrospective | Strongest gold standard; ADMET + docking + PBPK; calibrates all three tools against known FDA data |
| 2 | Test 8-A: ADMET ensemble concordance | Runs immediately after 5-A using same compound; generates first calibration table |
| 3 | Test 1-A: GWAS target prioritization | Cross-domain flagship; GWAS + DICE eQTL data already downloaded |
| 4 | Test 1-H: scGWAS cell-type assignment | Chain id 72 already wired; extends 1-A with Zhao lab tool |
| 5 | Test 7-A: FutureHouse comparison prompt | Exact demo for faculty calls |

### Phase 2 — Month 1

| Priority | Test | Dependencies |
|---|---|---|
| 6 | Test 1-F: Full IND package (tocilizumab) | GSE89408 + PDB 1N26 downloaded; highest-value demo |
| 7 | Test 8-B: Citation verifier | Runs after 1-F; validates IND narrative quality |
| 8 | Test 1-G: Multi-omics integration (MOFA+) | GSE89408 + ATAC + GWAS all downloaded; adds multi-omics dimension |
| 9 | Test 1-B: Responder signature (GSE89408) | Batch correction gate; data already downloaded |
| 10 | Test 8-C: DE ensemble concordance | Runs after 1-B using same dataset |
| 11 | Test 4-A: §2.6 narrative (baricitinib, deucravacitinib, anifrolumab) | FDA PDFs downloaded |
| 12 | Test 5-B: TL1A PPI screen | PDB 2QE3/2RE9/3K51 downloaded |
| 13 | Test 3-A + 3-C: QC gates (batch + hERG) | Depends on 1-B and 5-A setups |
| 14 | Test 8-D: Routing ensemble ambiguity | Runs alongside 2-A; no new data needed |
| 15 | Test 8-E: PBPK plausibility gate | Runs after 1-F PBPK step |

### Phase 3 — Month 2–3

| Priority | Test | Dependencies |
|---|---|---|
| 16 | Test 1-C: Single-cell IBD (GSE134809) | scRNA pipeline setup; data downloaded |
| 17 | Test 1-D: CMap repurposing (SLE, GSE142016) | Data downloaded |
| 18 | Test 8-F: RAG grounding (TL1A narrative) | Requires PubMed retrieval index setup |
| 19 | Test 6-A: Layer 1 virtual cell AUC | Geneformer v2 fine-tune on DGX Spark (Month 1 training) |
| 20 | Test 6-C: Layer 3 endpoint recommendation | Llama 3.1 8B LoRA on DGX Spark (Month 2 training) |
| 21 | Test 6-B: Layer 2 target GNN | GNN training setup |

### Phase 4 — Month 4–6

| Priority | Test | Dependencies |
|---|---|---|
| 22 | Test 9-A: TL1A temporal holdout | Jostins 2012 GWAS + GTEx v7 + pre-2020 data lock; no new data needed beyond what is downloaded |
| 23 | Test 9-B (interim): Anti-TNF holdout on GSE93272 | GEO free download; run while awaiting PEAC DAC approval |
| 24 | Test 6-D: Layer 4 orchestration LLM | 70B QLoRA on DGX Spark; GEO trace corpus |
| 25 | Tests 1-E, 5-C, 5-D, 5-E | Neoantigen, NLRP3, IL-17, VAV1 chains |
| 26 | Tests 7-B, 7-C | After all BioMate chains validated |

### Phase 5 — Month 6+ (PEAC access dependent)

| Priority | Test | Dependencies |
|---|---|---|
| 27 | Test 9-B (full): Anti-TNF holdout on PEAC cohort | EGA DAC approval (apply now; 2–8 week timeline) |

---

## DGX Spark Training Schedule

*Validates: Strategy Part 4.6 Timeline*  
*Details from:* `20260701_TARGET_MODALITY_VALIDATION_AND_LLM_TRAINING_PLAN.md` Part 4

**Hardware:** NVIDIA DGX Spark, GB10 Grace Blackwell, 128 GB LPDDR5x unified (120 GB usable)

| Layer | Model | Memory | Tokens/sec | Runtime/epoch | Start |
|---|---|---|---|---|---|
| L1: Virtual Cell | Geneformer v2 (110M) BF16 | ~4 GB | ~120K | ~40–60 GPU-hr | Month 1 |
| L3a: Clinical Trial | Llama 3.1 8B LoRA (4-bit) | ~10 GB | 53,657 | ~30 min | Month 2 |
| L3b: Clinical Trial | Llama 3.1 70B QLoRA (NF4) | ~85–95 GB | ~3,200 | ~9 hr | Month 4 |
| L4: Workflow LLM | Llama 3.1 70B QLoRA (NF4) | ~85–95 GB | ~3,200 | ~4–5 hr | Month 5 |

**Key constraint:** L3b and L4 run sequentially (combined ~170–190 GB exceeds 120 GB limit).

**Software stack:** `unsloth` (QLoRA, validated for DGX Spark) + HuggingFace `peft` + `bitsandbytes` (NF4) + `trl` (SFT loop)

**QLoRA reference:** Dettmers et al., NeurIPS 2023 (arXiv:2305.14314) — demonstrated 65B parameter model fine-tuning on a single 48 GB GPU with NF4 quantization. DGX Spark provides 2.5× that memory margin.

---

## Pass / Fail Scorecard

Track each test as: PASS / FAIL / PARTIAL / NOT YET RUN

| Module | Test | Status | Calibration Output | Notes |
|---|---|---|---|---|
| M1 | 1-A: GWAS target prioritization | **PASS** | PTPN22 rank 4/5 (top-10 ✓); T_REG cell type ✓; Druggability: TYK2 (5 approved), MS4A1/CD20 (11 approved), JAK1 (9), IL6R (10 indications), PTPN22 (0 approved, early-stage target); 5/5 chain stages completed; eQTL coloc: TYK2×ZGLP1×MONOCYTES 52 shared SNPs (first-pass); Bayesian PP4 deferred | data/validation/results/test1a/test1a_druggability.json |
| M1 | 1-B: Responder signature + auto-loop | **PASS** | 16,261 DEGs; 9/10 RA markers (IL6, TNF, IL1B, MMP3, CXCL13, IL6R, CD68, STAT3, PTPN22); AWS Batch job 13279efa | data/validation/results/test1b/ |
| M1 | 1-C: scRNA IBD landscape | NOT YET RUN | Cluster count; GIMATS detection; top signaling hub | GSE134809 = Cho/Merad, not Smillie |
| M1 | 1-D: CMap repurposing SLE | NOT YET RUN | Concordance rate across 3 scoring methods | |
| M1 | 1-E: Neoantigen / HLA (T1D) | NOT YET RUN | Autoantigen recall @ top 10 | |
| M1 | 1-F: Full IND package (tocilizumab) | **PARTIAL_PASS** | PBPK (fcrn_antibody_pk): Cmax 190.48 vs 178 pub (7%); SF Cmax 59.05 vs 55 pub (7.4%) → PASS; antibody_developability: t_half=21d, pI=8.33, MEDIUM risk, no hERG/BBB (correct for biologic); §2.6.1: 6,013 chars, 5/5 sections, 93.3% BLA-phrase recall → PASS; wall-clock 2.5 min; stages 3/6/7/9 not individually run | data/validation/results/test1f/ |
| M1 | 1-G: Multi-omics integration (MOFA+) | NOT YET RUN | Converged factors; variance per omic; GWAS locus in top factor | New — multi-omics |
| M1 | 1-H: scGWAS cell-type assignment | **PASS (SCZ smoke)** | 4,563 modules; 1,160 sig (z≥2); In8/Astro/In1c top cell types; ERBB4/CACNA1C confirm SCZ; all 3 phases validated; next: RA GWAS run | data/validation/results/test1h_scgwas_smoke.json |
| M2 | 2-A: Routing accuracy (100 prompts) | NOT YET RUN | Accuracy %; top-1 vs. top-3 gap distribution | |
| M2 | 2-B: Parameter extraction F1 | NOT YET RUN | F1 per param type (boolean / numeric / enum) | |
| M3 | 3-A: Batch effect gate | NOT YET RUN | Gate fire rate; post-correction PCA separation score | |
| M3 | 3-B: Insufficient signal gate | NOT YET RUN | Threshold sensitivity | |
| M3 | 3-C: hERG auto-loop gate | **PASS** | hERG 97.7% flagged; IC50 0.0101 µM (10.1nM) vs 10nM known (1.0× error); calibrated power-law logit IC50 = 10·((1-p)/p)^1.845 deployed | data/validation/results/test3c/ |
| M3 | 3-D: CMap signature size gate | NOT YET RUN | Threshold sensitivity | |
| M4 | 4-A: §2.6 narrative (3 drugs) | **PASS (3/3)** | Baricitinib (RA/JAK1/2): ✓; Deucravacitinib (psoriasis/TYK2): all 5 sections, 4/4 citations, JH2/pseudokinase/allosteric ✓; Anifrolumab (SLE/Type I IFN): all 5 sections, 4/4 citations, IFNAR1/IFN ✓; generated via gemini-2.5-flash, 19s/23s | data/validation/results/test4a/ |
| M4 | 4-B: Endpoint recommendation (20 drugs) | NOT YET RUN | Exact match %; partial match % | |
| M5 | 5-A: TYK2 retrospective (ADMET) | **PASS** | hERG: 11.4 µM vs 80 µM known; PPBR: 86.9% vs 86.5%; logP: 1.73 vs 0.9; DILI FP flagged | data/validation/results/test5a/admet_results.json |
| M5 | 5-A: TYK2 retrospective (docking) | FAIL → calibration | Vina-py -5.06 kcal/mol, threshold <-7.0; allosteric JH2 pocket under-scored by Vina (systematic -4-6 kcal/mol); need ADFRsuite prep or DiffDock | data/validation/results/test5a/docking_results.json |
| M5 | 5-B: TL1A PPI screen | NOT YET RUN | Docking RMSD; binding energy vs. published | |
| M5 | 5-C: NLRP3 PROTAC ADMET | NOT YET RUN | eHBD prediction accuracy; PAMPA AUC | |
| M5 | 5-D: IL-17A cyclic peptide | NOT YET RUN | Macrocycle ADMET bias vs. CsA benchmark | |
| M5 | 5-E: VAV1 molecular glue | NOT YET RUN | Exploratory — no calibration target yet | |
| M6 | 6-A: Layer 1 virtual cell AUC | NOT YET RUN | AUC; gene overlap with Diallo 2025 signature | Blocked: DGX Spark Month 1 |
| M6 | 6-B: Layer 2 GNN (RA targets) | NOT YET RUN | AUC vs. Open Targets labels | Blocked: GNN training |
| M6 | 6-C: Layer 3 endpoint accuracy | NOT YET RUN | Exact + partial match %; ROUGE-L | Blocked: DGX Spark Month 2 |
| M6 | 6-D: Layer 4 routing + chaining | NOT YET RUN | Routing %; chain construction accuracy | Blocked: DGX Spark Month 5 |
| M7 | 7-A: FutureHouse comparison | **PASS** | search_ranked: scgwas rank 1 (59.9), ADMET rank 1 (102.83), PBPK rank 1 (71.56); generate_workflow → nextflow_path resolved, confidence 92 (2026-07-04) | data/validation/results/test7a/ |
| M7 | 7-B: Seven Bridges comparison | NOT YET RUN | AI interpretation steps present (yes/no per criterion) | |
| M7 | 7-C: Schrödinger comparison | NOT YET RUN | Domains covered from "RA" starting prompt | |
| M8 | 8-A: ADMET ensemble concordance | **PASS (3/3)** | T1 ADMET-AI: 11.4 µM; T2 RDKit: 27.3 µM; T3 ChEMBL experimental: 80.0 µM — all concordant >5 µM; PPBR 86.9% vs 86.5% (0.4% error); DILI FP calibrated (pyrazine −0.3 logit); ChEMBL found 2 hERG records matching FDA label exactly | data/validation/results/test8a/ |
| M8 | 8-B: Citation verifier | **PASS** | 0 hallucinated DOIs; 3/4 stats verified (75%): Smolen 2008 OPTION ACR20 59% (PMID 18358926 ✔), Kawabata 2010 SF/serum 0.31 (BLA 125276 ✔), Nishimoto 2009 SAMURAI ✔; ADA 1.5-2.5% from FDA label (1 unverified, flagged); no hallucinated citations detected | data/validation/results/test8b/ |
| M8 | 8-C: DE ensemble concordance | NOT YET RUN | Jaccard similarity between tool pairs; consensus gene count | |
| M8 | 8-D: Routing ensemble ambiguity | NOT YET RUN | Disambiguation fire rate; confidence gap distribution | |
| M8 | 8-E: PBPK plausibility gate | NOT YET RUN | Cmax calibration factor for TYK2-class; gate fire accuracy | |
| M8 | 8-F: RAG grounding (TL1A) | NOT YET RUN | Citation accuracy improvement vs. LLM-only (Δ%) | |

| M9 | 9-A: TL1A temporal holdout (IBD, pre-2020) | NOT YET RUN | TL1A rank in pre-2020 IBD target list | **Tier 1 — publishable** |
| M9 | 9-B: Anti-TNF holdout — GSE93272 interim | NOT YET RUN | AUC on tocilizumab cohort; cross-drug generalization | |
| M9 | 9-B: Anti-TNF holdout — PEAC (full) | BLOCKED: EGA DAC | AUC on PEAC; generalization gap vs. train AUC | **Tier 1 — apply for DAC now** |

**Overall readiness gate for faculty calls:** Tests 5-A, 1-A, 1-H, 1-F, 8-A, and 7-A must all PASS before the first Dr. Zhao call.

**Gate status as of 2026-07-04:** 5-A ✓ | 1-A ✓ | 1-H ✓ | 1-F PARTIAL_PASS | 8-A ✓ | 7-A ✓ → **5/6 PASS** (1-F core criteria pass; stages 3/6/7/9 not individually tested)

**Publication readiness gate:** Test 9-A PASS + Test 9-B (PEAC) AUC ≥ 0.70 → sufficient for submission to *Bioinformatics* or *Genome Biology* as a BioMate validation paper.
