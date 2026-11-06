# Instrument-deck result values (for Claude Design)

**Date:** 2026-10-25. **For:** Claude Design — the result-scene numbers for the instrument
decks, so you don't have to invent them. **RNA-seq is REAL** (a real BioMate run); the rest are
**realistic, method-consistent ILLUSTRATIVE example values** — fine for a demo, shown as example
data, swappable for real-run numbers later. Every value is consistent with the workflow's real
method and QC. Use the per-instrument QC number (the "what-good-looks-like" gate) as the headline.

---

## 1. basespace-sequencing (RNA-seq branch) — **REAL DATA, use as-is**
Source: `reference/claude_design/tutorials/assets/live/_raw/deseq_results_top200.csv` +
`deseq_qc_metrics.json` (GSE52778, dexamethasone vs untreated airway smooth muscle; nf-core/rnaseq → DESeq2).
- **34,371 genes tested · 1,242 significant** (padj < 0.05, |FC| ≥ 2) — this is the QC gate row.
- Top DE genes (gene · log2FC · padj): **SPARCL1 +4.64 · 1.7e-116**; PER1 +3.19 · 7.6e-54;
  ZBTB16 +4.02 · 1.4e-49; DUSP1 +2.95 · 3.4e-47; MT2A +2.18 · 3.4e-47; KLF15 +1.42 · 2.3e-46.
- Read `log2FoldChange` (+1 = doubled) + `padj` (FDR). Source file `deseq2_results.csv`; MultiQC for run QC.
- *(WGS branch — illustrative: mean coverage 32×, alignment 96%, 4.6M variants; example HIGH-impact: `BRCA2 stop_gained`. 16S branch — illustrative: top taxa Bacteroides 31%, Faecalibacterium 12%, Shannon 3.4.)*

## 2. plate-reader-assays — illustrative (answers the IC50 / Hill / dose-point question)
**Dose-response (4PL / LL.4):** IC50 = **0.12 µM (120 nM)** · Hill slope = **1.05** · Top = 99% ·
Bottom = 2% · R² = 0.995 · both plateaus reached (so the IC50 is interpolated, not extrapolated).
**10-point curve** (conc µM → % inhibition, triplicate): 10→99, 3.0→97, 1.0→93, 0.33→82, 0.11→55,
0.037→24, 0.012→9, 0.0041→3, 0.0014→1, 0→0.
**Screen / hit-calling:** **Z′-factor = 0.76** (excellent, > 0.5) · 384 wells · **18 hits** at > 50%
inhibition @ 10 µM. (Z′ is the single most important QC number — show it.)

## 3. somatic-tumor-sequencing (nf-core/sarek · Mutect2) — illustrative
**142 somatic variants** pass filters · **TMB 8.2 mut/Mb** · **MSI-stable** (3.1%). Top: `KRAS p.G12D`
VAF 0.34 (HIGH); `TP53 p.R175H` VAF 0.52 (HIGH); `PIK3CA p.E545K` VAF 0.21 (MODERATE). Outputs: annotated VCF + recalibrated BAM.

## 4. nanopore-minknow (nf-core/nanoseq) — illustrative
3.2M reads · **read N50 = 12.4 kb** · mean Q = 13.8 · mapping 94%. Variants: 1,284 structural + 38k SNVs. (Long-read QC: N50 + mean Q are the headline.)

## 5. lcms-proteomics-metabolomics (diaproteomics / metaboigniter) — illustrative
**Proteomics:** 6,842 protein groups quantified (1% FDR) · **312 differentially abundant** (adj.p < 0.05);
top UP log2FC +1.9, top DOWN −2.1; MultiQC/PTXQC clean. **Metabolomics:** 1,860 features · 94 significant;
top feature m/z 311.168 @ RT 4.2 min, VIP 2.3, fold-change +2.4.

## 6. advanced-proteomics-mass-spec — illustrative
- **TMT (MSstatsTMT):** 8,120 proteins · **540 DE** (adj.p < 0.05).
- **Phospho (ptm_localization):** 12,340 phosphosites at **PhosphoRS ≥ 0.9** · 890 regulated (adj.p < 0.05).
- **Immunopeptidomics (nf-core/mhcquant):** 1,840 peptides (8–11-mer) · **147 HLA-A*02:01 binders** (rank ≤ 2%);
  top `KLVVVGAVGV` rank 0.12%.

## 7. cryoem-reconstruction (cryosparc_standard_spa) — illustrative
**Resolution 3.1 Å** (FSC = 0.143) · 142,300 particles (from 1.2M picks) · B-factor −98 Å² · CTF fit to 3.0 Å.
(Resolution at FSC 0.143 is the headline; show the FSC curve.)

## 8. microscopy-pathology-imaging (nf-core/mcmicro · segmentation) — illustrative
**48,200 cells segmented** · markers DAPI / CD8 / CD68 / PanCK · CD8+ fraction 14% · tumor (PanCK+) 38% ·
mean nuclear area 42 µm². Output: OME-TIFF + per-cell marker table.

## 9. sample-qc-instruments (RIN / NanoDrop) — illustrative
**RIN = 8.6** (DV200 92%) · **A260/280 = 2.03** · A260/230 = 2.11 · concentration 185 ng/µL. Verdict: **pass**
(RIN ≥ 7 for RNA-seq). (RIN + A260/280 are the headline QC.)

## 10. flow-cytometry-gating — already has numbers (confirm/align if needed)
For consistency, a matching example: 142,000 events · live 88% (viability) · CD3+ 62% · CD4+ 38% · CD8+ 21% ·
CD4/CD8 ratio 1.8; FlowSOM 8 clusters. Keep whatever the deck already uses if it's method-consistent.

---

**Notes for Design:** show these as **example values** (not framed as a specific real run) except
RNA-seq (real). Each deck's "what good looks like" QC gate uses the bolded headline number (Z′,
coverage, N50, FDR, resolution/FSC, RIN). Engineering can replace any illustrative set with a real
run later; the shapes/units are correct so the layout won't change.
