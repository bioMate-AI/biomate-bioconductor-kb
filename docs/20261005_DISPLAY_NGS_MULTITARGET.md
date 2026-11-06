# Multi-Target Cyclic-Peptide Display-NGS Pool — Harvest, Unified Table, and Honest Data-Wall Verdict

**Date:** 2026-10-05 · **Author:** research session (Yaoyun Zhang / BioMate)
**Context:** the data dependency for **v3** of the inverted-data-dependency cyclic LLM —
*target-conditioned generation + cross-target generalization*. Follows
`docs/20261005_DISPLAY_NGS_HARVEST.md` (which built the single-target PADI4 dataset and the
reusable parser) and `docs/20261004_CYCLIC_PEPTIDE_DATA_WALL_STRATEGY.md`.

**TL;DR.** We assembled **ONE unified, target-labeled enrichment table across 5 distinct targets**
(**525,665 peptides, 2,215,404 rows**) entirely from free public SRA/ENA, each with a genuine
selection-convergence signal. This **exceeds the ≥3–5 distinct-target goal**. **But** the free pool
is chemistry-heterogeneous — it splits into **3 display regimes**, so clean "apples-to-apples"
cross-target generalization is only available **within a regime** (2 RaPID-round targets; 2 phage
targets). This is enough to *prototype target-conditioning and run a first cross-target transfer test*,
**not** a broad target-diverse corpus. And critically: **none of the 5 is one of OUR targets**
(PD-L1, αvβ6) — the data wall for the moat program stands. The free axis got *wider* (1→5 targets),
not *deeper on our targets*.

**S3:** `s3://knowledge-datasets-1759951976/cyclic_peptide/datasets/display_ngs_multitarget/`
- `display_ngs_multitarget.csv.gz` (12.8 MB gz; **2,215,404 rows**) — unified long table
- `display_ngs_multitarget_meta.json` — full per-target + per-stage provenance
**Code:** `research/guangzhou_all_atom/harvest_display_ngs_multitarget.py` (new; original single-target
`harvest_display_ngs_rapid.py` left intact).

---

## 1. Inventory — campaigns picked (distinct targets, enrichment structure)

Selected from the existing inventory + a focused SRA/ENA pass (NCBI E-utilities `RaPID selection
peptide` → 103 runs, grouped by BioProject; design/anchors reverse-engineered from each deposit's
`DESIGN_DESCRIPTION`).

| Target | Accession | Display / chemistry | Enrichment definition | Runs harvested | Download |
|---|---|---|---|---|---|
| **PADI4** (human peptidylarginine deiminase 4) | PRJNA1188087 | mRNA-display RaPID, **thioether ClAc-Cys**, ncAA | round-over-round, **R2→R6** vs R2 | 5 (reused from S3) | — (reused) |
| **hPCSK9** (human PCSK9) | PRJNA1406026 | XL RaPID, **photo-crosslink** (Bpa/PhoL/N3F reprog. Met), ncAA | **single-round, output/input** | 36 (18 in + 18 out) | 340 MB |
| **FIKK13** (*P. falciparum* FIKK13 kinase) | PRJNA1172558 | mRNA-display RaPID, **thioether ClAc-Cys**, ncAA | round-over-round, **R1→R6** vs R1 | 6 | 167 MB |
| **Abeta42** (amyloid-β 42) | PRJNA1170358 | **M13 phage** cyclic (Cys-flanked), canonical AA | **library→selected** (7 rounds, NNK) | 2 (R1) | 560 MB |
| **hIAPP** (islet amyloid polypeptide/amylin) | PRJNA1170358 | **M13 phage** cyclic (Cys-flanked), canonical AA | **library→selected** (5 rounds, NDT) | 2 (R1) | 380 MB |

Total downloaded ≈ **1.45 GB** (well under the 30 GB cap; ENA direct fastq, no SRA toolkit).

### Reverse-engineered amplicon designs (from deposits)
- **PADI4 / FIKK13 (identical RaPID construct):**
  `5'-…CATATG (NNK)n TGCGGCAGCGGCAGCGGCAGC TAG GACGGGGGGCGGAAA-3'`, n=6–12.
  Parse: variable AA between `CATATG` and `TGCGGCAGC`; drop amber/frameshift/N. Cyclization =
  ClAc-initiator + variable + fixed Cys thioether.
- **hPCSK9 (XL RaPID):** two parent binders **P1, P6** affinity-matured (one internal Met→photo-AA
  per variant). No Cys-GS anchor; reads are ORF point-mutant variants on a 101 bp NovaSeq read.
  Parse: fixed **12-codon ORF window** from the ATG in `CATATG` (stable key despite read truncation).
  Enrichment = log2(output_freq/input_freq), aggregated across P1/P6 × PhoL/Bpa/N3F × reps.
- **Abeta42 / hIAPP (M13 phage SICLOPPS-style):** cyclic peptide between two Cys codons in the phage
  gIII cassette. Parse: variable (incl. flanking Cys) between constants `CACAAC` … `CTCAGT` on R1;
  codon range 5–14. Enrichment = log2(selected_freq/library_freq).

### Rejected false positives (honest)
The `RaPID selection peptide` free-text search also returned **PRJNA970348** (scTCR/scRNA-seq T-cell
repertoire — "selection" matched sort gates, **not** peptide display) and **PRJNA296366**
(*Cryptococcus* RNA-seq/ChIP-seq Qsp1 study). Both excluded. **PRJNA1167468** is *additional PADI4*
RaPID (rounds 7–9 ± Ca/Cl-amidine) — same target as #1, not a new one; left out to avoid double-counting
PADI4 (available as a future PADI4-depth extension).

> **Correction to the prior harvest doc.** `docs/20261005_DISPLAY_NGS_HARVEST.md` listed PRJNA1406026
> as "**multiple targets** (P1_PhoL, P6_N3F, …)". That was wrong: **all 54 runs are against a single
> target, hPCSK9** — `P1/P6` are two parent-peptide scaffolds and `PhoL/Bpa/N3F` are three
> photo-crosslinker ncAAs (every `experiment_title` reads "…XL RaPID selection against hPCSK9"). So the
> single richest "multi-target" lead was actually single-target; the genuine target diversity came from
> stitching **four separate BioProjects** together.

---

## 2. Unified table — schema, per-target counts, signal

**Schema (long; one row per target × sequence × stage):**
`target, sequence, n_residues, round_or_io, count, enrichment_log2fc, cyclization, display_type, source_accession, is_binder`

**Enrichment / binder label (the v2 lesson applied — bucket by the ENRICHED TAIL, not quantiles):**
`enrichment_log2fc = log2((freq_stage+eps)/(freq_baseline+eps))`, eps = 1/min(stage_total). A peptide is
`is_binder=1` iff at its **terminal/selected stage** `count ≥ 10` **AND** `log2fc ≥ 2.0` — i.e. the
label keys on the actually-enriched, well-sampled tail, not a distributional quantile dominated by
sequencing-error singletons. Row floor: keep peptides with max per-stage count ≥ 3.

| Target | Rows | Unique peptides | Binders (tail-bucketed) | Selection-convergence (unique: baseline→terminal) | Top enriched (log2FC) |
|---|---:|---:|---:|---|---|
| PADI4 | 1,854,030 | 370,806 | 394 | 780,697 (R2) → 28,936 (R6) | `VYSMKEWKY` 10.96 |
| hPCSK9 | 28,270 | 14,135 | 749 | 45,494 (in) → 29,677 (out) | `MVPGPWRHIHCW` 6.62 |
| FIKK13 | 77,484 | 12,914 | 38 | 383,077 (R1) → 1,103 (R6) | `ESCRYRQVLQL` 12.47 |
| Abeta42 | 88,234 | 44,117 | 1,104 | 156,950 (lib) → 10,036 (sel) | `CRVYQVLC` 14.80 |
| hIAPP | 167,386 | 83,693 | 828 | 394,521 (lib) → 4,467 (sel) | `CHVVGVIC` 14.44 |
| **TOTAL** | **2,215,404** | **525,665** | **3,113** | — | — |

Every target shows a textbook affinity-selection fingerprint: large diversity collapse + a small
dominant enriched tail (FIKK13 `ESCRYRQVLQL` 5,685 reads @ R6; Abeta42 `CRVYQVLC` 3.6 M reads;
hIAPP `CHVVGVIC` 2.9 M reads). PADI4 reproduces the prior harvest exactly (`VYSMKEWKY` R2→R6 0→10.96).

**Validity checks done:** parse functions unit-tested on real reads of each campaign before the bulk
run (incl. correct dropping of a FIKK13 read with a premature stop); all phage fastqs verified with
`gzip -t` + exact ENA byte counts after two were caught truncated.

---

## 3. Honest assessment — how many distinct targets with usable enrichment did we actually get free, and is it enough for cross-target generalization?

**Count:** **5 distinct targets, all free, all with usable enrichment.** This meets/exceeds the ≥3–5
goal and is a real improvement over the single-target (PADI4-only) starting point.

**The catch — chemistry/definition heterogeneity.** The 5 targets are **not one homogeneous axis**;
they fall into **three regimes** that differ in display chemistry, cyclization, and enrichment
definition:

1. **RaPID rounds, thioether ncAA, round-over-round log2FC** — **PADI4, FIKK13** (identical construct).
2. **XL RaPID, photo-crosslink ncAA, single-round output/input, fixed 12-mer ORF window** — **hPCSK9**.
3. **M13 phage, disulfide/Cys-flanked canonical AA, library→selected** — **Abeta42, hIAPP**.

**Implications for cross-target generalization:**
- The **cleanest apples-to-apples transfer test** available today is **within regime 1** (train on
  PADI4 → test on FIKK13, identical chemistry + enrichment axis) and **within regime 3** (Abeta42 ↔
  hIAPP, matched library→selected). Both are **2-target** tests — enough for a *first* generalization
  probe, not for a "train on N−1, hold out 1" sweep with N large.
- Using **all 5** requires the model/eval to **condition on `display_type` + `cyclization`** and treat
  the enrichment axis as regime-specific; otherwise chemistry is a confound that will masquerade as
  (or destroy) "target" signal. The columns are in the table precisely so this conditioning is possible.
- **Known artifact to respect:** hPCSK9 sequences are all exactly **12 residues** (fixed ORF window on
  a maturation of 2 parent clones) — lower effective diversity and N-terminal-truncated keys. Valid as a
  per-target enrichment signal, but do **not** treat its length distribution or absolute diversity as
  comparable to the degenerate-library targets.

**Verdict (truthful):** Free public display NGS yields a **usable 5-target prototype substrate** for
target-conditioning and a **first (within-regime, 2-target) cross-target generalization test** — a
genuine step up from single-target. It is **not** a broad, chemistry-homogeneous, many-target corpus;
real cross-target *breadth* is capped by how few clean campaigns are deposited (the `RaPID selection
peptide` ceiling is ~103 runs across ~4 usable BioProjects, and phage cyclic-panning NGS is mostly
**not** deposited at all — authors publish final hits, not round-over-round reads). **And none of the
5 targets is PD-L1 or αvβ6.** So this **confirms the data wall for our targets**: the free pool is now
*wider* (5 generic targets) but still *empty on our targets* → a **proprietary campaign remains
required** for PD-L1/αvβ6 binding labels (`docs/20261004_CYCLIC_PEPTIDE_DATA_WALL_STRATEGY.md` Step 2).

---

## 4. Reproduce

```bash
# 1. ENA direct fastq (authoritative paths from the portal API; do NOT hand-construct the /0XX/ subdir)
curl -sL "https://www.ebi.ac.uk/ena/portal/api/filereport?accession=PRJNA1172558&result=read_run&fields=run_accession,fastq_ftp&format=tsv"
# (FIKK13 + hPCSK9 input/output + phage R1 for Abeta42/hIAPP; verify each with `gzip -t`)

# 2. harvest all 5 targets into the unified table (+ reuse PADI4 from S3)
aws s3 cp s3://knowledge-datasets-1759951976/cyclic_peptide/datasets/display_ngs_padi4_rapid/display_ngs_padi4_rapid_15min.csv.gz padi4_long.csv.gz
python3 research/guangzhou_all_atom/harvest_display_ngs_multitarget.py \
  --fastq-dir ./fastq --padi4-long ./padi4_long.csv.gz --outdir ./out --name display_ngs_multitarget
```

## 5. Next steps
1. **Prototype target-conditioning now ($0):** train a target-conditioned enrichment head on the
   unified table, conditioning on `target` + `display_type` + `cyclization`.
2. **First cross-target transfer test:** regime-1 (PADI4→FIKK13) and regime-3 (Abeta42↔hIAPP) hold-outs.
   Report transfer within-regime separately from across-regime (the latter measures chemistry transfer,
   not target transfer).
3. **Cheap depth extension:** fold **PRJNA1167468** (more PADI4 RaPID rounds ± Ca/Cl-amidine) into the
   PADI4 arm for a condition-transfer axis on a single target.
4. **Moat (paid):** nothing free covers PD-L1/αvβ6 — commission the proprietary cyclic display campaign
   for target-specific binding labels.

## 6. Sources
- PRJNA1188087 (PADI4, Imperial College London) — reused from the first harvest.
- PRJNA1406026 — "Single-round XL RaPID selection against hPCSK9" (P1/P6 scaffolds; Bpa/PhoL/N3F).
- PRJNA1172558 — "FIKK13 RaPID selection" rounds 1–6.
- PRJNA1170358 — Tina Wang lab (UW-Madison), M13 phage cyclic peptides vs Aβ42 / hIAPP (SICLOPPS/PACE).
- Prior: `docs/20261005_DISPLAY_NGS_HARVEST.md`, `docs/20261004_CYCLIC_PEPTIDE_DATA_WALL_STRATEGY.md`,
  `docs/20261005_INNOVATION_THESIS_CYCLIC_LLM.md`.
