# Instrument tutorial — LC-MS → proteomics (DDA/DIA) & metabolomics feature detection

> **Who this is for:** anyone who runs a liquid-chromatography mass spectrometer (Thermo Orbitrap/Q-Exactive/
> Fusion, Waters, Bruker timsTOF, SCIEX) and wants its raw spectra turned into **"which proteins (or
> metabolites) are present, and how their amounts differ between my conditions"** — no coding needed.
> **Time:** ~12 minutes to read; a real LC-MS pipeline run takes tens of minutes to hours (it is heavy compute).
> **Where it fits:** Tutorial 6 (T6) explains how to *connect* an LC-MS instrument so its files reach BioMate.
> This tutorial explains **the analyses that data drives, how to run them, and how to read them.**

---

## 1. What this instrument produces

An LC-MS run first **separates** a complex mixture over a chromatography column (so molecules arrive at
different **retention times**), then the mass spectrometer **weighs** whatever is arriving and records its
intensity. The result is a huge collection of (mass-to-charge `m/z`, retention time, intensity) measurements —
and, in most experiments, **fragment spectra** (MS/MS) that help identify what each peak actually is.

Vendors save this as raw data in their own formats:

- Thermo (Xcalibur) → `.raw` **file**; Waters (MassLynx) → `.raw` **folder**; Bruker → `.d` folder
  (`.baf`/`.tdf` inside); SCIEX → `.wiff`/`.wiff.scan`.
- A vendor-neutral `.mzML` (converted via ProteoWizard **msconvert**) is what most pipelines actually read.

**Raw spectra are not an answer.** Turning millions of peaks into "protein X is 2-fold up in disease" (or
"metabolite Y appears only in treated samples") takes a multi-step pipeline. That pipeline is what BioMate runs
— and which one depends on *what you were measuring* and *how you acquired it*.

---

## 2. The BioMate analysis it drives (and why)

LC-MS splits into two very different jobs, and BioMate has distinct pipelines for each.

### 2a. Proteomics — "which proteins, and how much?"

You searched peptides against a protein database. Which pipeline depends on your **acquisition mode**:

- **DDA** (Data-**Dependent** Acquisition) — the instrument picks the most intense precursors to fragment. The
  classic label-free workflow.
  → **`nf-core/proteomicslfq`**: a DDA label-free quantification pipeline (OpenMS + MSstats) that does protein
  identification (Comet / MSGF+ database search), feature-based quantification, QC, and group-based statistical
  testing of differential protein abundance. Key inputs: `input` (your `.raw`/`.mzML`), `database` (a **FASTA**
  protein database to search against), and `labeling_reagent` (`none` for label-free, or a TMT/iTRAQ option).
  A license-clean variant (`proteomics_dda_search`) also exists.
- **DIA** (Data-**Independent** Acquisition / SWATH) — the instrument fragments everything in wide windows.
  → **`nf-core/diaproteomics`** (OpenSWATH / PyProphet): the recommended, **license-clean** DIA pipeline — it
  builds or uses a spectral library, then quantifies peptides and proteins. Inputs: your DIA `.raw`/`.mzML`/`.d`,
  a `fasta` database, optional `lib` (spectral library), `qvalue` (FDR, default 0.01). *(A DIA-NN-based variant
  (`nf-core/dia_proteomics_analysis`) also exists, but DIA-NN is not license-clean for commercial use — prefer
  the OpenSWATH pipeline above.)*

*Why the mode matters:* feeding DIA data to a DDA pipeline (or vice-versa) gives wrong or empty results — the
two acquisition styles produce fundamentally different spectra. Know which mode your method used.

### 2b. Metabolomics — "which small-molecule features, and how much?"

You're profiling small molecules (not proteins), so there's no protein database — instead the pipeline detects
**features** (a feature = one m/z at one retention time) across samples and tries to annotate them.

→ **`xcms_lc_ms_preprocessing`** / **`metaMS`**: XCMS-based peak detection, alignment (retention-time
correction so the same metabolite lines up across samples), correspondence (grouping peaks into features), gap
filling, and export of a **feature table**. `metaMS` adds compound annotation. These are the standard
untargeted-metabolomics first steps.

| What you measured / how | Workflow BioMate offers |
|---|---|
| Proteins, DDA label-free | **`nf-core/proteomicslfq`** (OpenMS + MSstats) |
| Proteins, DDA, license-clean engines only | `proteomics_dda_search` (Comet/Sage/mokapot) |
| Proteins, DIA / SWATH | **`nf-core/dia_proteomics_analysis`** (DIA-NN) or `nf-core/diaproteomics` (OpenSWATH) |
| Small molecules, untargeted | **`xcms_lc_ms_preprocessing`** → **`metaMS`** (annotation) |
| You have BOTH proteomics AND metabolomics on the same samples | `Lc Ms Proteomics Metabolomics` (joint correlation + shared-pathway integration — needs both together) |

> **Honest note up front:** the LC-MS *connector* guesses `proteomics` vs. `metabolomics` vs. `lipidomics` from
> the folder/file name and tags the file with an internal routing label (its defaults point at DIA-NN for
> proteomics and XCMS for metabolomics). That tag is a **hint**. When you Launch, tell BioMate your
> **acquisition mode** (DDA or DIA) and whether it's proteins or metabolites, so it routes to the right pipeline
> above. See §6 for validation status — this is the area with the **least** real-run evidence, so read it.

---

## 3. Before you start — get the data in (see T6)

- **Connect the instrument (best for a core facility).** Register an **LC-MS** instrument in **Connectors →
  Instruments**; your admin points its file-watcher at the acquisition output folder. The watcher waits for a
  run to finish writing (LC-MS runs are long), can optionally convert `.raw` → `.mzML` with **msconvert**, and
  surfaces a **New data event**. Full steps: **Tutorial 6**.
- **Upload by hand (one-off).** Convert to `.mzML` and bring it in from the Data area. Full steps: **Tutorial 4**.

**What you must have ready:**
- **For proteomics:** a **FASTA** protein database for your organism (e.g. the human proteome from UniProt), and
  you must know your **acquisition mode (DDA or DIA)** and any **labelling** (label-free vs. TMT/iTRAQ).
- **For metabolomics:** your samples' `.mzML` files and a note of **polarity** (positive/negative ion mode).
- **A sample/condition table** (which file is which group) for any differential comparison.

---

## 4. Step by step — run it

<!-- CAPTURE route=/ ; state=New data events list showing an LC-MS event (experiment type "proteomics", vendor Thermo, source LC-MS watcher) with Launch + Dismiss ; focus=instrument-event ; note=show an LC-MS New-data event card: raw file, vendor badge, proteomics/metabolomics experiment-type badge, Launch -->
*(Figure to add: an LC-MS New-data event — the raw file, vendor badge, the proteomics/metabolomics experiment-type badge, and the Launch button.)*

1. **Start from the data event (or ask).** Click **Launch** (opens a pre-filled draft, nothing runs yet), or
   type your goal **with the acquisition mode**, e.g. *"DDA label-free proteomics on these Thermo raw files,
   search against the human UniProt FASTA, treated vs. control"* or *"Untargeted metabolomics feature detection
   with XCMS on these mzML files, positive mode."*
2. **Check the workflow.** Confirm the panel opened the right pipeline for your mode (§2) — e.g.
   `nf-core/proteomicslfq` for DDA, `nf-core/dia_proteomics_analysis` for DIA, `xcms_lc_ms_preprocessing` for
   metabolomics. Not "undefined"; if it's the wrong one, restate your mode.
3. **Fill the key inputs:**
   - Proteomics: attach your spectra (`input`), attach the **FASTA** `database`, set `labeling_reagent`
     (`none` for label-free), leave FDR/tolerances at defaults unless you have a reason.
   - Metabolomics: attach the `.mzML` files, set **polarity**; defaults handle peak detection/alignment.
4. **Attach the sample/condition table** so the statistical step knows which files are which group.
5. **Confirm and run.** Click **Confirm & Run**. Expect a **long** run (this is real MS compute — proteomics DDA
   can need ~128 GB RAM). Watch phases move *pending → running → completed* in the Phases tab.

<!-- CAPTURE route=/ ; state=Workflow panel running for nf-core/proteomicslfq, phase cards (Input Validation, Database Search, Quantification, Statistical Analysis, QC, Report) with one running ; focus=workflow-panel ; note=show the multi-phase proteomics pipeline mid-run with a phase in the running state -->
*(Figure to add: the proteomics pipeline mid-run — the Database Search / Quantification / MSstats / QC phase cards, with one phase showing the running state.)*

---

## 5. Reading the result / report

Open the **After run** section (three tabs — see **Tutorial 3**):

**Proteomics (DDA/DIA):**
- **Summary** — the headline: how many **proteins identified**, and which are **differentially abundant** between
  your groups. Read the differential table by **fold change** (how many times up/down) plus an **FDR / adjusted
  p-value** (how confident — smaller is stronger; a common cut is FDR < 0.05). A protein with a big fold change
  *and* low FDR is a solid hit.
- **Outputs** — the **protein and peptide quantification matrices** (amount per protein per sample), the
  differential-abundance table, and QC plots (MultiQC / PTXQC). Downloadable for your figures.

**Metabolomics:**
- **Summary / Outputs** — the **feature table** (each row = one m/z × retention-time feature, with intensity per
  sample), plus any putative annotations (candidate metabolite names from HMDB/KEGG). *Caution:* an annotation
  from mass alone is a **putative identification**, not a confirmed compound — confirming an ID usually needs a
  matching standard or MS/MS evidence.
- **Reproducibility record** — the database/FASTA, FDR thresholds, tolerances, software versions, and outputs —
  the audit trail that makes the result defensible.

> **What good looks like, and what to watch.** In proteomics, a healthy run identifies a sensible number of
> proteins for your sample type and the QC plots look clean; be suspicious of very few IDs (often a wrong FASTA,
> wrong acquisition mode, or a bad conversion). In metabolomics, retention-time alignment should line the same
> feature up across samples; a feature present in only one of several replicates is usually noise.

---

## 6. Honest limits — what to expect (read this carefully)

- **Status: available, but NOT validated on real data end-to-end — this is the weakest-evidence instrument of
  the set.** The proteomics and metabolomics workflows named here are **real, indexed BioMate workflows**
  (confirmed in the catalogue — `nf-core/proteomicslfq`, `nf-core/dia_proteomics_analysis`, `proteomics_dda_
  search`, `nf-core/diaproteomics`, `xcms_lc_ms_preprocessing`, `metaMS`). But BioMate has **no recorded
  real end-to-end proteomics or metabolomics run** on the development site. Treat every result as *experimental*
  until you've checked it against a known dataset or your prior analysis. Do not report a proteomics/metabolomics
  number from BioMate as validated.
- **The connector label is a routing hint, not a literal workflow, and it guesses mode poorly.** The LC-MS
  watcher's internal defaults (an internal `diann_proteomics` / `xcms_metabolomics` tag) do **not** resolve
  verbatim to catalogue IDs, and the watcher cannot reliably tell **DDA from DIA** from a filename. **You** must
  state the acquisition mode when you Launch, or you may get the wrong pipeline (and wrong or empty results).
- **`.raw` → `.mzML` conversion may be needed first.** Thermo `.raw` conversion in particular depends on
  ProteoWizard/msconvert (Windows or the pwiz Docker container). If your lab's connector isn't set to
  auto-convert, convert before uploading, or your run may stall on an unreadable input.
- **Engine licensing matters for commercial use.** Some proteomics engines (e.g. DIA-NN, MSFragger, Spectronaut)
  are **not license-clean for commercial work**. If that applies to you, prefer the **license-clean** route
  (`proteomics_dda_search` with Comet/Sage/mokapot, or OpenSWATH-based DIA). Ask if unsure before running.
- **Metabolite IDs are putative.** Feature detection is reliable; turning a feature into a named compound from
  mass alone is a hypothesis, not a confirmed identification.
- **Lipidomics is a gap.** The connector has a `lipidomics` tag, but there is **no confirmed dedicated lipidomics
  workflow** in the catalogue; a lipidomics request may not route to a real pipeline. Stated plainly rather than
  faked.

---

## 7. Where to go next

| You want to… | Where |
|---|---|
| Connect the LC-MS instrument so runs arrive automatically | **Tutorial 6** |
| Convert/upload a single `.mzML` by hand | **Tutorial 4** |
| Understand the three-tab report | **Tutorial 3** |
| Integrate proteomics + metabolomics on the same samples | ask for **`Lc Ms Proteomics Metabolomics`** |
| Check a license-clean proteomics route | ask for **`proteomics_dda_search`** (Comet/Sage/mokapot) |

The habit: **Launch the LC-MS event → tell BioMate the mode (DDA/DIA) and proteins-vs-metabolites → attach your
FASTA / mzML + sample table → run (expect a long job) → read the quant + differential tables, treating results
as experimental.**

---

## 8. Key terms

| Term | What it means — and why you care |
|---|---|
| **m/z** | Mass-to-charge ratio — what the mass spectrometer measures to "weigh" a molecule. |
| **Retention time** | When a molecule comes off the chromatography column; the same molecule should elute at the same time across samples. |
| **DDA vs. DIA** | Two acquisition modes. DDA fragments the top peaks; DIA fragments everything in windows. **They need different pipelines — know yours.** |
| **FASTA database** | The list of protein sequences peptides are searched against (proteomics only). Wrong FASTA = few/no IDs. |
| **Label-free vs. TMT/iTRAQ** | Whether samples were chemically tagged for multiplexed quantification. Set via `labeling_reagent`. |
| **Feature (metabolomics)** | One m/z at one retention time, tracked across samples. The unit of untargeted metabolomics. |
| **FDR / adjusted p-value** | How confident a differential hit is; smaller is stronger (common cut-off 0.05). |
| **Putative annotation** | A candidate metabolite name from mass — a hypothesis, not a confirmed identity. |
| **msconvert / mzML** | ProteoWizard tool / vendor-neutral format most pipelines actually read. |

---

_Grounded in: `biomate-connector/lab_instruments/lcms_connector.py` (vendor detection + experiment-type →
workflow routing) and BioMate catalogue entries `nf-core/proteomicslfq`, `nf-core/dia_proteomics_analysis`,
`proteomics_dda_search`, `nf-core/diaproteomics`, `xcms_lc_ms_preprocessing`, `metaMS`, `Lc Ms Proteomics
Metabolomics` — all confirmed via workflow search. Validation-gap context: proteomics/metabolomics have no
verified real E2E run evidence. Companion: Tutorials 3, 4, 6._
