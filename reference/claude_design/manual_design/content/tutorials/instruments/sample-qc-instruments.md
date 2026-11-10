# Instrument tutorial — sample-QC & assay instruments (RIN / NanoDrop / cell counter / gel & blot imager)

> **Who this is for:** anyone who runs the small **sample-QC and assay** instruments that gate a wet-lab
> pipeline — an **Agilent Bioanalyzer / TapeStation** (RNA integrity, RIN), a **microvolume
> spectrophotometer / NanoDrop** (A260/280 & A260/230 purity), an **automated cell counter**
> (count + viability %), or a **gel & blot imager** (Western densitometry) — and wants each instrument's
> short export turned into **a defensible pass/fail call and a documented QC record**, with no coding.
> **Time:** ~12 minutes to read; each of these QC analyses runs in seconds to a minute (they are light
> compute — a single tidy table in, a pass/fail table out).
> **Where it fits:** Tutorial 6 (T6) explains how to *connect* an instrument so its files reach BioMate.
> This tutorial explains **what to do with the export once it is in BioMate** — how to turn it into a QC
> verdict and how that verdict gates the downstream pipeline the sample feeds (RNA-seq, proteomics, …).
> **Read the honest-status note in §6 first:** three of the four QC analyses are **built but not yet live
> in routing** on the development site. This tutorial states plainly what you can run today and what is
> pending.

---

## 1. What these instruments produce

Unlike a sequencer or a mass spectrometer, these instruments do **not** produce large primary-data files.
They produce **small tabular or image exports** whose only job is to answer one question: *is this sample
good enough to put into the expensive downstream run?* Each one measures a different quality axis.

- **Bioanalyzer / TapeStation (RNA integrity).** Agilent's 2100 Bioanalyzer and 4200/4150 TapeStation
  separate an RNA sample by fragment size and score its **integrity** — how intact the RNA is versus
  degraded. The headline number is the **RIN** (RNA Integrity Number, 1–10; RINe on TapeStation), with a
  **28S/18S** rRNA ratio, concentration, and for fixed tissue a **DV200** (percentage of fragments > 200 nt).
  Export: a per-sample **CSV** (and a PDF electropherogram).
- **Microvolume spectrophotometer / NanoDrop (nucleic-acid purity).** A Thermo NanoDrop (One / 2000 / 8000)
  or comparable instrument measures absorbance of 1–2 µL across the UV spectrum and reports **concentration**
  (ng/µL) plus two purity ratios: **A260/280** (protein / phenol contamination) and **A260/230** (guanidine,
  EDTA, carbohydrate carry-over). Export: a per-sample **CSV**.
- **Automated cell counter (count + viability).** A Countess 3 / 3 FL, LUNA, Cellometer, NucleoCounter or
  Vi-CELL counts cells (trypan-blue or fluorescent dye exclusion) and reports **total / live / dead
  concentration** (cells/mL), **viability %**, and **mean cell diameter**. Export: a per-sample **CSV**.
- **Gel & blot imager (Western densitometry).** A multi-function gel/blot imager photographs a stained gel
  or a chemiluminescent Western membrane. For a **Western blot**, the quantitative read-out is
  **densitometry** — the integrated intensity of each target band, normalised to a **loading control**
  (GAPDH, β-actin). Export: a **band image** (PNG / TIFF / JPEG).

**A number on a vendor screen is not a QC record.** A RIN of 6.4, or an A260/230 of 1.1, means nothing until
it is checked against an explicit threshold, written down with that threshold, and carried forward as a
*gate* on whatever the sample feeds next. Turning the export into **a pass/fail table + a durable, auditable
QC record** is what BioMate does here — and, importantly, each gate is the **entry condition** for a real
downstream pipeline (§5).

---

## 2. The BioMate analysis each instrument drives (and why)

Each instrument maps to one small, purpose-built QC workflow under
`backend/biomni_workflows/nextflow_nfcore/subworkflows/lab_automation/`. Every one is a *tolerant parser*:
it accepts the several column spellings different firmwares emit, recomputes derived fields when the export
omits them, applies a **configurable threshold**, and returns a tidy per-sample table, a machine-readable
JSON, and a human-readable summary. If no file is supplied it emits demonstration data so you can see the
output shape before wiring in your own export.

### 2a. RNA integrity → `lab_automation/rin_bioanalyzer_qc`

Ingests the Bioanalyzer / TapeStation per-sample CSV and calls pass/fail on a **configurable RIN threshold**
with a **DV200 fragment-size sanity check**.

- **Key parameters:** `bioanalyzer_csv` (the export), `rin_threshold` (default **7.0**),
  `dv200_min_pct` (default **30.0 %**), `assay_type` (`RNA` | `FFPE_RNA`).
- **The logic that matters:** for fresh RNA the gate is **RIN ≥ threshold** (DV200 advisory); for
  **FFPE / archival RNA** — where RIN is uninformative because the RNA is inherently fragmented — the gate
  switches to **DV200 ≥ minimum** instead (Illumina TruSeq RNA Access guidance). The workflow picks the right
  gate from `assay_type`, so you do not mis-fail degraded-but-usable fixed-tissue RNA.
- **Why RIN ≥ 7 matters downstream:** library preparation and transcript quantification assume reasonably
  intact RNA. A low RIN biases 3′ coverage and inflates technical variance, so **RIN < 7 is the standard flag
  for RNA-seq risk** — see §5.

### 2b. Nucleic-acid purity → `lab_automation/nanodrop_purity_qc`

Ingests the NanoDrop CSV and calls purity pass/fail against **nucleic-acid-type-specific** absorbance windows.

- **Key parameters:** `nanodrop_csv`, `nucleic_acid_type` (`DNA` | `RNA`),
  `min_conc_ng_ul` (default **10.0**), `a260_230_min` (default **2.0**).
- **The logic that matters:** the **A260/280** acceptance window is set by sample type — **1.7–2.0 for DNA,
  1.9–2.2 for RNA** (Thermo bulletin T042; Wilfinger 1997) — because the two have different intrinsic ratios.
  **A260/230 below ~2.0** flags organic carry-over (guanidine, phenol, EDTA) that inhibits enzymes
  downstream. If the export gives only raw A260 / A280 / A230 absorbances, the workflow **recomputes the
  ratios** itself, so partial exports still score.
- **Why purity matters downstream:** low A260/230 is a leading cause of failed library prep and inhibited
  PCR / reverse transcription — catching it here is far cheaper than discovering it after a sequencing run.

### 2c. Count + viability → `lab_automation/cell_counter_viability_qc`

Ingests the cell-counter CSV and gates on **viability** and a **live-cell-concentration floor**, with an
advisory cell-size window.

- **Key parameters:** `cellcount_csv`, `viability_min_pct` (default **80.0 %**),
  `min_live_conc` (cells/mL, default **100 000**), `diameter_min_um` / `diameter_max_um` (advisory,
  default **5–30 µm**).
- **The logic that matters:** a sample passes only if **viability ≥ minimum AND live concentration ≥ floor**.
  Mean diameter is **advisory** — out-of-window flags clumping or debris but does not by itself fail the
  sample. When the export omits viability or live count, the workflow **derives them** from the
  live / dead / total columns (e.g. viability = live ÷ total).
- **Why viability matters downstream:** single-cell and primary-cell assays degrade sharply below ~80–90 %
  viability (dead cells release ambient RNA and skew encapsulation), so this gate is the entry condition for
  the single-cell pipelines in §5.

### 2d. Western densitometry → `pharmacology/analyze_western_blot`

A **real image-densitometry** workflow: it reads the blot image, measures the integrated intensity of each
declared band region, and reports each target's expression **relative to a loading control**.

- **Key parameters:** `blot_image_path` (PNG / TIFF / JPEG), `target_bands`
  (a list of `{name, roi:[x, y, width, height]}` — one **region of interest** per target band, in pixels),
  `loading_control_band` (one `{name, roi}` for GAPDH / β-actin), `antibody_info` (primary/secondary record,
  carried into the report for provenance).
- **The logic that matters:** for each ROI the workflow sums grayscale intensity, then computes
  **relative expression = target intensity ÷ loading-control intensity** — the standard loading-normalised
  Western read-out. Output is a `Protein, Raw Intensity, Relative Expression` table plus a research log.
- **Important limitation — band regions are manual.** The workflow quantifies the ROIs *you* give it; it does
  **not** automatically detect lanes or bands. You must supply the pixel ROI for each band (read them off the
  image, e.g. in the imager software or any viewer). Automatic lane-profile detection (Fiji/ImageJ-style) is a
  known gap — see §6. And note this is **blot** densitometry: there is **no** workflow that does densitometry
  on a photographed **DNA/protein gel** (§6).

| Instrument | QC question it answers | BioMate workflow | Primary gate |
|---|---|---|---|
| Bioanalyzer / TapeStation | Is my RNA intact enough? | `lab_automation/rin_bioanalyzer_qc` | RIN ≥ 7 (or DV200 for FFPE) |
| NanoDrop / microvolume spec. | Is my nucleic acid pure & concentrated enough? | `lab_automation/nanodrop_purity_qc` | A260/280 in window, A260/230 ≥ 2.0 |
| Automated cell counter | Are enough of my cells alive? | `lab_automation/cell_counter_viability_qc` | Viability ≥ 80 %, live conc ≥ floor |
| Gel & blot imager | How much of my protein, vs a loading control? | `pharmacology/analyze_western_blot` | Relative expression vs GAPDH/β-actin |

---

## 3. Before you start — get the data in (see T6), then run it

### Get the export into BioMate

These instruments produce a **small file**, so getting the data in is simple: **upload the instrument's
export** from the Data area — the per-sample **CSV** (Bioanalyzer / NanoDrop / cell counter) or the **band
image** (PNG / TIFF / JPEG, for the blot). If your vendor software exports a **PDF** report (common for the
Bioanalyzer), export or save the per-sample **CSV / tabular** view alongside it — the parser reads the
tabular export, not the PDF electropherogram picture. How connection and automatic ingestion will work in a
core-facility setting is the subject of **Tutorial 6**; this tutorial assumes the file is already in BioMate.

**What you must have ready:**
- **RIN:** the Bioanalyzer / TapeStation per-sample CSV; know whether the RNA is **fresh** or **FFPE** (sets
  `assay_type`).
- **NanoDrop:** the per-sample CSV; know whether the sample is **DNA or RNA** (sets the A260/280 window).
- **Cell counter:** the per-sample CSV; decide your **viability threshold** (default 80 %) and **live-cell
  floor** for the downstream assay.
- **Western:** the band image, plus the **pixel ROI** of each target band and of the loading control, and the
  antibody details for the record.

### Run it

1. **Ask in chat, or pick the workflow card.** State the instrument and the gate, e.g. *"RIN QC on this
   Bioanalyzer CSV, fail anything under 7"*; *"NanoDrop purity QC on this CSV, these are RNA samples"*;
   *"cell-counter viability QC, minimum 85 % viability"*; *"Western densitometry on this blot, GAPDH as the
   loading control."*
2. **Check the panel opened the right QC workflow** (§2) and shows the correct name — not "undefined".
   **See §6:** for the three `lab_automation` QC parsers this routing is **pending on the development site**,
   so if the card does not appear, that is the known registration gap, not a mistake on your part.
3. **Fill the key parameters.** Set the threshold you want to gate on (`rin_threshold`, the A260/280 window via
   `nucleic_acid_type`, `viability_min_pct`, …). The defaults encode the standard cut-offs above; override them
   only when you have a protocol-specific reason.
4. **Confirm & Run.** These are light jobs — expect a result in seconds to about a minute. Watch the phase move
   *pending → running → completed*.

---

## 4. Reading the outputs

Every QC workflow writes the **same three-file shape**, so once you have read one you can read them all:

- **a per-sample CSV** — one row per sample with the measured values, the `qc_pass` boolean, and a
  `fail_reason` naming exactly which threshold was missed (e.g. `A260/230=1.1 < 2.0`). This is the table you
  file as the **QC record** and attach to the downstream run.
- **a results JSON** (`*_qc_results.json`) — the same data plus a **batch summary** (`n_pass` / `n_fail`,
  pass-rate %, and a `batch_qc_status` of **PASS** when every sample passes or **REVIEW** when any fails).
  This is the machine-readable gate a downstream pipeline reads.
- **a human-readable summary** (`*_summary.txt`) — the thresholds used and a one-line verdict per sample.

What each adds on top:

- **RIN** (`rin_per_sample.csv`, `rin_qc_results.json`, `rin_summary.txt`): columns `RIN`, `28S/18S`,
  `concentration_ng_ul`, `DV200_pct`, the `gate` actually applied (RIN vs DV200), plus `mean_rin` in the
  summary. A FAIL row tells you *why* (RIN below threshold, or DV200 below minimum for FFPE).
- **NanoDrop** (`nanodrop_per_sample.csv`, …): columns `concentration_ng_ul`, `A260`, `A280`, `A230`,
  `A260/280`, `A260/230`. A FAIL names the offending axis — low concentration, 260/280 outside the window, or
  260/230 carry-over — so the corrective action (re-purify vs re-elute vs re-quantify) is unambiguous.
- **Cell counter** (`cellcount_per_sample.csv`, …): columns `total/live/dead_cells_ml`, `viability_pct`,
  `mean_diameter_um`, plus a separate **`size_warning`** when diameter is out of window (clumping/debris) —
  distinct from a hard fail.
- **Western** (`analyze_western_blot_results.json`, `western_blot_results.csv`,
  `analyze_western_blot_output.txt`): the `Protein, Raw Intensity, Relative Expression` table (loading control
  fixed at 1.0) and a research log recording the antibodies and steps.

> **What good looks like, and what to watch.** A clean batch is `batch_qc_status: PASS` with every sample's
> `fail_reason` empty. Treat a **REVIEW** status as a stop-and-look, not an automatic discard: read each
> `fail_reason`, because a single borderline sample (RIN 6.8 against a 7.0 cut) is a judgement call, whereas a
> whole batch failing A260/230 points at an extraction problem upstream. For the Western, a loading-control
> intensity near zero or wildly uneven across lanes usually means the ROIs are mis-placed — re-check the pixel
> regions before trusting the relative-expression numbers.

---

## 5. BioMate also offers — how these gates feed the real downstream pipelines

The point of a QC gate is the pipeline **behind** it. A core facility running these instruments feeds samples
into BioMate's main analysis catalogue, and each QC verdict above is the entry condition for one of them:

- **RIN (and NanoDrop) → bulk RNA-seq differential expression.** RNA that passes RIN and purity QC is the
  input to the validated **`nf-core/rnaseq` → DESeq2** differential-expression chain (transcriptomics — the
  facility's sequencer path; see the *BaseSpace / sequencing* tutorial). **RIN < 7 is the standard flag that a
  sample is a quality risk for RNA-seq**, so this QC gate is literally the front door of that pipeline.
- **NanoDrop → WGS / variant calling and qPCR.** DNA that passes purity QC feeds the **WGS Germline GATK**
  pipeline and, for targeted work, **`normqpcr` ΔΔCq** quantification — both sensitive to the carry-over that
  A260/230 catches.
- **Cell-counter viability → single-cell and flow pipelines.** Viable-cell suspensions feed the single-cell
  RNA-seq pipelines (Seurat / Scanpy / STARsolo, with CellBender ambient-RNA removal) and the
  **flow-cytometry immunophenotyping** workflow (flowCore / FlowSOM; see the *flow cytometry* tutorial) —
  both of which assume the ≥ 80 % viability this gate enforces.
- **Western densitometry → the proteomics and pharmacology catalogue.** Relative-expression read-outs sit
  alongside BioMate's mass-spec proteomics pipelines (`nf-core/proteomicslfq`, `nf-core/diaproteomics`; see
  the *LC-MS proteomics / metabolomics* tutorial) and the plate-reader dose-response / hit-calling assays for
  functional follow-up.

In other words, these four small instruments are not a side-show: they are the **quality front-end** of the
facility's transcriptomics, genomics, single-cell, proteomics and assay workflows. Running QC in the same
system that runs the downstream analysis is what lets a RIN/purity/viability verdict travel with the sample
as a documented gate rather than a sticky note.

---

## 6. Honest status — what you can run today, and what is pending

- **The three `lab_automation` QC parsers (RIN, NanoDrop, cell counter) are BUILT but NOT YET LIVE in
  routing.** The workflow files exist in the repository (PR #226) and are grounded in the standard references
  (Schroeder 2006 for RIN; Thermo T042 / Wilfinger 1997 for NanoDrop ratios; trypan-blue dye-exclusion for
  viability). **However, they are pending dev-database registration**, which means that on the development site
  the chat router may **not yet surface them** when you ask. Treat them as **available in-repo and ready, but
  not confirmed to route end-to-end on dev**. If the workflow card does not appear, that is this registration
  gap — the fix is a one-step DB re-index on dev, not a change to how you use them. Do not report a QC result
  from these as a validated production run until routing is confirmed live.
- **Western densitometry is a real workflow, but band regions are manual, and it does Western *blots* only.**
  `pharmacology/analyze_western_blot` performs genuine image densitometry, but it quantifies the **pixel ROIs
  you provide** — it has **no automatic lane/band detection**. Supplying accurate ROIs is on you. Proper
  automated lane-profile densitometry (Fiji / ImageJ-style) is a recognised upgrade gap (**B9** in the
  facility inventory).
- **There is NO densitometry for a photographed DNA/protein gel.** The only "gel" workflow in the catalogue,
  `genetics/perform_pcr_and_gel_electrophoresis`, is an **in-silico simulation** — it predicts band positions
  from a DNA **sequence** and primers, i.e. it *draws* an expected gel, it does **not analyse a real gel
  image** from the imager. If you need lane densitometry on an actual agarose/SDS-PAGE gel photograph, that
  capability does not exist today; use the Western-blot path for membrane densitometry, and treat gel-image
  quantification as a gap.
- **Connection / automatic ingestion is out of scope here.** This tutorial assumes you uploaded the export.
  How a core facility wires an instrument's output folder to BioMate is **Tutorial 6**, and should not be
  inferred from anything above.

---

## 7. Where to go next

| You want to… | Where |
|---|---|
| Connect an instrument so its exports arrive automatically | **Tutorial 6** |
| Upload a single CSV / image by hand | **Tutorial 4** |
| Understand the results panel / report tabs | **Tutorial 3** |
| Run the RNA-seq pipeline your RIN-passed samples feed | *BaseSpace / sequencing* tutorial (`nf-core/rnaseq` → DESeq2) |
| Run single-cell analysis on your viability-passed cells | ask for the **single-cell RNA-seq** workflow (Seurat / Scanpy) |
| Quantify a dose-response plate | *plate-reader assays* tutorial (Z′ / 4PL hit calling) |

The habit: **upload the small export → ask for the matching QC workflow → set the threshold you want to gate
on → run (seconds) → file the per-sample CSV + batch-status JSON as the QC record that travels with the
sample into its downstream pipeline.**

---

## 8. Key terms

| Term | What it means — and why you care |
|---|---|
| **RIN / RINe** | RNA Integrity Number (1–10). How intact the RNA is; **< 7 flags RNA-seq quality risk**. RINe is the TapeStation variant. |
| **DV200** | Percentage of RNA fragments longer than 200 nt. The integrity gate for **FFPE / degraded** RNA, where RIN is uninformative. |
| **28S/18S ratio** | Ratio of the two ribosomal RNA peaks; ~2.0 indicates intact total RNA. |
| **A260/280** | Purity ratio; protein / phenol contamination. Target **~1.8 for DNA, ~2.0 for RNA**. |
| **A260/230** | Purity ratio; organic / salt carry-over (guanidine, phenol, EDTA). Target **~2.0–2.2**; low values inhibit enzymes. |
| **Viability %** | Fraction of live cells (dye exclusion). Downstream single-cell / flow assays expect **≥ 80–90 %**. |
| **Live-cell concentration** | Live cells per mL; must clear a **floor** so the downstream assay has enough input material. |
| **Densitometry** | Measuring band intensity from a blot/gel image to quantify how much protein (or DNA) is present. |
| **ROI (region of interest)** | The pixel rectangle `[x, y, width, height]` defining one band for Western densitometry — supplied manually. |
| **Loading control** | A housekeeping protein (GAPDH, β-actin) used to normalise Western band intensities across lanes. |
| **batch_qc_status** | The batch verdict: **PASS** (all samples pass) or **REVIEW** (at least one failed — read its `fail_reason`). |

---

_Grounded in the real workflow files `backend/biomni_workflows/nextflow_nfcore/subworkflows/lab_automation/
{rin_bioanalyzer_qc,nanodrop_purity_qc,cell_counter_viability_qc}/main.nf` (params / steps / outputs read
directly) and `…/pharmacology/analyze_western_blot/main.nf`; status per
`docs/20260920_HOSPITAL_INSTRUMENT_RESOURCE_INVENTORY.md` §2 (RIN / NanoDrop / cell-counter = 🆕 B8 built,
pending dev DB registration; Western densitometry real, B9 upgrade for automated lane detection; the only gel
workflow is `genetics/perform_pcr_and_gel_electrophoresis`, an in-silico simulation). Companion: Tutorials 3,
4, 6, and the sequencing / flow-cytometry / plate-reader instrument tutorials._
