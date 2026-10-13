# Proteomics (DIA / label-free quant & differential expression)

> One-line promise: go from mass-spec runs (mzML) to a **protein quantification
> table** and a ranked list of **differentially abundant proteins** — with a
> volcano plot you can read at a glance and the identification / reproducibility
> gates that tell you whether the quant is trustworthy before you interpret it.
> For: **wet-lab proteomics researchers / PIs** comparing conditions (treated vs
> control, disease vs healthy) and **bioinformaticians** who want the
> Bioconductor label-free DE path run and reported for them. No coding required.

<!--
P2 chapter. Every "supported" claim below is green in coverage-ledger.md § "Proteomics (DIA / label-free DE)".
Honesty rule: QC gates are documented as "code-enforced" ONLY where they live in qc_trace_monitor.py (MaxQuant /
DIA-NN FDR/CV/missing-value gates). The tutorial's UPS1-recall metric is a VALIDATOR metric, not a runtime gate,
and is labelled as such. The gold-standard chain in the DB is MSnbase → limma; "DIA-NN → MaxLFQ" is the front-end
search+quant that produces the table the chain consumes — documented honestly (DIA-NN/MaxLFQ are not standalone
catalog workflows; they surface via nf-core/diaproteomics + the msqrob2 DIA subworkflow). Anything not built is in
"What's not covered".
-->

## What this is for

This is the **"which proteins changed, and by how much"** path for
mass-spectrometry proteomics. You ran samples on an MS instrument, you have two
or more groups (treated vs control, disease vs healthy, high vs low dose), and
you want a table of proteins that go up or down with statistical confidence.

BioMate covers the **label-free quantification (LFQ)** workflow, including
**data-independent acquisition (DIA)**:

1. **Identification + quantification** — turn spectra into a protein × sample
   intensity table (via a DIA/LFQ search engine such as DIA-NN or a MaxQuant/
   MaxLFQ export, or MSnbase for a Bioconductor-native load).
2. **Differential expression** — model the intensity table with limma (empirical-
   Bayes moderated t-test) to get log2 fold-changes and adjusted p-values.

The through-line is interpretation: every QC number below is explained as "what
it means and what to do next," and the worked example ends on a *decision* (these
proteins, this confidence), not a process tree.

> **Tip** — If you already have a quantification table (a MaxQuant `proteinGroups.txt`,
> a DIA-NN `report.tsv`, or any protein × sample matrix), you do not need to
> re-search the raw files. The DE step (limma) takes the table directly — the
> cheap, fast lane. The MS search + quant is the expensive step; run it only when
> you have raw/mzML to process.

## Use cases

| Goal (researcher's words) | Workflow(s) / chain | Inputs | Outputs (artifact) | Lane |
|---|---|---|---|---|
| "Label-free proteomics: which proteins differ, treated vs control" | chain **`bioc_proteomics_de_v2`**: MSnbase load/quant → limma DE (`adj_method=BH`, `lfc_threshold=1.0`) | mzML files + sample sheet | DE-proteins CSV (log2FC, adj.P) + volcano plot + QC report | Cloud (AWS Batch) |
| "Run a DIA search + quant from my raw/mzML, then DE" | `nf-core/diaproteomics` (id **1495**) or `nf-core/proteomicslfq` (id **1496**) → limma DE | Raw/mzML + spectral library / FASTA | Protein-quant table → DE table | Cloud |
| "I have a DIA-NN / Spectronaut precursor report — get differentially abundant proteins" | msqrob2 DIA precursor subworkflow (maxLFQ summarisation → robust DE) | DIA-NN `report.tsv` / Spectronaut export | Protein-level DE table | Cloud |
| "I have a MaxQuant proteinGroups table — run DE" | `deqms` (id **11248**) or limma | `proteinGroups.txt` + design | DE table with variance-corrected statistics | Cloud |

> **Pitfall — the gold chain is MSnbase → limma, not "DIA-NN → MaxLFQ → DEqMS".**
> The peer-reviewed gold-standard chain wired in the catalog
> (`bioc_proteomics_de_v2`) is **two Bioconductor steps: MSnbase load/quant →
> limma DE**. DIA-NN and MaxLFQ are **search/quant front-ends** that produce the
> intensity table — they are not standalone catalog workflows (DIA-NN surfaces via
> `nf-core/diaproteomics` and the msqrob2 DIA subworkflow; maxLFQ is the
> `iq::maxLFQ` summarisation inside msqrob2/QFeatures). DEqMS (id 11248) exists as
> an alternative DE method but is not the gold chain's DE step. Document what you
> actually run: quantify (DIA-NN/MaxLFQ/MSnbase) → DE (limma), with DEqMS as a
> variance-aware swap.

## How to ask

BioMate routes on intent. The disambiguation that matters here is **what you
already have** (raw/mzML vs a quant table) and **which DE method**.

Bioconductor label-free DE (the gold chain):

> "Bioconductor proteomics pipeline — label-free protein DE analysis."

DIA search from raw, then DE:

> "Run a DIA proteomics search and quantification on my mzML with this spectral
> library, then run differential expression, disease vs healthy."

The proteomics chain triggers on proteomics context — its example queries include
*"proteomics differential expression"*, *"mzml limma analysis"*, *"label free
protein de analysis"*, and it triggers on upstream workflows
`diaproteomics` / `maxquant` / `openms` and output extensions `mzml` / `txt`
(`backend/lib/galaxy/ai/bioc_chain_templates.py:350-358`).

**Disambiguation to avoid:**

- **DIA vs DDA.** DIA (data-independent acquisition) and DDA (data-dependent)
  need different search settings; DIA-NN/Spectronaut are DIA-native. Say "DIA" so
  the right search front-end is chosen; the downstream limma DE is the same.
- **Label-free vs labelled (TMT / iTRAQ).** This chapter is **label-free**.
  Isobaric-labelled quant (TMT/iTRAQ) is a different quant mode with its own
  normalisation — the gold chain drops the labelled MSstats variant on purpose
  (`bioc_chain_templates.py:328-330`). Name your labelling if it isn't label-free.
- **limma vs DEqMS.** Both fit moderated statistics; **DEqMS** additionally
  corrects the variance estimate by the number of peptides/PSMs per protein
  (proteins quantified from one peptide are noisier). For a rigorous
  spectral-count-aware analysis, ask for DEqMS; the default gold chain uses limma.

> **Tip — start from the table if you have it.** The MS search is the expensive
> step. If you already have a protein-quant table (MaxQuant/DIA-NN/mzTab), ask for
> "differential expression on my protein table" and skip straight to the fast lane.

## Tools & workflows behind this

| Tool / workflow | Role | Where (verified) |
|---|---|---|
| Chain `bioc_proteomics_de_v2` | 2-step gold path: MSnbase load/quant → limma DE | `backend/lib/galaxy/ai/bioc_chain_templates.py:318-358`; DB `workflow_chains` |
| `BIOC_MSNBASE` (step 1) | Load mzML, label-free quant; `method=label_free` | chain step 1 `bioc_chain_templates.py:331-337`; `msnbase` id **11894** in DB |
| `BIOC_LIMMA` (step 2) | Moderated-t DE; `adj_method=BH`, `lfc_threshold=1.0` | chain step 2 `bioc_chain_templates.py:338-343`; `limma` id **11697** in DB |
| `nf-core/diaproteomics` (id **1495**) | DIA search + quant front-end | DB id 1495 |
| `nf-core/proteomicslfq` (id **1496**) | Label-free LFQ search + quant front-end | DB id 1496 |
| msqrob2 DIA precursor subworkflow | DIA-NN/Spectronaut precursor → maxLFQ summarisation → robust DE | `backend/biomni_workflows/nextflow_nfcore/subworkflows/bioconductor/msqrob2/dia_precursor_workflow.nf:4,24` |
| `deqms` (id **11248**) | Variance-corrected (spectral-count-aware) DE | DB id 11248 |

The chain's hand-off is real: MSnbase's `rds` output (an MSnSet) feeds limma's
`msnset_rds` input (`bioc_chain_templates.py:345-347`). That is why a quant table
can enter at the DE step — the contract is the quant object, not a fixed position.

> **License** — nf-core pipelines and Bioconductor packages (MSnbase, limma,
> DEqMS, msqrob2, QFeatures) are open-source academic tools; results are yours.
> DIA-NN is free for academic use under its own licence.

## QC gates & how to read them

A QC gate answers one question: **"can I trust this quant before I call proteins
up or down?"** The proteomics gates are **profile-driven** and largely
**code-enforced** — a real strength of this domain relative to some others.

| Gate | Threshold | What a fail means | Enforced where |
|---|---|---|---|
| **PSM FDR** | **< 1%** (HALT) | Identifications aren't controlled — you can't trust which proteins are which. | **Code-enforced (GOLD).** `qc_trace_monitor.py:4915-4928`; Elias & Gygi 2007 |
| **Protein FDR** | **< 1%** (HALT) | Same, at the protein-inference level. | **Code-enforced (GOLD).** `:4931-4943` (MaxQuant) · `:5017-5029` (DIA-NN); Elias & Gygi 2007 |
| **Median CV across replicates** | **≤ 20%** DDA · **≤ 15%** DIA (HALT) | Poor reproducibility — replicates disagree, so fold-changes are noisy. | **Code-enforced (SILVER).** `:4963-4976` (MaxQuant) · `:5032-5045` (DIA-NN); EuBIC 2018 / DIA community |
| **Missed cleavage %** | **≤ 20%** (HALT) | Incomplete digestion — biased peptide detection. | **Code-enforced (SILVER).** `:4946-4960`; EuBIC 2018 |
| **Missing values per protein** | **≤ 30%** (profile-gated) | Too many gaps to quantify a protein reliably. | **Code-enforced when the profile sets it** (e.g. plasma-biomarker). `:5048-5061`; Geyer et al. 2017 |
| **PSM count** | **≥ 1,000** (advisory) | Too few IDs for a meaningful proteome. | **Code-enforced (advisory, BRONZE).** `:4997-5011` |
| **UPS1 recall at FDR 5%** | tutorial target **≥ 80%** | Spike-in ground-truth recovery — the pipeline's benchmark score. | **Validator metric, not a runtime gate** — computed by the gold-standard validator |

**Profiles change the numbers** (`qc_trace_monitor.py` proteomics profiles): the
default `proteomics_standard` applies the GOLD FDR gates and 20% CV;
`proteomics_phospho` relaxes PSM count to 500 and CV to 25% (enrichment adds
variance); `proteomics_plasma_biomarker` tightens CV to 15% and adds the ≤ 30%
missing-value gate; `proteomics_chemoproteomics` relaxes PSM count to 200.

**How to read each:**

- **FDR (< 1%)** — the non-negotiable gate. If PSM or protein FDR exceeds 1%, the
  run halts: you don't have controlled identifications, so nothing downstream is
  trustworthy.
- **Median CV** — your reproducibility thermometer. DIA is held to a tighter 15%
  because DIA quant is more reproducible by design; DDA to 20%. Above the
  threshold, tighten sample handling / normalisation before believing
  fold-changes.
- **Missing values** — proteins with too many blanks can't be quantified
  reliably. In plasma-biomarker work this is a hard gate (≤ 30%); elsewhere it's
  informative context.
- **UPS1 recall** — this is the *benchmark* number (how many known-spiked
  proteins the pipeline recovers), computed by the validator against a known-truth
  dataset. It tells you the pipeline is calibrated; it is not a gate that halts
  your own run.

> **Pitfall — UPS1 recall is a validator score, not a gate on your data.** The
> tutorial's "UPS1 recall ≥ 80% at FDR 5%" is how the gold-standard *demo* is
> scored against a spike-in truth set; it is **not** a live QC gate that runs on
> your experiment. Your runtime gates are FDR, CV, missed cleavage, and
> missing-value — those are the ones that halt.

> **QC gate — FDR first, always.** Read PSM/protein FDR before anything else. A
> run with uncontrolled FDR can produce a beautiful volcano plot of proteins that
> aren't reliably identified. FDR < 1% is the entry ticket to interpretation.

### What "fixing" a QC fail looks like here

There is **no proteomics auto-loop**. QC fails are surfaced for you to correct
and re-run:

- FDR fail → check the search settings (database, decoy strategy, mass
  tolerances) and re-search.
- High CV / missing values → a sample-handling or normalisation issue; check for
  a batch effect or a bad replicate, correct the design, and re-run the DE step
  on the existing quant table (no re-search needed).
- Too few PSMs → more injection / longer gradient, or check the sample amount.

## Worked example (gold standard)

**Goal.** Run label-free DE on a benchmark where the *right answer is known*, and
read the artifact as a biologist would.

**Dataset.** ProteomeXchange **PXD002952** — the **UPS1** universal protein
standard (48 human proteins) spiked into a **yeast** lysate background at known
ratios. The spike-ins are the ground truth: the 48 UPS1 proteins are the true
positives (they change between concentrations), and the yeast background proteins
are true negatives (they don't). So we can score recall and false-positive rate,
not just eyeball the volcano.
(`evaluation/tutorial_demos/gold_standards.yaml:51-61`;
`Tutorial Demo Scenarios 7-domain.md:277-329`.)

**Prompt** (the recorded tutorial T5):

> "Bioconductor proteomics pipeline — label-free protein DE analysis."

**What comes back and how to read it (from the demo spec):**

- **ID rate ≈ 71%, median CV ≈ 11%** — comfortably inside the identification and
  reproducibility gates. Interpretation: the quant is clean; fold-changes are
  trustworthy.
- **DE table** — each protein with a log2 fold-change and an adjusted p-value for
  the `concentration_high_vs_low` contrast (limma eBayes). This is the artifact
  you carry forward.
- **The ground-truth check.** **42 of 48 UPS1 proteins recovered at FDR ≤ 5%
  (87.5% recall)**, above the 80% target, with a **yeast-background false-positive
  rate ≈ 3.1%** (below the 5% ceiling). Interpretation: the pipeline recovers the
  known spike-ins at the published MaxLFQ standard while keeping false positives
  low — so you can trust it on your unknown proteins too.
- **Volcano plot** — the UPS1 proteins land in the significant, high-fold-change
  corner; the yeast cloud sits at the centre. This is what a well-calibrated
  proteomics DE looks like.

**The artifact.** A DE-proteins CSV + a volcano plot + a QC report. You end on a
decision — *these proteins moved, at benchmark-grade recall and controlled false
positives* — which is exactly the "gold-standard-comparable artifact" the
tutorial-demo plan mandates.

> **Note (verification tier).** The chain wiring (MSnbase → limma), workflow IDs
> (11894 / 11697; front-ends 1495 / 1496; DEqMS 11248), default params, routing,
> and the **code-enforced** QC gates (FDR/CV/missed-cleavage/missing-value/
> PSM-count, profile-driven) are **code-verified (C)** by reading source
> (citations above). The numeric outputs (42/48 UPS1, 3.1% FPR, 71% ID rate) come
> from the gold-standard demo spec; a **fresh live AWS Batch re-run** to reproduce
> them is **pending (L / ⏳)** and was not fired — Batch runs cost real money and
> the plan forbids speculative execution. The UPS1-recall / yeast-FPR scoring is a
> **validator metric**, and the validator file
> (`evaluation/tutorial_demos/proteomics.py`) referenced by the demo doc is **not
> yet present in the repo** (only `transcriptomics.py` exists) — see What's not
> covered.

## Outputs & visualization

Every output renders in the after-run panel's Outputs section via the in-app viewer
taxonomy (`frontend/client/src/components/step-output-preview.tsx:66-105`); the
mapping below is by file extension.

| Output | File | In-app viewer | When to go interactive |
|---|---|---|---|
| QC report | `qc_report.html` | **HTML iframe** viewer (sandboxed) | Read per-sample ID rate / CV / missing-value inline |
| DE-proteins table | `de_proteins.csv` | **Table** viewer (sortable, 200-row preview + full download) | Download to filter by adj.P / log2FC for target triage |
| Volcano plot | `*.pdf` / `*.png` | **PDF / Image** viewer | Export for the figure panel |
| Protein-quant matrix | `*.csv` / `*.tsv` | **Table** viewer | Download for your own re-analysis |
| MSnSet / limma R object | `*.rds` | **R-object** viewer (binary → open in RStudio) | Re-analyse in R only if you need more than the table |

> **Tip — read the table in-app, don't re-plot.** The DE table renders sortable
> with a 200-row preview and full download. Sort by `adj.P.Val` for your top hits
> or by `logFC` for effect size — you rarely need RStudio just to look. Go
> interactive only to re-analyse, and only where those tools are provisioned (see
> What's not covered).

## Pitfalls & tips

> **Pitfall — label-free only in this chapter.** TMT/iTRAQ isobaric quant is a
> different mode with its own normalisation. The gold chain is label-free; name
> your labelling if it isn't.

> **Pitfall — one-peptide proteins are noisy.** A protein quantified from a
> single peptide has a shakier estimate than one from ten. If that matters for
> your conclusions, use **DEqMS** (variance corrected by peptide/PSM count)
> rather than plain limma.

> **Tip — start from the quant table.** The MS search is the expensive Batch
> step. If you already have a MaxQuant/DIA-NN/mzTab table, ask for DE on it
> directly.

> **QC gate — FDR < 1% is the entry ticket.** Read PSM/protein FDR before the
> volcano. Uncontrolled FDR makes every downstream number suspect.

## What's not covered

Honest scope — these are **not** claimed as present; they live in **Appendix E
(Coverage & roadmap)**:

- **DIA-NN / MaxLFQ as standalone catalog workflows.** They are search/quant
  front-ends that surface via `nf-core/diaproteomics` (1495) and the msqrob2 DIA
  subworkflow, not one-click indexed workflows of their own. The gold chain's DE
  is MSnbase → limma.
- **A hard UPS1-recall gate on your data.** UPS1 recall is a **validator** metric
  for the demo, not a runtime gate. The validator file
  `evaluation/tutorial_demos/proteomics.py` is **not yet present in the repo**.
- **TMT / iTRAQ labelled quant.** Only the label-free MSstats-adjacent path is
  wired; the labelled MSstats variant is dropped from the gold chain on purpose.
- **A proteomics auto-loop.** Unlike ADMET, there is no automatic
  parameter-tuning loop; QC fails are surfaced for manual correction and re-run.
- **Deep coverage of chemoproteomics / phospho / PTM chains.** Profiles exist
  (`proteomics_phospho`, `proteomics_chemoproteomics`) and their QC gates are
  code-enforced, but end-to-end worked examples and gold-standard validation for
  them are roadmap.
- **Interactive tools (RStudio / Jupyter) launch.** On dev these are **not
  provisioned** (`/api/interactive/available` → `available:false`); the launch
  buttons are correctly hidden. In-app table/plot/HTML viewers cover reading
  outputs; interactive re-analysis is environment-dependent.

---
_Verification: this page depends on the coverage-ledger rows under
**"## Proteomics (DIA / label-free DE)"** — chain `bioc_proteomics_de_v2`
(MSnbase→limma) + step IDs 11894/11697 + front-ends 1495/1496 + DEqMS 11248 +
default params (C), routing + DIA-vs-DDA + label-free-vs-TMT + limma-vs-DEqMS
disambiguation (C), code-enforced FDR/CV/missed-cleavage/missing-value/PSM-count
gates + 4 proteomics profiles (C), UPS1-recall as validator-not-gate (C), the
"DIA-NN→MaxLFQ→DEqMS/limma" prompt vs real MSnbase→limma gold chain mismatch
(C 🔧), viewer taxonomy (C), PXD002952 UPS1 gold artifact + 42/48 recall / 3.1%
FPR (C from demo spec; live-Batch re-run L / ⏳; validator file absent 🗺️), and the
roadmap/gap rows (🗺️)._
