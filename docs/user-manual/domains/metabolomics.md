# Metabolomics (untargeted LC-MS)

> One-line promise: go from raw LC-MS runs (mzML) to a table of **metabolic
> features** (m/z × retention-time peaks), a **consensus list of the features that
> separate your groups**, and annotations for what those features might be — so
> you end with candidate biomarkers, not a spectra dump.
> For: **wet-lab metabolomics researchers / PIs** running untargeted profiling
> (urine, plasma, tissue) and **bioinformaticians** who want the xcms → CAMERA →
> multi-method feature-selection pipeline run and reported for them. No coding
> required.

<!--
P2 chapter. Every "supported" claim below is green in coverage-ledger.md § "Metabolomics (untargeted LC-MS)".
Honesty rule (IMPORTANT): metabolomics has NO code-enforced QC gate in qc_trace_monitor.py — every metabolomics
QC number in the tutorial spec (QC-CV ≤30%, peak count 3k–15k, classifier accuracy ≥0.70) is SPEC-ONLY / advisory.
This chapter states that plainly rather than implying enforced gates. The chain uses biosigner for consensus
feature selection; HMDB (biodbHmdb) exists as an annotation database but is NOT a step in the gold chain — the
task's "→ HMDB" is documented honestly as an available-but-separate annotation option. Anything not built is in
"What's not covered".
-->

## What this is for

This is the **"which small molecules differ between my groups"** path for
untargeted LC-MS metabolomics. You profiled samples without a predefined target
list, you have a phenotype to compare (gender, disease, treatment), and you want
the features that discriminate the groups — and ideally a chemical identity for
them.

BioMate runs the standard untargeted consensus pipeline:

1. **Peak detection + alignment** — turn raw chromatograms into a feature table
   (m/z, retention time, intensity per sample) with **xcms** (centWave).
2. **Isotope / adduct annotation** — group peaks that are isotopes or adducts of
   the same compound with **CAMERA**, so you don't count one molecule as several
   features.
3. **Consensus feature selection** — find the features that separate your groups
   robustly across **three classifiers** (PLS-DA, Random Forest, SVM) with
   **biosigner**, so your biomarker list isn't an artifact of one method.

The through-line is interpretation: the worked example ends on a *decision* (these
features discriminate, these are the likely metabolites), not a process tree.

> **Tip** — Untargeted metabolomics is inherently exploratory: xcms will find
> thousands of features, most of which are noise, isotopes, or adducts. The value
> of this pipeline is the *funnel* — CAMERA collapses redundancy and biosigner
> keeps only features that hold up across three independent classifiers. Trust the
> consensus list, not the raw feature count.

## Use cases

| Goal (researcher's words) | Workflow(s) / chain | Inputs | Outputs (artifact) | Lane |
|---|---|---|---|---|
| "Untargeted metabolomics: which features separate my groups" | chain **`lcms_metabolomics_consensus`**: xcms (id **12631**, centWave) → CAMERA (id **11032**) → biosigner (id **10990**, PLS-DA + RF + SVM) | mzML files + sample metadata + phenotype column | Differential-features TSV + consensus-selection RDS + annotation HTML report | Cloud (AWS Batch) |
| "Annotate my features against a metabolite database (HMDB)" | `biodbHmdb` (id **10977**) or `metaboannotation` (id **11773**) | Feature table (m/z, RT) | Annotated features (candidate metabolite IDs) | Cloud |
| "Run the nf-core metabolomics pipeline end-to-end" | `nf-core/metaboigniter` (id **12731**) | Raw/mzML + design | Feature table + annotation | Cloud |
| "1D-NMR quantification / deconvolution" | `asics` (id **10905**) | NMR spectra | Quantified metabolite table | Cloud |

> **Pitfall — the consensus chain does not annotate to HMDB.** The gold chain is
> xcms → CAMERA → **biosigner** (feature *selection*). It tells you *which m/z×RT
> features discriminate*, not *what molecule they are*. Chemical annotation
> against HMDB is a **separate** step (`biodbHmdb` id 10977, or `metaboannotation`
> id 11773) you run on the feature table. Document the two-step reality: select
> discriminating features, then annotate the shortlist.

## How to ask

BioMate routes on intent. The disambiguation that matters here is **untargeted vs
targeted**, **LC-MS vs NMR**, and **feature selection vs annotation**.

Untargeted consensus DE (the gold chain):

> "Untargeted metabolomics multi-method analysis." — or —
> "LC-MS metabolomics differential analysis with consensus feature selection,
> phenotype = gender."

The chain triggers on metabolomics context — its example queries include
*"LC-MS metabolomics differential analysis"*, *"mass spec metabolomics with
consensus feature selection"*, *"xcms camera biosigner pipeline for
metabolomics"*, *"untargeted metabolomics multi-method analysis"*
(`backend/lib/galaxy/ai/chain_composer/proposed_chains/lcms_metabolomics_consensus.json`).

**Disambiguation to avoid:**

- **Untargeted vs targeted.** This chapter is **untargeted** (discover features
  without a predefined panel). Targeted quantification of a known metabolite list
  is a different design; say "untargeted" to get xcms peak detection.
- **LC-MS vs NMR.** The consensus chain is **LC-MS** (mzML). For NMR data, the
  correct tool is **ASICS** (id 10905, spectral deconvolution/quantification), not
  xcms. Name the platform.
- **Feature selection vs annotation.** "Which features differ" = biosigner
  consensus (the chain). "What are these features" = HMDB/metaboannotation. If you
  want both, say so — you'll run the chain, then annotate the shortlist.

> **Tip — name the phenotype column.** biosigner needs to know which sample
> metadata column defines the groups (e.g. `gender`, `condition`). State it in the
> prompt so the classifiers train on the right contrast.

## Tools & workflows behind this

| Tool / workflow | Role | Where (verified) |
|---|---|---|
| Chain `lcms_metabolomics_consensus` | 3-step: peak detection → annotation → consensus selection | `backend/lib/galaxy/ai/chain_composer/proposed_chains/lcms_metabolomics_consensus.json`; DB `workflow_chains` |
| `xcms` (id **12631**) | centWave peak picking + RT correction + grouping | DB id 12631; chain step 1 (`method=centWave`) |
| `camera` (id **11032**) | Isotope + adduct annotation (collapse redundant peaks) | DB id 11032; chain step 2 |
| `biosigner` (id **10990**) | Consensus feature selection across PLS-DA + RF + SVM | DB id 10990; chain step 3 (`methods=[plsda, rf, svm]`) |
| `biodbHmdb` (id **10977**) | HMDB metabolite annotation (separate step) | DB id 10977 |
| `metaboannotation` (id **11773**) | Feature-to-compound annotation | DB id 11773 |
| `nf-core/metaboigniter` (id **12731**) | Full nf-core LC-MS pipeline | DB id 12731 |
| `asics` (id **10905**) | 1D-NMR quantification (NMR, not LC-MS) | DB id 10905 |

The chain's hand-off is real: xcms's `xcms_set` feeds CAMERA's `xcms_set`;
CAMERA's `annotated_features` feeds biosigner's `feature_table` (chain JSON
`connections`). The xcms/CAMERA/biosigner family is part of a large
alternative-substitution cluster, so a step's role can be swapped for another
cluster member when the design calls for it (chain `description`).

> **License** — xcms, CAMERA, biosigner, and the HMDB/metabolomics Bioconductor
> packages are open-source academic tools; results are yours. HMDB and MassBank
> annotations are the standard public releases.

## QC gates & how to read them

**Honest statement up front: metabolomics has no code-enforced QC gate in
BioMate's pipeline monitor.** Unlike proteomics (FDR/CV gates) or ATAC-seq (TSS
enrichment), there is no `_parse_metabolomics_metrics` and no metabolomics branch
in the QC verdict logic (`qc_trace_monitor.py`). The QC numbers below come from
the **tutorial / gold-standard spec** and are **advisory quality checks you read
yourself** — the system does not halt on them.

| Check | Target (spec) | What it tells you | Status |
|---|---|---|---|
| **QC-sample CV** | ≥ 70% of features with **CV ≤ 30%** | Analytical reproducibility — pooled QC samples injected repeatedly should give consistent intensities. High CV = instrument drift or poor sample prep. | **Spec / advisory** — not code-enforced; read from the xcms QC output |
| **Peak count** | ∈ **[3k, 15k]** for urine LC-MS | Sanity range — far below means detection is too strict; far above means too much noise. | **Spec / advisory** — read from the feature table |
| **biosigner classifier accuracy** | ≥ **0.70** (cross-validated) | Whether the consensus signature actually discriminates your groups. Below 0.70, the "biomarkers" don't separate the phenotype. | **Spec / advisory** — read from the biosigner output |

**How to read each:**

- **QC-sample CV** — the reproducibility anchor. Inject pooled QC samples
  throughout the run; if ≥ 70% of features have CV ≤ 30% across them, the platform
  was stable. If not, treat every downstream difference with suspicion — it could
  be drift, not biology.
- **Peak count** — a sanity band, not a hard rule. A urine run returning 300
  features (too few) or 40,000 (mostly noise) signals a mis-set detection
  parameter. The gold-standard urine run lands around 5,000 after CAMERA.
- **biosigner accuracy** — the "does my signature mean anything" check. biosigner
  reports cross-validated accuracy per classifier; a consensus that clears 0.70
  across PLS-DA/RF/SVM is a signature worth annotating.

> **Pitfall — no gate will stop a bad metabolomics run for you.** Because there is
> no code-enforced metabolomics QC gate, a drifting instrument or an over-loose
> peak-detection setting will produce a full feature table and a biosigner
> signature *without any automatic flag*. You must read the QC-sample CV and the
> classifier accuracy yourself before trusting the biomarker list. This is the
> most important honesty point in the chapter.

### What "fixing" a QC issue looks like here

There is **no metabolomics auto-loop**. Issues are surfaced (in the outputs, not
as a halt) for you to correct and re-run:

- High QC-sample CV → check for instrument drift / batch effects; consider
  signal-drift correction and re-run.
- Peak count out of band → adjust xcms centWave parameters (ppm, peak width) and
  re-run peak detection.
- Low classifier accuracy → the phenotype may not be metabolically separable, or
  the design is confounded; re-check the metadata and contrast.

## Worked example (gold standard)

**Goal.** Run the untargeted consensus pipeline on a benchmark where the *right
answer is known*, and read the artifact as a biologist would.

**Dataset.** MetaboLights **MTBLS136** — the Thévenot 2015 human **urine LC-MS**
study (age × gender × BMI design). The ground truth is the set of
**gender-discriminating metabolites** the authors reported (steroid metabolites
including testosterone glucuronide, androsterone sulfate, etc.): we know which
features *should* separate the sexes, so we can score recall of a published
signature, not just eyeball it.
(`evaluation/tutorial_demos/gold_standards.yaml:74-83`;
`Tutorial Demo Scenarios 7-domain.md:390-444`.)

**Prompt** (the recorded tutorial T7), phenotype column = `gender`:

> "Untargeted metabolomics multi-method analysis."

**What comes back and how to read it (from the demo spec):**

- **≈ 5,400 features after CAMERA grouping; median QC-CV ≈ 14%.** Interpretation:
  the feature count is in the expected urine band and the platform was stable
  (well under 30% CV) — the differences that follow are analytical signal, not
  drift.
- **biosigner consensus selected ≈ 23 features across the three classifiers.**
  Interpretation: a compact, robust signature — features that hold up under
  PLS-DA *and* Random Forest *and* SVM, not one method's quirk.
- **The ground-truth check.** **9 of 12 published gender-discriminating features
  recovered (75%)**, above the 70% target. Interpretation: the pipeline recovers
  the known Thévenot 2015 signature, so you can trust its selections on features
  the paper didn't report.
- **Annotation.** The recovered features map to steroid metabolites consistent
  with the reported sex differences — the biologically expected story.

**The artifact.** A differential-features TSV + a consensus-selection object + an
annotation HTML report. You end on a decision — *these features discriminate the
groups, they reproduce a published signature, here's what they likely are* —
which is exactly the "gold-standard-comparable artifact" the tutorial-demo plan
mandates.

> **Note (verification tier).** The chain wiring (xcms → CAMERA → biosigner),
> workflow IDs (12631 / 11032 / 10990; annotation 10977 / 11773; NMR 10905),
> default params, and routing are **code-verified (C)** by reading source
> (citations above). The QC checks are **spec / advisory (no code gate exists)**.
> The numeric outputs (~5,400 features, 14% CV, 9/12 recall) come from the
> gold-standard demo spec; a **fresh live AWS Batch re-run** to reproduce them is
> **pending (L / ⏳)** and was not fired — Batch runs cost real money and the plan
> forbids speculative execution. The biomarker-recall scoring is a **validator
> metric**, and the validator file (`evaluation/tutorial_demos/metabolomics.py`)
> referenced by the demo doc is **not yet present in the repo** (only
> `transcriptomics.py` exists) — see What's not covered.

## Outputs & visualization

Every output renders in the after-run panel's Outputs section via the in-app viewer
taxonomy (`frontend/client/src/components/step-output-preview.tsx:66-105`); the
mapping below is by file extension.

| Output | File | In-app viewer | When to go interactive |
|---|---|---|---|
| Annotation / biomarker report | `annotation_report.html` | **HTML iframe** viewer (sandboxed) | Read the consensus signature + annotations inline |
| Differential-features table | `differential_features.tsv` | **Table** viewer (sortable, 200-row preview + full download) | Download to filter by m/z / RT / selection score |
| Feature table (post-CAMERA) | `*.csv` / `*.tsv` | **Table** viewer | Download for your own re-analysis |
| Consensus-selection R object | `*.rds` | **R-object** viewer (binary → open in RStudio) | Re-analyse in R only if you need more than the table |
| QC / PCA plots | `*.pdf` / `*.png` | **PDF / Image** viewer | Read the QC-sample clustering; export for figures |

> **Tip — read the QC plot before the biomarker list.** The QC-sample PCA/CV plot
> tells you whether the run was analytically stable. If pooled QC samples don't
> cluster tightly, the "differences" downstream may be drift — read this first,
> then the differential-features table.

## Pitfalls & tips

> **Pitfall — no code gate protects you.** Metabolomics has no enforced QC gate;
> a drifting instrument produces a full result with no flag. Read QC-sample CV and
> biosigner accuracy yourself.

> **Pitfall — features are not molecules.** The consensus chain gives you
> discriminating m/z×RT features, not identities. Annotate the shortlist against
> HMDB (`biodbHmdb`) / metaboannotation as a separate step before naming
> metabolites.

> **Pitfall — LC-MS ≠ NMR.** For NMR data use ASICS, not xcms. The consensus
> chain is LC-MS only.

> **Tip — name the phenotype column.** biosigner trains on the metadata column you
> specify; state it so the classifiers learn the right contrast.

## What's not covered

Honest scope — these are **not** claimed as present; they live in **Appendix E
(Coverage & roadmap)**:

- **Any code-enforced metabolomics QC gate.** There is no
  `_parse_metabolomics_metrics` and no metabolomics branch in the QC verdict logic
  (`qc_trace_monitor.py`) and no metabolomics section in `qc_evidence.yaml`. All
  QC numbers are spec/advisory — the manual says so.
- **HMDB annotation inside the consensus chain.** The chain selects features;
  annotation (`biodbHmdb` 10977 / `metaboannotation` 11773) is a separate step.
- **A biomarker-recall gate on your data.** Published-biomarker recall is a
  **validator** metric for the demo, not a runtime gate. The validator file
  `evaluation/tutorial_demos/metabolomics.py` is **not yet present in the repo**.
- **A metabolomics auto-loop.** No automatic parameter-tuning; peak-detection
  fixes are manual (adjust centWave params, re-run).
- **Deep coverage of NMR (ASICS), metaboigniter, and pathway-level analysis.**
  These workflows **exist and route**, but end-to-end worked examples and
  gold-standard validation for them are roadmap.
- **Interactive tools (RStudio / Jupyter) launch.** On dev these are **not
  provisioned** (`/api/interactive/available` → `available:false`); the launch
  buttons are correctly hidden. In-app table/plot/HTML viewers cover reading
  outputs; interactive re-analysis is environment-dependent.

---
_Verification: this page depends on the coverage-ledger rows under
**"## Metabolomics (untargeted LC-MS)"** — chain `lcms_metabolomics_consensus`
(xcms→CAMERA→biosigner) + step IDs 12631/11032/10990 + annotation 10977/11773 +
NMR 10905 (C), routing + untargeted-vs-targeted + LC-MS-vs-NMR + selection-vs-
annotation disambiguation (C), NO code-enforced QC gate (C ✅ absence confirmed;
all spec-only), HMDB-not-in-chain mismatch vs "→ HMDB" prompt (C 🔧), viewer
taxonomy (C), MTBLS136 gold artifact + 9/12 recall (C from demo spec; live-Batch
re-run L / ⏳; validator file absent 🗺️), and the roadmap/gap rows (🗺️)._
