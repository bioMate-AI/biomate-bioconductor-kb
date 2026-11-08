# H2 (Translation Efficiency) — Matched Ribo-seq + RNA-seq Pairing Inventory

**Date:** 2026-09-13 · **training_eligible = false** (inventory + TE tables, not yet QC'd/ingested)
**TE = ribosome-protected-fragment count / mRNA count, per gene.** Computed as `log2((RPF_CPM+0.5)/(mRNA_CPM+0.5))` per sample, genes filtered to mean mRNA ≥ 10.
**S3 root:** `s3://knowledge-datasets-1759951976/immunology_sc_corpus_broad/acquisitions_modalities/riboseq_h2/`

This closes the H2 gap that the registry logged as "~zero held." The gap was a *holdings* gap, not an *existence* gap — TE tables are now HELD.

---

## Bottom line

| Metric | Value |
|---|---|
| **Generic-human matched Ribo+RNA pairs (TE-ready), HELD** | **1,282** (RiboBase, uniformly reprocessed) |
| Generic-human TE contexts in the held plain table | 77 cell-line/tissue contexts × 11,150 genes |
| **Immune-specific paired studies identified** | **16** |
| **Immune-specific TE tables HELD (computed/ready-made)** | **3** studies, **23 paired samples** |
| Immune-specific paired samples fetch-ready (identified, not held) | ~110 across 13 more studies |
| **H2 pretraining feasible now?** | **YES on GENERIC human data; immune fine-tune/eval feasible on a small held anchor set** |

---

## What is HELD on S3 (bytes landed)

### 1. RiboBase generic-human TE tables — `ribobase_zenodo_10373032/`
Source: Zenodo **10373032** (RiboBase intermediate TE, Cenik lab / massiveNGSpipe; Genome Biol 2024, PMC11326257). Uniform reprocessing → low batch.

| File | Size | Content |
|---|---|---|
| `human_TE_cellline_all_plain.csv` | 15.7 MB | per-gene TE (CLR) × **77 contexts** × 11,150 genes — plain CSV, immediately usable |
| `human_flatten_te_clr.rda` | 90.2 MB | per-GSM-sample TE (genes × ~1,282 GSM ids) |
| `human_flatten_ribo_clr.rda` | 34.1 MB | ribosome-profiling CLR counts (genes × GSM) |
| `human_flatten_rna_clr.rda` | 33.8 MB | matched RNA-seq CLR counts (genes × GSM) |

**Immune contexts present in the plain table** (baseline/resting, no stimulus): Primary CD4+ T-cells, primary macrophages, THP-1, K562, HSB2, Molt-3, MM1.S, MOLM-13, LCL, Mutu.
**Size-gated / skipped:** `human_RNA_rho_new.rda`, `human_TE_rho.rda`, `mouse_*_rho.rda` (~944–993 MB each; gene–gene covariation matrices, not per-sample TE, not needed).

### 2. Immune-stimulus TE tables — `immune_geo_TE/`

| File | Study | Organism | Cell / stimulus | Paired N | Genes |
|---|---|---|---|---|---|
| `TE_GSE254157_254230_humanTcell.csv` | GSE254157(RNA)+GSE254230(RPF) | **human** | Jurkat **T-cell activation** 0/5/12h | **9** | 11,759 |
| `TE_GSE168476_mouseCD8T.csv` | GSE168476 | mouse | **CD8 memory T**, TCR activation T0/2hr | 5 | 18,120 |
| `provenance/GSE99787_TE_mouseBMDM_LPS.xlsx` | GSE99787 | mouse | **BMDM macrophage, LPS** 0/1/2/4/6h | 9 | ready-made |

Raw count tables kept under `immune_geo_TE/provenance/` for reproducibility; all raw intermediates deleted locally after upload.

---

## Immune-specific paired inventory (identified)

High confidence = both modalities confirmed on same samples + clear immune stimulus.

| GSE | Org | Cell | Stimulus | Paired N | TE table | Conf |
|---|---|---|---|---|---|---|
| GSE254157+GSE254230 | human | Jurkat T | T-cell activation 0/5/12h | 9 | **HELD-computed** | high |
| GSE99787 | mouse | BMDM | **LPS** 0–6h | 9 | **HELD ready-made** | high |
| GSE168476 | mouse | CD8 mem T | TCR T0/2hr | 5 | **HELD-computed** | high |
| GSE281922 | mouse | macrophage | LPS activation | 11 | GEO TXT (fetch) | high |
| GSE60930 | mouse | RAW264 mac | LPS 30min | 6 | GEO (fetch) | high |
| GSE240674 | **human** | monocyte/mac | endotoxin tolerance (LPS/ET) | 18 | RNA TPM up; RPF needs GSM fetch | med |
| GSE108331+108333 | mouse | dendritic cell | DC activation (Mettl3 m6A) | 4 | GEO (fetch; title=TE) | high |
| GSE184909 | mouse | T cell | early activation (tRNA-m1A) | 12 | GEO CSV/XLSX (fetch) | high |
| GSE83351 | mouse | T cell | activation time course | 7 | GEO TXT (fetch) | high |
| GSE160328 | mouse | CD4 T | activation (RNMT) | 16 | GEO SuperSeries (fetch) | high |
| GSE94698 | mouse | Th1 | Th1 stim | 5 | GEO (fetch) | med |
| GSE96076 | mouse | T cell | activation / anti-viral (ZFP36) | 12 | GEO SuperSeries | med |
| GSE120762 | mouse | macrophage | mucosal immunity | 8 | GEO SuperSeries | med |
| GSE286704 | mouse | melanoma+immune | RIG-I anti-tumour (t6A) | 6 | GEO (fetch) | med |
| GSE148245 | human | epithelial | viral infection (host translation) | 2 | GEO; infection-adjacent | med |
| GSE216912 | human | CD8 T | mitoRibo-seq (fate) | 6 | mito TE, different meaning | low |

Not found: a true **NK-cell** or usable **B-cell** paired Ribo+RNA study (GSE133934 B-cell is ribo-only, n=2).

---

## Generic pretraining pools identified (larger, not held)

| Resource | Ribo | Matched RNA | Note |
|---|---|---|---|
| **RiboBase** | — | **1,282 human matched** | TE tables **HELD**; ribo files via CenikLab request |
| **RPFdb v3.0** | 5,018 | 2,343 | 496 studies / 34 species; host timed out from sandbox; has Download + TE |
| **RiboSeq Data Portal (RDP)** | 14,840 | — | 969 studies; REST API + CLI; host timed out from sandbox |
| **TEDD** | 738 | 726 | 1,518 human samples / 143 projects; per-transcript TE/TR/EVI download; no immune conditions flagged |

RPFdb.org and rdp.ucc.ie were **unreachable from this sandbox** (connection timeout) — they are fetch-ready from a networked host but not held here.

---

## Feasibility verdict

- **H2 generic pretraining: FEASIBLE NOW.** The RiboBase held set gives ~1,282 matched human samples across 77 contexts (~11k genes) with uniform reprocessing — enough to pretrain the sequence/codon→TE transform. Larger pools (RPFdb 2,343 / RDP 14,840) are identified and fetch-ready to scale.
- **H2 immune-specific: FEASIBLE for fine-tune / held-out eval, but on a SMALL held anchor** (23 paired samples / 3 studies held; ~110 more paired samples across 13 studies identified and cheap to fetch). Best held human immune anchor = **GSE254157/254230 T-cell activation (9)**; best held stimulus anchor = **GSE99787 BMDM-LPS (9)**.

## Caveats (honest)
- **training_eligible = false** — not yet QC'd/ingested into the cache; earns a slot only after `qc.py` + a measured objective improvement.
- **Generic↔immune transfer risk.** Held pool is mostly non-immune cell lines at baseline. It teaches the codon/sequence→TE map, not immune-stimulus response. Immune held anchors are few.
- **Batch / method heterogeneity.** RiboBase is uniformly processed (low batch). Individual GEO studies used different aligners/normalizations; our held immune TE (GSE254157/254230, GSE168476) was recomputed with one CPM-ratio method for internal consistency, but GSE99787 is author-provided (different method). Absolute TE is **not** cross-study comparable; within-study stimulated-vs-resting contrasts are the reliable signal.
- **Species skew.** Most immune-stimulus paired studies are mouse; human immune-stimulus paired ribo-seq is scarce.
