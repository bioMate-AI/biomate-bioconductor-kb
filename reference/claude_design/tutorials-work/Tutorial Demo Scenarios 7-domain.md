# Tutorial Demo Scenarios — 7-Domain Gap-Fill

**For:** Claude design / engineering handoff (videos for `/tutorials`)
**Builds on:** existing `Bioconductor Tutorial Scenarios.md` and the 4 videos already in `frontend/client/src/pages/tutorials.tsx`
**What this adds:** Seven new tutorial demos, one per top BioMate domain currently uncovered on the live tutorials page.
**Hard constraint:** every scenario is anchored to a **real chain in `workflow_chains`** plus the **indexed workflows it composes** (`workflow_id` references are real DB rows). Inputs / QC gates / outputs / pass metrics are all aligned to a **peer-reviewed gold-standard dataset** so the demo can be auto-validated, not just "rendered."

Format follows `Bioconductor Tutorial Scenarios.md` (plan checklist, tape events, phase trace, QC gates, gold standard, validation metric).

---

## Coverage map vs. live `/tutorials`

| Live video | Domain |
|---|---|
| `bpG0IWrwN5g` | platform overview |
| `C4gQD-xbHnQ` | cryo_em (CryoSPARC SPA) |
| `F2DgmBa5gq8` | reporting (cross-domain) |
| `IDcICWmB0Oo` | drug_discovery + pharmacology (IND §2.6) |

**Gaps filled by this doc:** transcriptomics, single_cell, variant_calling, epigenomics, proteomics, metagenomics, metabolomics.

---

## Shared scaffolding

Every scenario uses the same UI tape structure (matches `Bioconductor Tutorial Scenarios.md`):
- `planShow` → `planUpdate` items
- `phaseUpdate` per phase card
- `qcGate` events whenever a real QC gate fires
- `showCard: 'findings'` at the end carrying the gold-standard metric

**Validation harness:** `evaluation/tutorial_demos/<slug>.py` loads the run's output S3 prefix and asserts the pass metric. The metric value gets piped into the voiceover script (`reference/claude_design/tutorials-work/generate_vo.py`) so the video literally says *"F1 = 0.992 vs GIAB truth"*, not a hand-waved "looks correct."

**E2E fixture for recording:** `lifeifei163361@163.com` (per `CLAUDE.md` E2E test user rule), dev env `https://dev.biomate.ai`.

---

## Scenario T1 — Bulk RNA-seq DE + GSEA (`tut_rnaseq_de`)

### Real BioMate chain

- Chain: `bulk_rnaseq_de_analysis` (display: "Bulk RNA-seq Differential Expression Analysis")
- Steps (real `workflow_id`s):
  1. `nf-core/rnaseq` (id **1491**) — alignment + Salmon quant, params `aligner=star_salmon`, `genome=GRCh38`
  2. `nf-core/differentialabundance` (id **1497**) — DESeq2, params `method=deseq2`
  3. `clusterprofiler_gene_set_enrichment_analysis` (id **12956**) — GO + KEGG + Reactome

### Prompt (taken from `example_queries`)

> "Run nf-core rnaseq then differential expression and GSEA"

### Inputs

- **Dataset:** SEQC / MAQC-III Consortium `GSE49712` (10 samples, mix A vs mix B, ERCC spike-ins as ground truth).
  - Mirrored to `s3://biomate-public-datasets/tutorial-gold/transcriptomics/GSE49712/{fastq/,samplesheet.csv,contrasts.csv}`.
- `sample_sheet`: 5× A, 5× B.
- `contrast`: `B_vs_A`.

### Plan checklist

```js
[
  { id: 'p1', title: 'Fetch FASTQ + sample sheet from S3',  status: 'pending', est_s: 15 },
  { id: 'p2', title: 'Run nf-core/rnaseq (STAR + Salmon)',  status: 'pending', est_s: 1500 },
  { id: 'p3', title: 'Run nf-core/differentialabundance',  status: 'pending', est_s: 120 },
  { id: 'p4', title: 'GSEA via clusterProfiler',           status: 'pending', est_s: 90 },
  { id: 'p5', title: 'Generate After-run report',          status: 'pending', est_s: 30 },
]
```

### QC gates (must fire in the demo)

| Gate | Source | Pass threshold |
|---|---|---|
| MultiQC per-sample STAR uniquely-mapped ≥ 70% | `nf-core/rnaseq` multiqc | all 10 ≥ 70% |
| Salmon mapping rate ≥ 70% | `nf-core/rnaseq` multiqc | all 10 ≥ 70% |
| DESeq2 sample-distance heatmap = 2 clear clusters | `nf-core/differentialabundance` | A and B separable |

### Gold-standard validation

- **Truth set:** ERCC ground-truth fold-changes (Mix A vs Mix B, 4 sub-pools with known ratios 4:1, 1:1, 0.67:1, 0.5:1).
- **Metric:** ERCC truth recovery — fraction of ERCC transcripts whose sign(log2FC) and direction match the spike-in ratio.
- **Pass:** ≥ **90%** truth recovery; AUC-ROC of `padj` vs ERCC class ≥ **0.95**.
- **Anchor publication:** SEQC/MAQC-III Consortium, *Nat Biotechnol* 32:903 (2014).
- **Validator:** `evaluation/tutorial_demos/transcriptomics.py` reads `de_results.tsv`, joins to ERCC truth, computes recovery + AUC.

### Findings card

- Headline: `8,427 DE genes (FDR < 0.05); ERCC truth recovery 92.1%`
- Bullets:
  - "Aligned 10 samples with STAR/Salmon; mean uniquely-mapped = 87%"
  - "DESeq2 contrast B_vs_A; sample-distance heatmap shows clean A/B split"
  - "GSEA top hit: cell-cycle (KEGG) padj 1.2e-12"
  - "ERCC truthset recovery 92.1% (target ≥ 90%) — matches SEQC/MAQC-III benchmark"

---

## Scenario T2 — scRNA-seq QC → cluster → annotate → DA (`tut_scrna_pbmc`)

### Real BioMate chain

- Chain: `single_cell_multimodal_analysis`
- Steps:
  1. `scrna_qc_normalization` — QC + log-norm + HVG
  2. `Create Harmony Embeddings Scrna` — Harmony batch integration
  3. `Annotate Celltype Scrna` — cluster + reference-based annotation
  4. `mfa` — pseudotime (skipped for static PBMC demo, hidden phase)
  5. `milor_da_glmm_random_effects` — Milo DA (left in for cross-condition demo; degenerate on single-condition PBMC, surfaced as QC-skip)

### Prompt

> "Run single-cell analysis from Cell Ranger output"

### Inputs

- **Dataset:** 10x Genomics PBMC 10k v3 (`pbmc_10k_v3_filtered_feature_bc_matrix.h5`).
- Mirror: `s3://biomate-public-datasets/tutorial-gold/single_cell/pbmc_10k_v3/`.
- `sample_metadata`: 1 donor, 1 condition (single-batch).

### Plan checklist

```js
[
  { id: 'p1', title: 'Load Cell Ranger H5 (10k cells)',         status: 'pending', est_s: 20 },
  { id: 'p2', title: 'QC + normalization (Scrublet, scran)',   status: 'pending', est_s: 90 },
  { id: 'p3', title: 'Harmony batch integration (single batch — pass-through)', status: 'pending', est_s: 30 },
  { id: 'p4', title: 'Cluster + annotate (Azimuth reference)',  status: 'pending', est_s: 120 },
  { id: 'p5', title: 'Generate UMAP + cell-type marker report', status: 'pending', est_s: 40 },
]
```

### QC gates

| Gate | Source | Pass threshold |
|---|---|---|
| Doublet rate ≤ 8% | Scrublet | ≤ 8% |
| Median genes/cell ≥ 1,500 | QC | ≥ 1,500 |
| Mitochondrial % median ≤ 15% | QC | ≤ 15% |
| Milo DA skipped (1 condition) | Milo | gracefully no-op, surfaced as advisory |

### Gold-standard validation

- **Truth labels:** Azimuth PBMC reference (level-1) — CD4 T, CD8 T, NK, B, CD14 Mono, CD16 Mono, DC.
- **Metric:** macro-F1 of predicted cluster labels vs Azimuth labels on the 7 main lineages.
- **Pass:** macro-F1 ≥ **0.85**.
- **Anchor publication:** Hao et al., *Cell* 184:3573 (2021).
- **Validator:** `evaluation/tutorial_demos/single_cell.py` runs Azimuth mapping on the final `h5ad_final`, computes macro-F1.

### Findings card

- Headline: `9,841 cells, 7 cell types annotated; macro-F1 vs Azimuth = 0.89`
- Bullets:
  - "Filtered 159 doublets (Scrublet)"
  - "Resolution 0.6 → 11 clusters → 7 lineages"
  - "macro-F1 0.89 vs Azimuth PBMC reference (target ≥ 0.85)"
  - "Milo DA skipped — single batch, single condition; advisory only"

---

## Scenario T3 — Germline variant calling (`tut_variant_giab`)

### Real BioMate chain

- Chain: `bioc_variant_annotation_workflow` (display: "Variant Annotation & Filtering (Bioc Workflow `variants`)")
- Steps:
  1. `nf-core/sarek` — alignment + DeepVariant + GATK HaplotypeCaller (germline)
  2. `BIOC_VariantAnnotation` — annotate consequences against TxDb.Hsapiens
  3. `variantfiltering` — filter by consequence + pop-freq (gnomAD AF ≤ 0.01)

### Prompt

> "Variant calling annotation filtering on this WGS sample"

### Inputs

- **Dataset:** GIAB HG002 (NA24385), **chr20 only** to keep the run ≤ 60 min.
- Mirror: `s3://biomate-public-datasets/tutorial-gold/variant_calling/giab_hg002_chr20/{HG002.chr20.bam, HG002.chr20.bam.bai, samplesheet.tsv}`.
- Reference: `GRCh38.chr20.fa`.

### Plan checklist

```js
[
  { id: 'p1', title: 'Fetch GIAB HG002 chr20 BAM',       status: 'pending', est_s: 20 },
  { id: 'p2', title: 'Run sarek (DeepVariant + GATK)',   status: 'pending', est_s: 1800 },
  { id: 'p3', title: 'Annotate with VariantAnnotation',  status: 'pending', est_s: 120 },
  { id: 'p4', title: 'Filter by consequence + gnomAD AF',status: 'pending', est_s: 60 },
  { id: 'p5', title: 'Generate after-run report',        status: 'pending', est_s: 30 },
]
```

### QC gates

| Gate | Source | Pass threshold |
|---|---|---|
| Mean coverage ≥ 30× | mosdepth | ≥ 30× on chr20 |
| Ti/Tv ratio ∈ [2.0, 2.1] | bcftools stats | ∈ [2.0, 2.1] |
| Het/hom ratio ∈ [1.4, 2.0] | bcftools | ∈ [1.4, 2.0] |

### Gold-standard validation

- **Truth set:** GIAB HG002 v4.2.1 high-confidence VCF + BED (chr20 subset).
- **Metric:** `hap.py` F1 SNV + indel.
- **Pass:** SNV F1 ≥ **0.99**, indel F1 ≥ **0.95**.
- **Anchor publication:** Wagner et al., *Cell Genomics* 2:100129 (2022); Zook et al., *Sci Data* 3:160025 (2016).
- **Validator:** `evaluation/tutorial_demos/variant_calling.py` runs `hap.py` against the truth VCF restricted to the high-confidence BED.

### Findings card

- Headline: `chr20 — SNV F1 0.994 · indel F1 0.962 vs GIAB v4.2.1`
- Bullets:
  - "DeepVariant + GATK consensus; 109,873 PASS variants on chr20"
  - "Ti/Tv 2.04, het/hom 1.62 — all QC gates pass"
  - "F1 above target (0.99 SNV, 0.95 indel)"

---

## Scenario T4 — ChIP-seq → peaks → annotation → enrichment (`tut_chipseq_k562`)

### Real BioMate chain

- Chain: `bioc_chipseq_annotation_v2`
- Steps:
  1. `nf-core/chipseq` (pre-step, called before chain) — bwa-mem + MACS2 narrow peaks
  2. `BIOC_CHIPSEEKER` — annotate peaks, `tss_region=[-3000,3000]`, `organism=hg38`
  3. `BIOC_CLUSTERPROFILER` — `ontology=BP`, `organism=hsa`

### Prompt

> "Annotate my ChIP-seq peaks and run pathway enrichment"

### Inputs

- **Dataset:** ENCODE K562 H3K27ac (`ENCFF301TVL` BAM, `ENCFF038FKY` input BAM).
- Mirror: `s3://biomate-public-datasets/tutorial-gold/epigenomics/encode_k562_h3k27ac/`.
- Pre-computed consensus peaks for the "Bioc-only" path: `ENCFF044JNJ.bed`.

### Plan checklist

```js
[
  { id: 'p1', title: 'Fetch BAM + input BAM',                  status: 'pending', est_s: 30 },
  { id: 'p2', title: 'Call peaks with MACS2 (q=0.01, narrow)', status: 'pending', est_s: 300 },
  { id: 'p3', title: 'Annotate peaks with ChIPseeker',         status: 'pending', est_s: 60 },
  { id: 'p4', title: 'GO BP enrichment via clusterProfiler',   status: 'pending', est_s: 60 },
  { id: 'p5', title: 'Generate annotation + dotplot report',   status: 'pending', est_s: 30 },
]
```

### QC gates

| Gate | Source | Pass threshold |
|---|---|---|
| FRiP score ≥ 0.20 | MACS2 / ChIPQC | ≥ 0.20 (active mark) |
| NSC ≥ 1.05 | phantompeakqualtools | ≥ 1.05 |
| Peak count ∈ [25k, 80k] | MACS2 | within range for K562 H3K27ac |

### Gold-standard validation

- **Truth set:** ENCODE consensus narrowPeak file for the same biosample (`ENCFF044JNJ.bed.gz`).
- **Metric:** Jaccard overlap on peak intervals; fraction of called peaks with ≥ 1 bp overlap.
- **Pass:** ≥ **80%** of called peaks overlap ENCODE consensus.
- **Anchor publication:** ENCODE Consortium, *Nature* 583:699 (2020).
- **Validator:** `evaluation/tutorial_demos/epigenomics.py` bedtools-intersects called peaks vs consensus.

### Findings card

- Headline: `47,331 H3K27ac peaks · 83.4% overlap ENCODE consensus`
- Bullets:
  - "FRiP 0.27, NSC 1.18 — quality gates green"
  - "Top GO BP: regulation of transcription by RNA-Pol II (padj 2.8e-30)"
  - "Peak overlap above 80% target → reproduces ENCODE call set"

---

## Scenario T5 — Proteomics LFQ (`tut_proteomics_ups`)

### Real BioMate chain

- Chain: `bioc_proteomics_de_v2`
- Steps:
  1. `BIOC_MSNBASE` — load + label-free quant
  2. `BIOC_LIMMA` — DE, `adj_method=BH`, `lfc_threshold=1.0`

### Prompt

> "Bioconductor proteomics pipeline — label-free protein DE analysis"

### Inputs

- **Dataset:** ProteomeXchange `PXD002952` — UPS1 protein standards spiked into yeast lysate at known ratios.
- Mirror: `s3://biomate-public-datasets/tutorial-gold/proteomics/PXD002952/{mzml/,samplesheet.csv}`.

### Plan checklist

```js
[
  { id: 'p1', title: 'Load mzML files (MSnBase)',            status: 'pending', est_s: 60 },
  { id: 'p2', title: 'Feature detection + alignment',         status: 'pending', est_s: 300 },
  { id: 'p3', title: 'Protein quantification (label-free)',   status: 'pending', est_s: 120 },
  { id: 'p4', title: 'limma DE + BH correction',              status: 'pending', est_s: 60 },
  { id: 'p5', title: 'Volcano + QC report',                   status: 'pending', est_s: 30 },
]
```

### QC gates

| Gate | Source | Pass threshold |
|---|---|---|
| Identification rate ≥ 60% PSMs | MSnBase | ≥ 60% |
| Median CV across replicates ≤ 20% | quant table | ≤ 20% |
| Missingness ≤ 30% per protein | quant table | ≤ 30% |

### Gold-standard validation

- **Truth set:** the 48 UPS1 proteins are known DE; all others (yeast background) are known non-DE.
- **Metric:** UPS1 recall at FDR ≤ 5%; yeast-background false-positive rate.
- **Pass:** ≥ **80%** of UPS1 proteins recovered at FDR ≤ 5%; yeast FPR ≤ 5%.
- **Anchor publication:** Cox et al., *Mol Cell Proteomics* 13:2513 (2014) (MaxLFQ).
- **Validator:** `evaluation/tutorial_demos/proteomics.py` joins `de_proteins_csv` to UPS1 truth, computes recall + FPR.

### Findings card

- Headline: `42/48 UPS1 proteins recovered at FDR 5% (87.5%); yeast FPR 3.1%`
- Bullets:
  - "ID rate 71%, median CV 11% — gates green"
  - "limma eBayes contrast `concentration_high_vs_low`"
  - "UPS1 recall 87.5% (target ≥ 80%) → reproduces MaxLFQ benchmark"

---

## Scenario T6 — Shotgun metagenomics → MAGs (`tut_metagenome_cami`)

### Real BioMate chain

- Chain: `shotgun_metagenomics_to_mag`
- Steps:
  1. `Fasta Binning Concoct` — contig binning
  2. `Mmseqs Contig Taxonomy` — taxonomy assignment
  3. `PathoStat` — differential abundance summary

### Prompt

> "MAG recovery with binning and taxonomy assignment"

### Inputs

- **Dataset:** CAMI II low-complexity gut subset (5 samples).
- Mirror: `s3://biomate-public-datasets/tutorial-gold/metagenomics/cami2_low_complexity/{contigs.fa,coverage.tsv,sample_metadata.csv}`.

### Plan checklist

```js
[
  { id: 'p1', title: 'Fetch assembled contigs + coverage',     status: 'pending', est_s: 30 },
  { id: 'p2', title: 'CONCOCT binning',                         status: 'pending', est_s: 600 },
  { id: 'p3', title: 'CheckM2 completeness / contamination',   status: 'pending', est_s: 300 },
  { id: 'p4', title: 'MMseqs2 taxonomy assignment',             status: 'pending', est_s: 240 },
  { id: 'p5', title: 'PathoStat differential abundance',        status: 'pending', est_s: 60 },
]
```

### QC gates

| Gate | Source | Pass threshold |
|---|---|---|
| Bin completeness ≥ 80% | CheckM2 | per high-quality MAG |
| Contamination ≤ 5% | CheckM2 | per high-quality MAG |
| Taxonomy assigned to ≥ 70% bins | MMseqs2 | ≥ 70% |

### Gold-standard validation

- **Truth set:** CAMI II gold-standard taxonomy + binning labels.
- **Metric:** AMBER-style bin-level F1 vs CAMI gold bins; fraction of high-quality MAGs (compl ≥ 80, contam ≤ 5).
- **Pass:** ≥ **70%** of CAMI II reference genomes recovered as high-quality MAGs.
- **Anchor publication:** Meyer et al., *Nat Methods* 19:429 (2022).
- **Validator:** `evaluation/tutorial_demos/metagenomics.py` runs `amber.py` against CAMI gold mapping.

### Findings card

- Headline: `38 MAGs · 27 high-quality (compl ≥ 80, contam ≤ 5) · 71% CAMI II recovery`
- Bullets:
  - "CONCOCT yielded 38 bins; CheckM2 keeps 27"
  - "MMseqs2 taxonomy at genus rank for 89% of bins"
  - "Recovery 71% above target 70% → reproduces CAMI II benchmark"

---

## Scenario T7 — LC-MS metabolomics consensus DE (`tut_metabolomics_mtbls`)

### Real BioMate chain

- Chain: `lcms_metabolomics_consensus`
- Steps:
  1. `xcms` — peak picking + alignment, `method=centWave`
  2. `camera` — isotope/adduct annotation
  3. `biosigner` — consensus feature selection across PLS-DA, RF, SVM

### Prompt

> "Untargeted metabolomics multi-method analysis"

### Inputs

- **Dataset:** MetaboLights `MTBLS136` (urine LC-MS, Thévenot 2015, age × gender × BMI design).
- Mirror: `s3://biomate-public-datasets/tutorial-gold/metabolomics/MTBLS136/{mzml/,sample_metadata.csv}`.
- `phenotype_column`: `gender`.

### Plan checklist

```js
[
  { id: 'p1', title: 'Fetch mzML files (MTBLS136)',              status: 'pending', est_s: 30 },
  { id: 'p2', title: 'xcms centWave peak picking + alignment',   status: 'pending', est_s: 600 },
  { id: 'p3', title: 'CAMERA isotope + adduct annotation',       status: 'pending', est_s: 120 },
  { id: 'p4', title: 'biosigner consensus (PLS-DA + RF + SVM)',  status: 'pending', est_s: 180 },
  { id: 'p5', title: 'Annotation + biomarker report',            status: 'pending', est_s: 30 },
]
```

### QC gates

| Gate | Source | Pass threshold |
|---|---|---|
| QC sample CV ≤ 30% | xcms QC | ≥ 70% of features ≤ 30% CV |
| Peak count ∈ [3k, 15k] | xcms | within range for urine LC-MS |
| biosigner classifier accuracy ≥ 0.70 (CV) | biosigner | ≥ 0.70 |

### Gold-standard validation

- **Truth set:** the gender-discriminating features reported in Thévenot et al. 2015 supplementary (steroid metabolites including testosterone glucuronide, androsterone sulfate, etc.).
- **Metric:** recall of published gender-discriminating features in the consensus signature.
- **Pass:** ≥ **70%** of published biomarkers recovered.
- **Anchor publication:** Thévenot et al., *J Proteome Res* 14:3322 (2015).
- **Validator:** `evaluation/tutorial_demos/metabolomics.py` matches `differential_features.tsv` to the published feature list (m/z + RT tolerance).

### Findings card

- Headline: `9 of 12 published gender-discriminating features recovered (75%)`
- Bullets:
  - "5,412 features after CAMERA grouping; QC-CV median 14%"
  - "biosigner consensus selected 23 features across 3 classifiers"
  - "Recall 75% above target 70% → reproduces Thévenot 2015 signature"

---

## Validation harness layout

```
evaluation/tutorial_demos/
  __init__.py
  runner.py                # shared API: submit prompt → poll run → download outputs
  gold_standards.yaml      # dataset paths + pass thresholds for all 7
  transcriptomics.py       # ERCC truth recovery
  single_cell.py           # Azimuth macro-F1
  variant_calling.py       # hap.py vs GIAB
  epigenomics.py           # bedtools vs ENCODE consensus
  proteomics.py            # UPS1 recall + yeast FPR
  metagenomics.py          # AMBER vs CAMI II gold
  metabolomics.py          # m/z+RT match to Thévenot 2015

scripts/run_tutorial_demo.sh <slug>   # one-shot: harness + gate + voiceover-ready JSON
```

Each validator emits a JSON like:
```json
{ "slug": "transcriptomics", "metric_name": "ercc_recovery",
  "metric_value": 0.921, "threshold": 0.90, "pass": true,
  "anchor_publication": "SEQC/MAQC-III 2014" }
```

The voiceover script `generate_vo.py` (already used for CryoSPARC/IND demos) interpolates `metric_value` + `anchor_publication` so every recorded video states the validated number on screen.

---

## Acceptance checklist (per tutorial)

- [ ] Chain + workflow IDs match `workflow_chains` and `workflows` in the production DB
- [ ] Gold-standard dataset mirrored to the canonical S3 prefix
- [ ] All listed QC gates fire in the live run (visible in workflow panel `data-status` transitions)
- [ ] Validator JSON `pass: true`, value above threshold
- [ ] Screen recording matches existing 4 videos in style (2560×1440, ≤ 5 min)
- [ ] `VIDEOS[]` entry added to `frontend/client/src/pages/tutorials.tsx` with the published YouTube ID

When all 7 check, this doc closes the per-domain tutorial gap on the live site.
