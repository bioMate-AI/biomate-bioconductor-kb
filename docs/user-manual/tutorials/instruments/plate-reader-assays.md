# Instrument tutorial — plate reader → dose–response, IC50 & assay quantification

> **Who this is for:** anyone who runs a microplate reader (BMG FLUOstar/CLARIOstar/PHERAstar, BioTek/Agilent
> Synergy, Molecular Devices SpectraMax, Tecan Spark, PerkinElmer EnSpire) and wants its plate of numbers turned
> into **"what's the IC50/EC50 of my compound"**, **"how much analyte is in each well (ELISA)"**, or
> **"what's the reaction rate"** — no coding needed.
> **Time:** ~10 minutes to read; a run is quick (curve fitting on a small table, not a heavy pipeline).
> **Where it fits:** Tutorial 6 (T6) explains how to *connect* a plate reader so its files reach BioMate. This
> tutorial explains **the analyses that data drives, how to run them, and how to read them.**

---

## 1. What this instrument produces

A plate reader measures a signal in every well of a 96- or 384-well plate. The signal is one of:

- **Absorbance** (optical density, OD) — e.g. OD450 for a colorimetric ELISA, OD600 for cell density.
- **Fluorescence** — a dye or reporter glows; brighter = more of whatever you're measuring.
- **Luminescence** — e.g. a CellTiter-Glo (CTG) viability assay where light ∝ live cells.

It can read **once** (an endpoint) or **repeatedly over time** (kinetic). The software (Gen5, MARS, SoftMax Pro,
SparkControl…) exports a `.csv`/`.txt`/`.xlsx` grid of wells × values, often with a header naming the wavelength,
read type, and plate format.

**A plate of raw numbers is not the answer.** The biology comes from *fitting a model* to those numbers:
a **dose–response curve** to get an IC50, a **standard curve** to turn ELISA signal into concentration, or a
**rate** from the kinetic slope. That fitting is the analysis BioMate runs.

---

## 2. The BioMate analysis it drives (and why)

What BioMate runs depends on what the plate *was*:

### 2a. Dose–response / IC50 / EC50 (the most common)

You tested a compound at several concentrations (a dilution series) and measured a response. You want the
concentration that gives half-maximal effect.

→ **`Dose Response`** (BioMate's `biochemistry` domain): fits a **4-parameter logistic (4PL / Hill)** curve — or
5PL for asymmetric curves — and reports **IC50** (for inhibition) or **EC50** (for activation). Key inputs:
`data` (your CSV/TSV), `concentration_col` and `response_col` (which columns hold dose and signal), `model`
(`LL.4` = 4PL, `LL.5` = 5PL), and `response_type` (`inhibition` → IC50, `activation` → EC50).

*Why a curve, not just a number:* a single well can't give an IC50 — potency is the *shape* of how response
changes with dose. The 4PL fit summarises that shape in a few interpretable numbers (top, bottom, slope, IC50).

### 2b. Screening a whole plate for hits (HTS)

You screened many compounds (one per well, plus control columns) and want to know which are "hits" and whether
the plate itself was any good.

→ **`Hts Plate Qc Hit Calling`** (`drug_discovery`): takes raw plate signal + controls, computes **Z-factor /
Z′-factor** (a 0–1 score of assay quality — see §5), normalises to **% activity/inhibition**, applies a hit
threshold, and fits 4PL dose–response where replicate concentration data exist. Key inputs: `plate_data_json`,
`hit_threshold_pct` (default 50), `hit_direction` (`inhibition`/`activation`), `min_z_prime` (default 0.5).

### 2c. Enzyme kinetics / ELISA / viability

| What you ran | Workflow BioMate offers |
|---|---|
| Enzyme kinetic read (rate, Km, Vmax) | **`Analyze Enzyme Kinetics Assay`** (`biochemistry`) |
| Cell viability (MTS/MTT/CTG) → IC50 / GI50 | **`Dose Response`** (fit viability vs. dose) |
| ELISA / immunoassay (signal → concentration) | standard-curve fit via the dose–response / enzyme-kinetics path (see §6) |
| Automated multi-step drug-response processing | `gdr_automated_drug_response_pipeline` (`pharmacology`) |

> **Honest note up front:** the plate-reader *connector* guesses the assay type from the file/folder name and the
> header (wavelength, "kinetic", "MTT", "IC50", "ELISA"…) and tags the file with an internal routing label. That
> tag is a **hint** — when you Launch, say what the assay was (e.g. "this is a cell-viability dose–response") so
> BioMate routes to the right fit above. See §6 for validation status.

---

## 3. Before you start — get the data in (see T6)

- **Connect the plate reader (best for regular use).** Register a **Plate reader** instrument in **Connectors →
  Instruments**; your admin points its file-watcher at your Gen5/MARS/SoftMax Pro export folder. Finished plates
  appear as **New data events**. Full steps: **Tutorial 6**.
- **Upload by hand (one-off).** Export a `.csv` and bring it in from the Data area. Full steps: **Tutorial 4**.

**What your file needs**, for a dose–response: a **concentration** column (your doses) and a **response** column
(the signal), with the dilution series laid out so BioMate can pair dose to response. Know your **units**
(e.g. µM, nM) and whether the effect is **inhibition or activation**. For plate screening, include your
**positive and negative control** wells — the Z′-factor QC needs them.

---

## 4. Step by step — run it

<!-- CAPTURE route=/ ; state=New data events list showing a plate-reader event (assay type "dose response", vendor BMG, 96-well) with Launch + Dismiss ; focus=instrument-event ; note=show a plate-reader New-data event card: file name, vendor badge, assay-type + plate-format badge, Launch -->
*(Figure to add: a plate-reader New-data event — the exported file, vendor badge, the "dose response" assay-type badge, plate format, and the Launch button.)*

1. **Start from the data event (or ask).** Click **Launch** (opens a pre-filled draft, nothing runs yet), or
   type your goal, e.g. *"Fit a 4-parameter dose–response and report the IC50 for this inhibition assay;
   concentration in column 'dose_uM', signal in column 'pct_inhibition'."*
2. **Check the workflow.** Confirm the panel opened the intended fit — **Dose Response** for IC50/EC50,
   **Hts Plate Qc Hit Calling** for a screening plate, **Analyze Enzyme Kinetics Assay** for a rate. Not
   "undefined"; if wrong, say which assay it was.
3. **Point it at the right columns / settings:**
   - **`concentration_col`** and **`response_col`** — the exact column names for dose and signal (from your file).
   - **`model`** — `LL.4` (4PL, the usual choice) or `LL.5` (5PL, for asymmetric curves).
   - **`response_type`** — `inhibition` (→ IC50) or `activation` (→ EC50).
   - For a screening plate: **`hit_threshold_pct`**, **`hit_direction`**, **`min_z_prime`**.
4. **Attach the plate file** if not already linked, then **Confirm & Run** (fast).

<!-- CAPTURE route=/ ; state=Workflow panel pre-run for Dose Response, param strip showing concentration_col, response_col, model (LL.4), response_type (inhibition) ; focus=workflow-panel ; note=show pre-run dose-response panel: the column mappings + model + response_type, Confirm & Run -->
*(Figure to add: the pre-run Dose Response panel — concentration/response column mappings, 4PL model, inhibition/activation choice, and Confirm & Run.)*

---

## 5. Reading the result / report

Open the **After run** section (two tabs — see **Tutorial 3**):

- **Summary** — the headline number:
  - **IC50 / EC50** — the concentration giving half-maximal effect. **Lower IC50 = more potent** inhibitor. Read
    it in your units (e.g. "IC50 = 120 nM").
  - **Hill slope** — how steep the curve is (how sharply response changes with dose).
  - For a screening plate: the **hit list** and the **Z′-factor** (plate quality).
- **Outputs** — the fitted parameters, the curve points, and (for screens) per-well % activity and hit flags,
  filed under the producing step; downloadable for figures.
- **Reproducibility record** — the model, columns, and software version used — so the fit is documented.

> **How to judge a fit (don't just take the IC50).**
> - **Z′-factor** (screening): **> 0.5 = an excellent, robust assay**; 0–0.5 = marginal; < 0 = your positive and
>   negative controls overlap, so **don't trust hits from that plate**. This is the single most important QC
>   number in plate screening.
> - **Curve shape:** a trustworthy IC50 sits where you actually have data points on both the top (no effect) and
>   bottom (full effect) **plateaus**. If your highest dose never reached a plateau, the reported IC50 is an
>   extrapolation — treat it as "greater than your top dose", not a precise value.
> - **Replicates:** an IC50 from triplicate points with tight error bars is solid; from single points it's
>   indicative only.

---

## 6. Honest limits — what to expect

- **Status: available, not yet validated on real data end-to-end.** `Dose Response`, `Hts Plate Qc Hit Calling`,
  and `Analyze Enzyme Kinetics Assay` are **real, indexed BioMate workflows** (confirmed in the catalogue, with
  real parameter schemas and QC settings). But BioMate has **no recorded real end-to-end plate-reader run** on
  the development site, and plate-reader coverage is known to be thin. Treat results as *available-but-untested*:
  verify your first IC50 against a value you compute in GraphPad/Prism or your usual tool before trusting it.
- **The connector label is a routing hint, not a literal workflow.** The watcher's internal assay tags
  (`dose_response`, `cell_viability_ic50`, `elisa_quantification`, etc.) do **not** resolve verbatim to
  catalogue IDs; BioMate routes your Launch to the real fit by matching your request. State your assay type to
  steer it.
- **ELISA has no dedicated standard-curve workflow of its own.** An ELISA (signal → concentration via a standard
  curve) is handled by re-using the dose–response / enzyme-kinetics fitting rather than a bespoke ELISA pipeline.
  It works in principle, but confirm the standard-curve fit and back-calculated concentrations yourself. Stated
  plainly rather than overclaimed.
- **You must map the columns.** The workflow needs to know **which column is dose and which is response** — it
  does not reliably guess plate layout. If your export is a raw well grid rather than tidy dose/response columns,
  reshape it (or ask BioMate to) first.
- **Garbage-in on controls breaks screening QC.** The Z′-factor is only meaningful if your positive/negative
  control wells are correctly labelled and real; mislabeled controls give a misleading quality score.

---

## 7. Where to go next

| You want to… | Where |
|---|---|
| Connect the plate reader so runs arrive automatically | **Tutorial 6** |
| Bring a single plate file in by hand | **Tutorial 4** |
| Understand the two-tab report | **Tutorial 3** |
| Screen a whole plate and QC it | ask for **`Hts Plate Qc Hit Calling`** |
| Fit enzyme kinetics (Km/Vmax) | ask for **`Analyze Enzyme Kinetics Assay`** |
| Take a hit forward to ADMET/safety screening | the **BioMate drug-discovery (ADMET) flow** (see the main run tutorial, T3) |

The habit: **Launch the plate event → confirm the right fit (dose–response / screen / kinetics) → map your
dose and response columns → run → read the IC50 and check Z′/curve shape.**

---

## 8. Key terms

| Term | What it means — and why you care |
|---|---|
| **Absorbance / OD** | How much light a well absorbs (e.g. OD450 ELISA, OD600 cell density). A common plate signal. |
| **Endpoint vs. kinetic** | A single read vs. repeated reads over time. Kinetic reads give rates. |
| **Dose–response curve** | Response plotted against dose; its shape defines potency. One well can't give it. |
| **IC50 / EC50** | Concentration for half-maximal inhibition / activation. **Lower IC50 = more potent.** |
| **4PL / Hill (LL.4)** | The 4-parameter logistic model fitted to a dose–response curve (top, bottom, slope, IC50). |
| **Z-factor / Z′-factor** | A 0–1 assay-quality score. **>0.5 = excellent**; <0 = controls overlap, don't trust hits. |
| **Standard curve** | A reference dilution series used to turn ELISA signal into concentration. |
| **Km / Vmax** | Enzyme-kinetics parameters (substrate affinity / max rate) from a kinetic read. |

---

_Grounded in: `biomate-connector/lab_instruments/plate_reader_connector.py` (assay-type → workflow routing) and
BioMate catalogue entries `Dose Response` (biochemistry), `Hts Plate Qc Hit Calling` (drug_discovery),
`Analyze Enzyme Kinetics Assay` (biochemistry), `gdr_automated_drug_response_pipeline` (pharmacology) — all
confirmed via workflow search. Companion: Tutorials 3, 4, 6._
