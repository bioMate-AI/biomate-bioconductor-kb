# H3 RNA-Protein Paired Training Set (CPTAC same-sample)

_Date: 2026-09-14 — training_eligible: **False**_

Close immune FM H3 (protein abundance) gap: same-sample transcriptome+proteome pairs (feature=mRNA -> label=protein abundance).

## Headline

- **1458 same-sample tumor RNA+protein pairs** assembled across **10/10 CPTAC cohorts** (all cohorts landed).
- **13,945,566 gene-level mRNA->protein training pairs** (feature=mRNA, label=protein abundance).
- Landed to S3: `s3://knowledge-datasets-1759951976/immunology_sc_corpus_broad/acquisitions_modalities/h3_rna_protein/` (10 x `*_h3_pairs.csv.gz` + `*_qc.json`).
- Grand total OPEN H3 pairs available (incl. cell lines): ~2,300-2,700 (1,458 CPTAC tumor + ~1,000-1,200 ProCan/Gygi cell lines, fetch-ready).

## The trainable signal: protein decouples from mRNA

Protein is NOT proportional to mRNA. Per-gene Spearman(mRNA,protein) across samples has cohort medians 0.29-0.50 (median-of-medians 0.41). On average ~35% of genes have corr<0.3 and ~7% are NEGATIVE; in PDAC/COAD ~50% of genes fall below 0.3. This residual (protein deviating from mRNA) IS the H3 trainable target -- a model predicting protein from mRNA must learn gene-specific post-transcriptional offsets.

- Cohort median Spearman(mRNA,protein) range: **0.2902–0.5015** (median-of-medians 0.41).
- Mean fraction of genes with corr<0.3: **0.355**; corr negative: **0.072**.

## Per-cohort QC

| Cohort | Cancer | Paired samples | Genes (both) | Gene-level pairs | Median ρ | P25–P75 ρ | %genes ρ<0.3 | %genes ρ<0 |
|---|---|--:|--:|--:|--:|--:|--:|--:|
| brca | Breast (BRCA) | 119 | 12,046 | 1,182,713 | 0.4362 | 0.2693–0.5907 | 29% | 3% |
| ccrcc | Clear-cell renal (CCRCC) | 185 | 11,254 | 1,676,543 | 0.4506 | 0.2288–0.6762 | 32% | 8% |
| coad | Colon (COAD) | 96 | 9,153 | 672,973 | 0.3047 | 0.146–0.475 | 49% | 9% |
| gbm | Glioblastoma (GBM) | 100 | 12,098 | 1,032,460 | 0.4358 | 0.2485–0.6187 | 31% | 5% |
| hnscc | Head & neck (HNSCC) | 158 | 11,580 | 1,500,207 | 0.4476 | 0.2397–0.6437 | 31% | 6% |
| lscc | Lung squamous (LSCC) | 207 | 12,757 | 2,239,456 | 0.5015 | 0.2849–0.6978 | 26% | 6% |
| luad | Lung adeno (LUAD) | 213 | 12,429 | 2,200,257 | 0.4094 | 0.2108–0.5891 | 35% | 8% |
| ov | Ovarian (OV) | 82 | 10,589 | 687,334 | 0.3934 | 0.2238–0.5571 | 35% | 6% |
| pdac | Pancreatic (PDAC) | 181 | 11,416 | 1,608,637 | 0.2902 | 0.1222–0.4741 | 51% | 11% |
| ucec | Uterine (UCEC) | 117 | 11,948 | 1,144,986 | 0.434 | 0.2409–0.6323 | 32% | 6% |
| **TOTAL** | 10 cohorts | **1458** | — | **13,945,566** | 0.41 | — | — | — |

## Data provenance & schema

- RNA source: **bcm** (Baylor, STAR/RSEM UQ-log2). Proteomics source: **umich** (U-Michigan, TMT MD-normalized log2).
- Table schema: `cancer, source, sample, gene, mRNA, protein`. Format: gzip CSV (.csv.gz); mRNA=log2 UQ RSEM (bcm), protein=log2 TMT reference-intensity-normalized abundance (umich).
- Method: cptac Python package (PayneLab). Per cohort: same-sample intersection of transcriptomics (bcm/Baylor) x proteomics (umich/U-Michigan), aligned to gene symbol; dup gene columns mean-collapsed; compact long table (cancer,source,sample,gene,mRNA,protein) written gzip-CSV; one cohort at a time with cptac cache cleared between cohorts (disk budget ~3GB).

## Total available across all sources

- **CPTAC (assembled):** 1458 tumor pairs — DONE (all 10 cohorts landed).
- **ProCan-DepMap-Sanger:** ~900+ cell lines — PXD030304 SWATH-DIA matrix + DepMap RNA join (fetch-ready, not downloaded).
- **Gygi/CCLE + DepMap:** ~375 cell lines — Nusinow 2020 TMT table + DepMap TPM join (fetch-ready, not downloaded).
- ProCan (~949) and Gygi (~375) overlap; unique cell-line pairs ~1,000-1,200. Grand total open H3 pairs ~2,300-2,700 (1,458 CPTAC tumor + ~1,000-1,200 cell-line).

## Notes

- cptac bcm-proteomics loader is broken in this version (missing Database_ID); used umich proteomics for all cohorts.
- coad umich mapping file missing from repo size-index; patched cptac download_tools.get_data to fetch size via HTTP HEAD / single-thread fallback.
- n_paired_samples = same-sample intersection of RNA and protein tables (tumor samples).
- Correlations are Spearman per gene across samples, computed only on genes with >=10 samples having both modalities.

## S3 locations

- brca: `s3://knowledge-datasets-1759951976/immunology_sc_corpus_broad/acquisitions_modalities/h3_rna_protein/brca_h3_pairs.csv.gz`
- ccrcc: `s3://knowledge-datasets-1759951976/immunology_sc_corpus_broad/acquisitions_modalities/h3_rna_protein/ccrcc_h3_pairs.csv.gz`
- coad: `s3://knowledge-datasets-1759951976/immunology_sc_corpus_broad/acquisitions_modalities/h3_rna_protein/coad_h3_pairs.csv.gz`
- gbm: `s3://knowledge-datasets-1759951976/immunology_sc_corpus_broad/acquisitions_modalities/h3_rna_protein/gbm_h3_pairs.csv.gz`
- hnscc: `s3://knowledge-datasets-1759951976/immunology_sc_corpus_broad/acquisitions_modalities/h3_rna_protein/hnscc_h3_pairs.csv.gz`
- lscc: `s3://knowledge-datasets-1759951976/immunology_sc_corpus_broad/acquisitions_modalities/h3_rna_protein/lscc_h3_pairs.csv.gz`
- luad: `s3://knowledge-datasets-1759951976/immunology_sc_corpus_broad/acquisitions_modalities/h3_rna_protein/luad_h3_pairs.csv.gz`
- ov: `s3://knowledge-datasets-1759951976/immunology_sc_corpus_broad/acquisitions_modalities/h3_rna_protein/ov_h3_pairs.csv.gz`
- pdac: `s3://knowledge-datasets-1759951976/immunology_sc_corpus_broad/acquisitions_modalities/h3_rna_protein/pdac_h3_pairs.csv.gz`
- ucec: `s3://knowledge-datasets-1759951976/immunology_sc_corpus_broad/acquisitions_modalities/h3_rna_protein/ucec_h3_pairs.csv.gz`
