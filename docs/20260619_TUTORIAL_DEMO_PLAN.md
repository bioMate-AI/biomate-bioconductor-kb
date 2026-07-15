# BioMate Tutorial Demos — Per-Domain Plan

**Date:** 2026-06-19
**Goal:** Add **one tutorial demo per top domain** to the live tutorials page (`frontend/client/src/pages/tutorials.tsx`), each anchored on a real research task with a **validatable gold standard** so we can prove the run is correct, not just "completes."

## 0. What's already on the tutorials page

`/tutorials` currently embeds 4 YouTube videos (see `VIDEOS[]` in `tutorials.tsx`):

| Existing video | Domain covered |
|---|---|
| BioMate overview (`bpG0IWrwN5g`) | platform intro (no specific domain) |
| Multi-step Workflow + QC (`C4gQD-xbHnQ`) — CryoSPARC SPA | **cryo_em** |
| After-Run Report (`F2DgmBa5gq8`) | reporting (cross-domain) |
| IND §2.6 Report (`IDcICWmB0Oo`) | **drug_discovery + pharmacology** |

**Already covered:** cryo_em, drug_discovery, pharmacology, reporting.

**Top domains still missing a tutorial demo (priority order):**

1. transcriptomics (1,692 workflows / 15 chains)
2. single_cell (93 / 8 chains)
3. variant_calling (181 / 4 chains)
4. epigenomics (262 / 5 chains)
5. proteomics (179 / 1 chain)
6. metagenomics (75 / 1 chain)
7. metabolomics (57 / 1 chain)

These 7 are the demos to produce. The rest of this doc keeps the longer 3-per-domain catalog as a backlog, but the **immediate deliverable is one demo per missing domain.**

---

## 1. Survey: what BioMate actually has

### Workflow inventory (`backend/database/galaxy_ai_tools.db`)

| Domain            | Workflows | Curated chains |
|-------------------|-----------|----------------|
| transcriptomics   | 1,692     | 15             |
| genomics          | 750       | 5              |
| epigenomics       | 262       | 5              |
| variant_calling   | 181       | 4              |
| proteomics        | 179       | 1              |
| drug_discovery    | 110       | 17             |
| systems_biology   | 108       | —              |
| single_cell       | 93        | 8              |
| imaging           | 77        | —              |
| metagenomics      | 75        | 1              |
| metabolomics      | 57        | 1              |
| pharmacology      | 39        | 3              |
| cryo_em           | 11        | 1              |
| immunology        | 24        | 1              |
| population_genetics | 2       | 2              |

Source: `SELECT domain, COUNT(*) FROM workflows GROUP BY domain` and `workflow_chains`. Chains already have curated `example_queries` we should reuse verbatim as demo prompts.

### Selection rule (per domain)

1. **Prefer a curated chain** (`workflow_chains`) when one exists — they have validated step graphs and queries.
2. Within a domain pick the **3 most general / highest-impact tasks** (literature popularity proxies: gene-expression DE, GWAS, scRNA clustering, peak calling, variant calling, virtual screening, etc.).
3. Each demo must terminate at a **gold-standard-comparable artifact** (DEG table, peak BED, VCF, cluster labels, docked pose, IC50 prediction) — not just a process tree.

---

## 2. Per-domain demo set (top 3 each)

For each: **Research task → Workflow/chain → Gold-standard dataset → Validation metric.**

### A. Transcriptomics (bulk + array)
1. **Bulk RNA-seq DE + GSEA** — nf-core/rnaseq → DESeq2 → fgsea.
   - Gold: **GSE49712** (SEQC ERCC mix A/B, 23k DE genes truth set) — assert ≥90% recovery of ERCC truth.
2. **Time-course DE (edgeR/`edge`)** — chain "Time-Course Differential Expression with edge".
   - Gold: **GSE6377** (Hwang yeast cell cycle) — recover ≥80% of canonical cycle-regulated genes.
3. **RNA-seq Differential Transcript Usage (rnaseqDTU)** — Salmon → DRIMSeq + DEXSeq.
   - Gold: **Love 2018 rnaseqDTU Bioc vignette** simulated dataset — match published switch list ≥90%.

### B. Single-cell
1. **scRNA-seq QC → norm → cluster → UMAP** (curated chain).
   - Gold: **PBMC 10k 10x v3** — Azimuth labels as ground truth; require macro-F1 ≥0.85 on 7 main lineages.
2. **scRNA + ADT (CITE-seq) via scrapper** chain.
   - Gold: **10x CITE-seq PBMC 5k** — RNA+ADT joint clusters must reproduce CD4/CD8/Mono/NK/B (≥5 of 7 protein-defined gates).
3. **scRNA-seq → Pseudobulk DESeq2 (OSCA)** chain.
   - Gold: **Kang 2018 lupus PBMC (GSE96583)** — recover ISG signature in IFN-β-stim CD14 mono (≥70% of published DE list).

### C. Variant calling / WGS
1. **Germline SNV/indel** — nf-core/sarek (DeepVariant + GATK).
   - Gold: **GIAB HG002 chr20** — F1 ≥0.99 SNV, ≥0.95 indel vs v4.2.1 truthset.
2. **Somatic tumor/normal** — nf-core/sarek (Mutect2 + Strelka).
   - Gold: **SEQC2 HCC1395/BL** — recall ≥0.85 high-confidence SNV truthset.
3. **CNV consensus** — chain "CNV Detection — Multi-Method Consensus".
   - Gold: **HG002 GIAB CNV truth (v0.6)** — F1 ≥0.80 deletions ≥5kb.

### D. Epigenomics
1. **ChIP-seq → peaks → annotation → enrichment** (curated chain).
   - Gold: **ENCODE H3K27ac K562** — peak overlap ≥80% with ENCODE consensus.
2. **CUT&Tag w/ spike-in** chain (`SEACR`).
   - Gold: **Henikoff K562 H3K27me3 CUT&Tag** (GSE145187) — recover canonical polycomb domains.
3. **450k/EPIC methylation DMR** chain.
   - Gold: **Bioc `methylationArrayAnalysis` vignette** dataset — match vignette DMR list ≥95%.

### E. Variant interpretation / Genomics
1. **VCF → annotation → gene-summary** chain (VEP).
   - Gold: **ClinVar 2024-Q4 pathogenic subset** — annotation consequence agreement ≥99%.
2. **liftOver hg19↔hg38** chain.
   - Gold: **dbSNP common 1k random** — round-trip identity ≥99.5%.
3. **GWAS meta-analysis with bacon bias correction**.
   - Gold: **GIANT BMI 2018 sumstats subset** — corrected λ ∈ [0.95, 1.10].

### F. Proteomics
1. **mzML → quant → DE → QC** (curated chain).
   - Gold: **PXD002952 (UPS spike-in)** — recover ≥80% of true UPS proteins with FDR ≤5%.
2. **TMT 10-plex differential abundance** (nf-core/quantms).
   - Gold: **PXD005486** — DE direction match ≥90%.
3. **DIA-NN label-free** (top workflow in DIA bucket).
   - Gold: **CPTAC LFQ benchmark** — quant CV ≤20%.

### G. Drug discovery
1. **ADMET-Gated Virtual Screening** chain (RDKit + AdmetAI + Vina).
   - Gold: **DUD-E AKT1** — enrichment factor EF1% ≥10.
2. **Folding-Docking-Affinity ligand screen (Z02)**.
   - Gold: **PDBbind v2020 refined set 50 holdout** — Pearson r ≥0.6 on ΔG.
3. **RNA-seq DEGs → LINCS MoA Identification** chain.
   - Gold: **LINCS L1000 vorinostat** — top-5 MoA contains HDAC inhibitor.

### H. Pharmacology
1. **PBPK → Virtual Patient Dose Optimization** chain.
   - Gold: **midazolam human PK (Smith 2018)** — AUC within 2-fold of observed.
2. **PBPK Renal/Hepatic Impairment** chain.
   - Gold: **FDA renal-impairment guidance test case (gabapentin)** — CL change within ±25%.
3. **Phase II → Phase III Dose Justification** chain.
   - Gold: prove monotonic dose-response + ED50 within 30% of published value.

### I. Metagenomics
1. **Shotgun → assembly → CONCOCT binning → taxonomy** (curated chain).
   - Gold: **CAMI II low-complexity** — bin completeness ≥80%, contamination ≤5% (CheckM2).
2. **16S amplicon (QIIME2/DADA2)** — top transcriptomics-adjacent demand.
   - Gold: **Mock community HMP** — recover ≥95% of expected genera.
3. **AMR profiling (CARD/AMRFinder)**.
   - Gold: **CARD reference isolates** — gene recall ≥95%.

### J. Metabolomics
1. **LC-MS → multi-method differential abundance** (curated chain).
   - Gold: **MTBLS1 (NMR diabetes)** or **MTBLS136** — recover published biomarkers (≥70%).
2. **GC-MS XCMS peak picking**.
   - Gold: vendor mix standard — RT/m/z within tolerance ≥95%.
3. **Pathway mapping (mummichog)**.
   - Gold: paired LC-MS + transcriptomics dataset; pathway overlap ≥60%.

### K. Cryo-EM
1. **GPCR/membrane SPA** chain (CryoSPARC standard).
   - Gold: **EMPIAR-10061 (β-galactosidase)** — resolution ≤2.5 Å.
2. **cryoDRGN heterogeneity** (already piloted EMPIAR-10059).
   - Gold: ≥3 conformational states recovered.
3. **Tomography sub-volume averaging (Relion-Tomo)**.
   - Gold: **EMPIAR-10164 (HIV VLP)** — published resolution ±10%.

### L. Population genetics / GWAS
1. **TorchGWAS UDIP brain phenotypes (Z01)**.
   - Gold: **UKB published locus list** — recover top-10 hits within 1Mb.
2. **Single-cell GWAS for immune cell types (ZZ02)**.
   - Gold: **scDRS Yazar 2022** — overlap top-5 cell types.
3. **Burden / SKAT rare-variant** (`Variant Calling → Burden Testing`).
   - Gold: **gnomAD LoF + ClinVar** — LDLR for hypercholesterolemia recovered (p<5e-8).

### M. Immunology / immuno-oncology
1. **CyTOF mass cytometry** (curated chain).
   - Gold: **Bodenmiller 2012 PBMC stim** — recover stim-responsive populations (≥90%).
2. **TCR-seq clonotype tracking (MiXCR + immunarch)**.
   - Gold: **Adaptive ImmuneCODE COVID** — public clonotype hits ≥80%.
3. **Tumor-reactive T-cell pipeline (ZZ01)**.
   - Gold: neoantigen prediction overlap with published TIL response panel.

---

## 3. Demo deliverable per workflow

Every demo records the same artifact bundle (so they can ship as user-facing tutorials):

1. **Prompt** — taken verbatim from `workflow_chains.example_queries` where possible.
2. **Inputs** — public S3 paths (we already use `s3://biomate-cryo-data/...`, `s3://biomate-public-datasets/...` patterns).
3. **Expected workflow card** — name, phases, required params (predicted at routing time).
4. **Run** — on dev (`dev.biomate.ai`) via the canonical fixture user (`lifeifei163361@163.com`).
5. **Gold-standard check** — automated post-run script in `evaluation/tutorial_demos/<domain>_<n>.py` that loads the output and computes the metric above; pass/fail printed.
6. **Screenshots** — pre-run, running (≥1 phase active), completed, downloaded report. Saved to `frontend/e2e/screenshots/tutorial-demos/<domain>/`.
7. **Tutorial page** — short MDX under `frontend/client/src/tutorials/<domain>-<n>.mdx` rendered into the in-app help drawer.

---

## 3a. Shortlist — the 7 demos to build now (one per missing top domain)

Each one is the **#1 entry** from §2 for that domain (highest-impact, most recognizable gold standard):

| # | Domain | Demo | Gold standard | Pass metric |
|---|---|---|---|---|
| 1 | transcriptomics | Bulk RNA-seq DE + GSEA (nf-core/rnaseq → DESeq2 → fgsea) | GSE49712 / SEQC ERCC | ≥90% ERCC truth recovery |
| 2 | single_cell | scRNA-seq QC → cluster → UMAP (chain) | PBMC 10k v3 + Azimuth labels | macro-F1 ≥0.85 on 7 lineages |
| 3 | variant_calling | Germline SNV/indel (nf-core/sarek + DeepVariant) | GIAB HG002 chr20 | F1 ≥0.99 SNV / ≥0.95 indel |
| 4 | epigenomics | ChIP-seq → peaks → annotation → enrichment (chain) | ENCODE H3K27ac K562 | peak overlap ≥80% |
| 5 | proteomics | mzML → quant → DE → QC (chain) | PXD002952 UPS spike-in | ≥80% UPS recovery @ FDR 5% |
| 6 | metagenomics | Shotgun → assembly → CONCOCT → taxonomy (chain) | CAMI II low-complexity | bin completeness ≥80%, contam ≤5% |
| 7 | metabolomics | LC-MS multi-method DE (chain) | MTBLS136 | ≥70% published biomarkers |

Each demo ships as:
- 1 YouTube video added to `VIDEOS[]` in `tutorials.tsx`
- 1 gold-standard check script in `evaluation/tutorial_demos/<domain>.py`
- 1 short tutorial MDX (optional, only if the in-app help drawer lands)

## 4. Execution plan

**Phase 1 — Scaffold (1 day)**
- Create `evaluation/tutorial_demos/` harness: shared runner + `gold_standards.yaml` keyed by domain.
- Add `scripts/run_tutorial_demo.sh <domain>` that: prompts the chat API on dev → polls the run → downloads outputs → runs the gold check → emits pass/fail JSON.
- Seed with **transcriptomics (GSE49712)** as pilot — most-used domain, smallest dataset, fastest turnaround.

**Phase 2 — Record demos (7 days, 1/day)**
Order: transcriptomics → single_cell → variant_calling → epigenomics → proteomics → metagenomics → metabolomics. Each day:
1. Mirror gold dataset to `s3://biomate-public-datasets/tutorial-gold/<domain>/`.
2. Run end-to-end on dev with the canonical fixture user.
3. Record screen capture (same format as existing 4 videos: ~3–5 min, 2560×1440, show chat → workflow card → live run → after-run report).
4. Run gold-standard check; embed metric in video voiceover ("F1 = 0.992 vs GIAB truth").
5. Upload to YouTube, append to `VIDEOS[]` in `tutorials.tsx`.

**Phase 3 — Backlog**
Demos #2 and #3 per domain from §2 stay queued; revisit once the 7 gaps are filled.

---

## 5. Open questions for confirmation

1. **Scope cap** — 13 domains × 3 demos = 39 end-to-end runs. Each non-trivial (5–60 min compute, AWS Batch). Confirm we want the full set, or start with **top 6 domains** (transcriptomics, single_cell, variant_calling, drug_discovery, epigenomics, proteomics) = 18 demos.
2. **Gold-standard data hosting** — OK to mirror GIAB / ENCODE / EMPIAR / GEO subsets into `s3://biomate-public-datasets/tutorial-gold/`? Otherwise we depend on external availability at demo time.
3. **Pass threshold policy** — should a failed gold check (e.g. F1 0.97 vs target 0.99) block the tutorial from shipping, or just annotate it?
4. **Validation mode** — do gold-standard checks run as part of CI (regression guard) or only on-demand during recording?

Once confirmed I'll start Phase 1 with the two pilots.
