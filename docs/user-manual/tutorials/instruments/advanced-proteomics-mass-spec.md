# Instrument tutorial — advanced mass-spec proteomics: TMT quantification, PTM/phospho localization & immunopeptidomics

> **Who this is for:** anyone running a high-resolution mass spectrometer (Thermo Orbitrap / Q-Exactive /
> Fusion / Lumos, Bruker timsTOF) for **beyond-basic** proteomics — multiplexed **TMT/iTRAQ** quantification,
> **post-translational-modification (PTM) site localization** (phosphoproteomics), or **immunopeptidomics**
> (profiling the HLA-presented peptide repertoire). No coding needed.
> **Time:** ~15 minutes to read; a real MS pipeline run takes tens of minutes to hours (heavy compute).
> **Where it fits:** this is the **companion** to the main LC-MS tutorial,
> [`lcms-proteomics-metabolomics.md`](./lcms-proteomics-metabolomics.md), which already covers label-free
> DDA/DIA proteomics and untargeted metabolomics — read that one first for the shared basics (acquisition
> modes, FASTA databases, `.raw`→`.mzML` conversion). This tutorial does **not** repeat them; it covers the
> three advanced assays that LC-MS tutorial does not. Tutorial 6 (**T6**) explains how to *connect* an
> instrument so its files reach BioMate; **this** tutorial explains the analyses that data drives, how to run
> them, and how to read them.

---

## 1. What these instruments produce

All three assays run on the same hardware as ordinary LC-MS — a chromatograph feeds a high-resolution mass
spectrometer that records (`m/z`, retention time, intensity) and fragment (MS/MS) spectra. The vendor raw
formats are identical to the ones in the main LC-MS tutorial (Thermo `.raw`, Bruker `.d`, SCIEX `.wiff`,
converted to vendor-neutral `.mzML`). What differs is the **experimental design** and therefore the
**analysis**, not the file type:

- **TMT / iTRAQ (multiplexed quantification).** Samples are chemically tagged with **isobaric labels** before
  being pooled and run together. Each tag releases a distinct **reporter ion** on fragmentation, so one MS/MS
  spectrum carries the relative abundance of a peptide across every channel (6-, 10-, 11-, 16-, 18-plex). The
  analysable input is not the raw spectra directly but a **search-engine PSM export** (Proteome Discoverer,
  MaxQuant, SpectroMine, OpenMS, or Philosopher) plus a **channel→condition annotation** you write yourself.
- **PTM / phosphoproteomics.** The same spectra, but the question is *which residue carries the modification*.
  A phospho-enriched sample produces identifications where the modification could sit on any of several
  S/T/Y residues; **site localization** scores how confident each placement is. Inputs here are a peptide
  **identification file** (`identifications.id.csv`) and the matching **MS2 peaklist** (`peaklist.mgf`).
- **Immunopeptidomics.** You immuno-precipitate HLA molecules and elute the short peptides they present, then
  acquire them by LC-MS/MS. Because eluted HLA ligands are low-abundance and **non-tryptic**, this assay is
  only meaningful on an **Orbitrap-/timsTOF-class** instrument (high resolution, high sensitivity). The
  analysable input is `.mzML` plus a protein **FASTA** search database.

**Raw spectra are not an answer.** Turning them into "this phosphosite is 3-fold up in treatment" or "these
peptides are presented on the patient's HLA-A*02:01" takes a multi-step pipeline — which one depends on the
assay above.

---

## 2. The BioMate analyses these drive (and why)

### 2a. TMT / iTRAQ — differential abundance across channels

→ **`msstatstmt` · `tmt_differential_abundance_analysis`** — Bioconductor **MSstatsTMT**, the reference R
package for TMT differential abundance.
(`backend/biomni_workflows/nextflow_nfcore/subworkflows/bioconductor/msstatstmt/main.nf`)

It runs the standard MSstatsTMT chain:

1. **Convert** your search output + annotation into MSstatsTMT format (`PDtoMSstatsTMTFormat`; sister
   converters exist for MaxQuant, SpectroMine, OpenMS, Philosopher).
2. **Protein-level summarization** with channel/run normalization and missing-value imputation
   (`proteinSummarization`, `method="msstats"`, `global_norm=TRUE`, `reference_norm=TRUE`).
3. **Diagnostic profile plots** (`dataProcessPlotsTMT`).
4. **Differential testing** — moderated t-tests, all pairwise comparisons by default
   (`groupComparisonTMT`), plus an optional **custom contrast matrix**.

**Inputs (two files):**
- `raw.pd` — the PSM-level export from your search engine (tab-separated Proteome Discoverer sheet, or the
  MaxQuant / SpectroMine / OpenMS / Philosopher equivalent).
- `annotation.pd` — **a CSV you build yourself** mapping the experimental design: columns `Run`, `Fraction`,
  `TechRepMixture`, `Channel`, `Condition`, `BioReplicate`, `Mixture`. MSstatsTMT cannot infer this from the
  search output.

**Key choices** (sensible defaults; change only with reason): `which.proteinid` (which column holds the
protein accession — `Protein.Accessions` for PD, `Leading.razor.proteins` for MaxQuant), `method`
(`msstats` imputes missing values; `MedianPolish`/`Median`/`LogSum` do not), `global_norm`, `reference_norm`,
`moderated`, and the `contrast.matrix` for custom comparisons.

### 2b. PTM / phospho — site localization & modified-peptide ratios

→ **`isobar` · `ptm_localization_quant`** — Bioconductor **isobar**, using **PhosphoRS** localization
probabilities. (`backend/biomni_workflows/nextflow_nfcore/subworkflows/bioconductor/isobar/ptm_localization_quant.nf`)

It:

1. Writes the **PhosphoRS** input (`writePhosphoRSInput`) and reads back localization probabilities
   (`readPhosphoRSOutput` / `getPhosphoRSProbabilities`).
2. Imports and **filters spectra** during read — by delta score (`filterSpectraDeltaScore`,
   `min.delta.score=10`) or, when a PhosphoRS engine is available, by localization probability
   (`filterSpectraPhosphoRS`, `min.prob=0.9`).
3. Fits a **noise model** (`NoiseModel`) and **estimates ratios** for modified peptides between reporter
   channels (`estimateRatio`).
4. Retrieves **PTM annotations** from PhosphoSitePlus (`getPtmInfoFromPhosphoSitePlus`) and neXtProt
   (`getPtmInfoFromNextprot`).

**Inputs (two files):** `identifications.id.csv` (peptide identifications) and `peaklist.mgf` (the matching
MS2 peaklist). **Key choices:** `type` (the isobaric chemistry — `iTRAQ4plexSpectra`, `TMT6plexSpectra`, …),
`min.delta.score`, `min.prob`, `massTolerance`, and `activationType` (`CID`/`HCD`).

### 2c. Immunopeptidomics — HLA-presented peptide identification, binding & antigen ranking

Immunopeptidomics is a **chain** of nf-core pipelines plus one BioMate fusion step. The quantification engine,
**`nf-core/mhcquant`**, is an **nf-core pipeline — it is not stubbed locally in this repo**; BioMate routes to
it as an external nf-core pipeline, so its parameters follow the nf-core/mhcquant documentation.

- **`nf-core/mhcquant`** — identifies and quantifies **MHC-bound (eluted-ligand) peptides** from LC-MS/MS. It
  runs an OpenMS-based pipeline: Comet database search against your protein **FASTA**, **Percolator** FDR
  control tuned for non-tryptic HLA ligands, and optional label-free quantification. Inputs: a samplesheet of
  `.mzML` files + a FASTA database; outputs: FDR-controlled MHC-peptide identification and quantification
  tables.
- **`nf-core/hlatyping`** (OptiType) — determines the sample's **HLA alleles** (class I) from sequencing
  reads, so predictions are made against the right alleles.
- **`nf-core/epitopeprediction`** — **peptide × HLA binding** predictions (NetMHCpan / NetMHCIIpan style:
  binding score and %rank).
- **`immunology/antigen_resolution`** (a **real, local** BioMate fusion workflow,
  `backend/biomni_workflows/nextflow_nfcore/subworkflows/immunology/antigen_resolution/main.nf`) — does **not**
  re-run the tools above; it **ingests** their outputs (repertoire, HLA typing, epitope predictions) and
  computes a single **antigen-resolution score** per candidate peptide by fusing HLA-binding strength, clonal
  repertoire support, and optional disease-gene relevance. It deliberately surfaces under-served **class-II
  (HLA-DP/DQ/DR)** candidates. Outputs: `antigen_candidates.csv`, `antigen_resolution_results.json`, a
  Markdown report.

| What you measured | Workflow BioMate offers | Where it lives |
|---|---|---|
| TMT/iTRAQ multiplexed quantification | **`msstatstmt`** (`tmt_differential_abundance_analysis`) | local Bioconductor workflow |
| Phospho / PTM site localization | **`isobar`** (`ptm_localization_quant`) | local Bioconductor workflow |
| HLA-eluted peptide ID & quant | **`nf-core/mhcquant`** | **nf-core pipeline (not local)** |
| HLA typing for the sample | **`nf-core/hlatyping`** (OptiType) | nf-core pipeline |
| Peptide × HLA binding prediction | **`nf-core/epitopeprediction`** | nf-core pipeline |
| Rank candidate antigens/epitopes | **`immunology/antigen_resolution`** | local BioMate fusion workflow |
| Plain label-free DDA/DIA, or metabolomics | see the main LC-MS tutorial | — |

---

## 3. Before you start — get the data in (see T6)

Connecting the instrument is **out of scope here** — once your `.raw`/`.d`/`.wiff` files are converted to
`.mzML` (or your search-engine exports are ready) and are **in BioMate**, this tutorial takes over. T6 covers
connecting an instrument; Tutorial 4 covers a one-off manual upload. As with all MS work, `.raw`→`.mzML`
conversion (ProteoWizard **msconvert**) may be needed first — see the main LC-MS tutorial's §6.

**What you must have ready:**
- **TMT:** your search-engine **PSM export** (`raw.pd`) **and** a hand-built **annotation CSV** (`annotation.pd`)
  with the channel→condition design (§2a). If you have only **one MS run**, set `reference_norm` to FALSE
  (reference normalization needs a `Norm` channel in each run).
- **PTM/phospho:** the peptide **identification file** (`identifications.id.csv`) and the matching
  **MS2 peaklist** (`peaklist.mgf`); know your **isobaric chemistry** (`type`).
- **Immunopeptidomics:** `.mzML` files from an **Orbitrap/timsTOF-class** instrument and a protein **FASTA**
  database; for the full chain, sequencing reads for HLA typing and a list of HLA alleles.

---

## 4. Step by step — run it

1. **Ask in chat (or pick the workflow card).** State the assay explicitly, e.g.
   *"TMT differential abundance with MSstatsTMT on this Proteome Discoverer PSM export and my annotation
   file, treated vs. control"*, or *"Phospho site localization with isobar on these identifications and
   this mgf peaklist, TMT6plex"*, or *"Immunopeptidomics: identify HLA-eluted peptides with nf-core/mhcquant
   against the human FASTA."*
2. **Check the workflow card.** Confirm the panel opened the right workflow (`msstatstmt`, `isobar`
   `ptm_localization_quant`, or `nf-core/mhcquant`) — the name must not read "undefined". If it is the wrong
   one, restate the assay.
3. **Attach the inputs** named in §3 for your assay, and set the key choices (§2) — for most runs the defaults
   are correct.
4. **Confirm and run.** Click **Confirm & Run**. Expect a **long** run (real MS compute). Watch the phase
   cards move *pending → running → completed*.

<!-- CAPTURE route=/ ; state=Workflow panel running for msstatstmt tmt_differential_abundance_analysis, phase cards with one running ; focus=workflow-panel ; note=show the TMT pipeline mid-run with a phase in the running state -->
*(Figure to add: the TMT pipeline mid-run — conversion / summarization / differential-testing phase cards, with one phase in the running state.)*

---

## 5. Reading the result / report

Open the **After run** section (three tabs — see **Tutorial 3**).

**TMT (`msstatstmt`):**
- **Protein-level quantification** — `quant_msstats_protein_level.csv` (normalized abundance per protein per
  channel) and the serialized `quant_msstats.rds`.
- **Differential abundance** — `test_pairwise_results.csv` (all pairwise group comparisons) and, when your
  condition names match the built-in contrast, `test_contrast_results.csv`. Read by **log2 fold change** plus
  **adjusted p-value** (smaller is stronger; a common cut is adj. p < 0.05).
- **Diagnostics** — the `ProfilePlot` PDF, plus a `qc_metrics.json` with gate checks (missing-value fraction,
  library-size CV, retained-feature fraction).

**PTM / phospho (`isobar`):**
- **`estimated_ratios.csv`** — per-peptide reporter-channel ratios (`lratio`, variance, `n.spectra`,
  `p.value.rat`).
- **`ptm_info_phosphositeplus.csv`** / **`ptm_info_nextprot.csv`** — annotated modification-site information.
- **`isobar_ptm_plots.pdf`** — the 95 %-CI noise-model MA-plot; `ib_phospho.rds` / `noise_model_hcd.rds` for
  downstream reuse. A **high localization probability** (PhosphoRS ≥ 0.9) is what lets you trust that the
  modification is on the reported residue, not a neighbour.

**Immunopeptidomics:**
- **`nf-core/mhcquant`** — FDR-controlled MHC-peptide identification/quantification tables (the presented
  peptide repertoire).
- **`immunology/antigen_resolution`** — `antigen_candidates.csv` (ranked candidates with the fused score),
  `antigen_resolution_results.json`, and a Markdown report; class-II (DP/DQ/DR) coverage is reported
  explicitly.

> **What good looks like, and what to watch.** In TMT, a healthy run normalizes channels onto a common scale
> and the ProfilePlot shows no single channel wildly offset; be suspicious of a result with almost no missing
> values *imputed* (often a mis-specified annotation). In phospho, trust the sites with high localization
> probability — an "identified" phosphopeptide with an ambiguous site is a hypothesis about *where*, not a
> confirmed site. In immunopeptidomics, a sensible yield of **8–11-mer** (class I) peptides enriched for your
> HLA's binding motif is the sanity check; very few peptides usually means a wrong FASTA or an instrument not
> sensitive enough for eluted ligands.

---

## 6. BioMate also offers (breadth)

Beyond these three assays, the facility's MS data can drive a wide BioMate proteomics surface:

- **Label-free DDA/DIA quantification & metabolomics** — the main LC-MS tutorial (`nf-core/proteomicslfq`,
  `nf-core/diaproteomics`, `proteomics_dda_search`, `xcms_lc_ms_preprocessing`, `metaMS`).
- **Isobaric PSM assembly & DEqMS** — `deqms/psm_table_isobaric` for building isobaric PSM tables and
  DEqMS-based differential testing, a complementary route to MSstatsTMT.
- **Standard (non-PTM) isobaric quantification** — the `isobar` package's `isobaric_quantification` workflow
  (isotope-impurity correction, normalization, noise modeling, protein-ratio estimation).
- **Immunogenomics stack** — `nf-core/airrflow` (TCR/BCR repertoire), `nf-core/hlatyping`,
  `nf-core/epitopeprediction`, and `immunology/antigen_resolution` for antigen/epitope discovery.
- **Knowledge & tool search** — BioMate indexes 1,000+ Bioconductor workflows and 12,000+ tools; ask in chat
  for an enrichment/pathway step (clusterProfiler/enrichGO, GSEA), a protein–protein network, or a figure, and
  it will route to the right one.

---

## 7. Honest limits — what to expect (read this carefully)

- **TMT and PTM status: 🔧 thin — real but single-package, not best-in-class, and not E2E-validated.**
  `msstatstmt` and `isobar` are **real, indexed BioMate workflows** wrapping the reference Bioconductor
  packages (MSstatsTMT; isobar + PhosphoRS). They are **thin single-package wrappers**, not the state-of-the-art
  umbrella pipelines, and have **no recorded real end-to-end run** on the dev site. An upgrade is **planned**
  (TMT → the nf-core/quantms umbrella; PTM → PTMShepherd/FragPipe), not yet shipped. Treat every result as
  **experimental** until checked against a known dataset — do not report a TMT/PTM number from BioMate as
  validated.
- **The TMT custom contrast is a template, not a universal comparison.** The built-in custom `contrast.matrix`
  is hard-coded for a spike-in design with conditions named `0.125`/`0.5`/`0.667`/`1`. It is wrapped so it
  won't crash on other designs, but it only produces `test_contrast_results.csv` if **your** condition names
  match those. The **pairwise** comparison (`test_pairwise_results.csv`) always runs and is what you read for
  an arbitrary design.
- **PhosphoRS needs its engine present.** Direct PhosphoRS probability computation requires a Java
  `PhosphoRS.jar`/`phosphoRS.jar` in the working directory, or a pre-computed `phosphors.out.xml`. Without
  either, the workflow falls back to **delta-score** filtering (`min.delta.score=10`) — still useful, but you
  do not get PhosphoRS localization probabilities.
- **You must build the TMT annotation by hand.** Search engines do **not** emit the channel→condition
  annotation (`Run`, `Fraction`, `Channel`, `Condition`, `BioReplicate`, `Mixture`, …); a wrong or missing
  annotation is the most common cause of a silently wrong TMT result. Single-run experiments must set
  `reference_norm=FALSE`.
- **Immunopeptidomics is strong but instrument-gated, and nf-core/mhcquant is not local.** The
  mhcquant → hlatyping → epitopeprediction → antigen_resolution chain is **best-in-class and complete** — but
  it is **gated on an Orbitrap-/timsTOF-class** instrument; a triple-quad will not yield a usable
  immunopeptidome. The facility's exact MS model is **unknown**, so confirm instrument class before relying on
  this assay. `nf-core/mhcquant`, `nf-core/hlatyping`, and `nf-core/epitopeprediction` are **nf-core pipelines,
  not stubbed in this repo** — only the `antigen_resolution` fusion step is local.
- **`.raw`→`.mzML` conversion and engine licensing** carry over from the main LC-MS tutorial: conversion may be
  required before upload, and some search engines (DIA-NN, MSFragger, Spectronaut) are not license-clean for
  commercial use. See that tutorial's §6.

---

## 8. Where to go next

| You want to… | Where |
|---|---|
| Plain label-free DDA/DIA proteomics, or metabolomics | the main [LC-MS tutorial](./lcms-proteomics-metabolomics.md) |
| Connect the MS instrument so runs arrive automatically | **Tutorial 6** |
| Convert/upload a single `.mzML` by hand | **Tutorial 4** |
| Understand the three-tab report | **Tutorial 3** |
| Build isobaric PSM tables / DEqMS testing | ask for **`deqms/psm_table_isobaric`** |
| Rank candidate antigens from the immunopeptidome | ask for **`immunology/antigen_resolution`** |

The habit: **state the assay (TMT / phospho / immunopeptidomics) → attach the right inputs (PSM export +
annotation, or id.csv + mgf, or mzML + FASTA) → confirm & run (expect a long job) → read the quant / ratio /
candidate tables, treating TMT and PTM results as experimental.**

---

## 9. Key terms

| Term | What it means — and why you care |
|---|---|
| **Isobaric label (TMT/iTRAQ)** | A chemical tag that lets several samples be pooled and quantified in one run; each tag releases a distinct **reporter ion**. |
| **Channel** | One isobaric tag = one sample in a multiplexed set (e.g. TMT-10plex = 10 channels). |
| **Reference / `Norm` channel** | A channel used to normalize between MS runs; `reference_norm` requires one per run (single run → set FALSE). |
| **Annotation file** | The CSV *you* write mapping channel → condition/bioreplicate/mixture; MSstatsTMT cannot infer it. |
| **PSM** | Peptide-Spectrum Match — one identified spectrum; the TMT input is a PSM-level search export. |
| **Site localization / PhosphoRS** | How confident the modification sits on a specific residue vs. a neighbour; a probability ≥ 0.9 is a confident site. |
| **Delta score** | Score gap between the best and second-best peptide match; a higher gap = a more trustworthy ID. |
| **Immunopeptidome** | The set of short peptides a cell presents on its HLA/MHC molecules. |
| **HLA typing (OptiType)** | Determining a sample's HLA alleles so binding predictions use the right alleles. |
| **Binding %rank (NetMHCpan)** | How strongly a peptide is predicted to bind an HLA allele; strong binders ≤ 2 %rank. |
| **Class I vs. class II HLA** | Class I presents ~8–11-mers to CD8 T cells; class II (DP/DQ/DR) presents longer peptides to CD4 T cells. |

---

_Grounded in the real workflow files:
`backend/biomni_workflows/nextflow_nfcore/subworkflows/bioconductor/msstatstmt/main.nf` (+ `_interpretation.json`,
`requirements.json`) — MSstatsTMT TMT differential abundance;
`backend/biomni_workflows/nextflow_nfcore/subworkflows/bioconductor/isobar/ptm_localization_quant.nf`
(+ `_interpretation.json`, `requirements.json`) — isobar/PhosphoRS PTM localization;
`backend/biomni_workflows/nextflow_nfcore/subworkflows/immunology/antigen_resolution/main.nf` — local antigen
fusion. `nf-core/mhcquant`, `nf-core/hlatyping`, and `nf-core/epitopeprediction` are **nf-core pipelines, not
stubbed locally** — grounded in the nf-core pipeline documentation. Status per
`docs/20260920_HOSPITAL_INSTRUMENT_RESOURCE_INVENTORY.md`: TMT/PTM 🔧 (U9/U12 upgrades planned),
immunopeptidomics ✅ best-in-class but gated on Orbitrap/timsTOF-class instrument. Connection is out of scope
(deferred to T6). Companion: the main LC-MS tutorial; Tutorials 3, 4, 6._
