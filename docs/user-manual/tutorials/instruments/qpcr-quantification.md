# Instrument tutorial — qPCR → relative gene-expression (ΔΔCt)

> **Who this is for:** anyone who runs a qPCR machine (Bio-Rad CFX, Applied Biosystems QuantStudio/StepOnePlus,
> Roche LightCycler, QIAGEN Rotor-Gene, BMS MIC) and wants the numbers it produces turned into a
> **"which genes went up or down, and by how much"** answer — no coding needed.
> **Time:** ~10 minutes to read; a run itself takes a minute or two (this is a small-table calculation, not a
> heavy pipeline).
> **Where it fits:** Tutorial 6 (T6) explains how to *connect* a qPCR machine so its files reach BioMate. This
> tutorial picks up from there and explains **the analysis that data drives, how to run it, and how to read it.**

---

## 1. What this instrument produces

A real-time qPCR (quantitative PCR) run measures how much of a specific DNA or RNA target is in each well of a
plate. The core number it reports per well is the **Cq** (quantification cycle, also written **Ct** —
threshold cycle): the PCR cycle number at which that well's fluorescence crosses a set line. **A lower Cq means
more starting material** (it crossed earlier); a higher Cq means less.

Depending on the vendor, the machine saves this as:

- Bio-Rad CFX Manager → `.pcrd` (a small database file) or a `.csv` export
- Applied Biosystems QuantStudio / StepOnePlus → `.eds` or a `.txt` export
- Roche LightCycler → `.ixo` or `.xls`
- QIAGEN Rotor-Gene → `.rex`; BioMolecular Systems MIC → `.micpcr`
- Any machine → a generic `.csv`/`.txt` table of wells, targets, samples, and Cq values

**The raw Cq table is not the answer you want.** A Cq of 24 for your gene means nothing on its own — it depends
on how much sample you loaded, pipetting, and reaction efficiency. To get a biological answer you have to
**normalise** it. That normalisation is the analysis BioMate runs.

---

## 2. The BioMate analysis it drives (and why)

The most common question from an RT-qPCR experiment is: **"Did my gene of interest change between two groups
(e.g. treated vs. control), after correcting for how much sample was in each well?"** The standard method for
answering this is the **ΔΔCt method** (delta-delta-Ct, reported as **2^−ΔΔCt** = fold change).

Plain-language version of what ΔΔCt does, in three steps:

1. **ΔCt (first delta) — correct for loading.** For each sample, subtract the Cq of a **housekeeping gene** (a
   gene that *shouldn't* change between your conditions, e.g. GAPDH or ACTB) from the Cq of your gene of
   interest. This cancels out "how much total sample was in this well". *(Why: without this, a well with twice
   as much cDNA would look like twice the expression even if nothing biological changed.)*
2. **ΔΔCt (second delta) — compare to the control group.** Subtract the average ΔCt of your **control group**
   from each sample's ΔCt. Now zero means "same as control".
3. **2^−ΔΔCt — turn it into fold change.** Because each PCR cycle roughly doubles the product, raising 2 to the
   power of −ΔΔCt converts cycles into a **fold change** you can read directly: 2.0 = "twice as much as
   control", 0.5 = "half as much".

**The workflow BioMate routes this to:** `normqpcr_delta_delta_cq_normalization` — a Bioconductor **NormqPCR**
pipeline that "normalises qPCR data and calculates relative gene expression between two groups using the
2^−ΔΔCq method with single or multiple housekeeping genes." It is a short (3-step) workflow in BioMate's
**transcriptomics** domain. Related NormqPCR workflows also exist if your experiment is different:

| Your situation | Workflow BioMate offers |
|---|---|
| Treated vs. control, you have good housekeeping genes | **`normqpcr_delta_delta_cq_normalization`** (the main one) |
| You're *not sure* your housekeeping genes are stable | `normqpcr_normalized_relative_quantities` / `normqpcr_compute_nrqs` (account for amplification efficiency) |
| You want to formally pick the most stable reference genes first | `nf-core/stableexpression` (identifies the best RT-qPCR reference genes) |
| No stable housekeeping genes available at all | `unifiedwmwqpcr` (normalises to overall expression instead) |

> **Honest note up front (read this):** the qPCR *connector* (the watcher on your lab network) tags each new
> file with an internal routing label such as `rt_qpcr_expression`. That label is a **hint**, not a literal
> workflow name — when you Launch the event, BioMate's chat routes your request to the real catalogue workflow
> above (`normqpcr_delta_delta_cq_normalization`). If you ever see the analysis resolve to something unrelated
> (for example a reference-gene-*stability* pipeline instead of ΔΔCt), just say "run delta-delta-Ct relative
> quantification" in the chat to steer it. See §6 for what is and isn't validated.

---

## 3. Before you start — get the data in (see T6)

This tutorial assumes your Cq data is already reaching BioMate. If it isn't yet, do one of:

- **Connect the instrument (best for a lab that runs qPCR regularly).** Register a **qPCR** instrument in
  **Connectors → Instruments** and have your admin point its file-watcher at the folder your CFX/QuantStudio
  software exports to. New runs then appear automatically as **New data events**. Full steps: **Tutorial 6**.
- **Upload one file by hand (fine for a one-off).** Export a `.csv` of your Cq values and bring it in from the
  Data area. Full steps: **Tutorial 4**.

**What your file should contain**, at minimum, for ΔΔCt: a column identifying each **sample**, each **target
gene**, the **Cq value**, and a way to tell **control** samples from treated ones (e.g. a condition column, or
"control" in the sample name). You will also need to know **which gene(s) are your housekeeping genes** — the
workflow asks for this by name.

---

## 4. Step by step — run it

<!-- CAPTURE route=/ ; state=New data events list showing a qPCR event (experiment type "rt qpcr expression", source qPCR watcher) with Launch + Dismiss ; focus=instrument-event ; note=show a qPCR New-data event card: file name, source=qPCR, experiment type badge, Launch button -->
*(Figure to add: a qPCR New-data event — the exported file, the "RT-qPCR expression" experiment-type badge, and the Launch button.)*

1. **Start from the data event (or just ask).** If the instrument is connected, find your run under **New data
   events** and click **Launch** — BioMate opens a chat with a **pre-filled draft** (nothing runs yet). If you
   uploaded by hand, just type your goal, e.g. *"Run delta-delta-Ct relative expression on this qPCR Cq table,
   treated vs. control, housekeeping genes GAPDH and ACTB."*
2. **Check BioMate picked the right workflow.** The right-hand panel should open **normqpcr_delta_delta_cq_
   normalization** (title not "undefined"). If it opened a different qPCR workflow, see the table in §2 and
   rephrase, or name the workflow directly.
3. **Fill the two key settings** (the workflow asks for these by name):
   - **Housekeeping gene(s)** (`qpcr_hkg`) — e.g. `GAPDH,ACTB`. *Where to get it:* it's whatever reference
     gene(s) you designed primers for; list all of them, comma-separated.
   - **Control label** (`qpcr_control_label`) — the text that marks your control samples in the table (default
     `control`). *Where to get it:* look at your own sample names / condition column.
4. **Attach your Cq table** to the file input if it isn't already linked from the event.
5. **Confirm and run.** Click **Confirm & Run**. Because this is a small-table calculation, it finishes quickly.

<!-- CAPTURE route=/ ; state=Workflow panel pre-run for normqpcr_delta_delta_cq_normalization, param strip showing qpcr_hkg + qpcr_control_label filled, Confirm & Run footer ; focus=workflow-panel ; note=show pre-run panel: workflow name, the two required params filled, Confirm & Run button -->
*(Figure to add: the pre-run workflow panel — workflow name, the `qpcr_hkg` and `qpcr_control_label` fields filled in, and the Confirm & Run button.)*

---

## 5. Reading the result / report

When the run finishes, open the **After run** section (the same three-tab report explained in **Tutorial 3**):

- **Summary** — the plain-language finding: which genes went up or down and by how much, as **fold change
  (2^−ΔΔCt)**. Read it like this:
  - **Fold change > 1** → the gene is **higher** in treated vs. control (e.g. 3.0 = three-fold up).
  - **Fold change < 1** → the gene is **lower** (e.g. 0.25 = four-fold down).
  - **≈ 1** → essentially unchanged.
  - A ΔΔCt difference of about **1 cycle ≈ a two-fold change**; this is why single-cycle Cq differences matter.
- **Outputs** — the normalised table(s): per-sample ΔCt, ΔΔCt, and 2^−ΔΔCt values, filed under the step that
  produced them, downloadable as files for your figures or supplement.
- **Reproducibility record** — the audit trail: the exact housekeeping genes and control label you used, the
  software version, and the outputs with checksums (generated on demand). This is what makes the result
  defensible in a paper.

> **What a good result looks like, and what should make you cautious.** A believable RT-qPCR result has your
> *housekeeping* gene looking flat across conditions (if GAPDH itself swings wildly, your normalisation is
> shaky — switch to the efficiency-aware or `stableexpression` workflow in §2). Fold changes are most
> trustworthy with **biological replicates** (ideally ≥3 per group); a "5-fold change" from a single well is a
> hint, not a result.

---

## 6. Honest limits — what to expect

- **Status: available, not yet validated on real data end-to-end.** `normqpcr_delta_delta_cq_normalization` is
  a real, indexed BioMate workflow (confirmed in the catalogue) built on the published Bioconductor **NormqPCR**
  package. BioMate does **not** yet have a recorded real qPCR run proving it end-to-end on the development site.
  Treat it as *available-but-untested*: the method is standard and the workflow exists, but expect to sanity-check
  the first run against a value you compute by hand.
- **The connector label is a routing hint, not a literal workflow.** The qPCR watcher's internal tag
  (`rt_qpcr_expression` → an internal `qpcr_differential_expression` label) does **not** resolve verbatim to a
  catalogue workflow. BioMate routes your Launch to the real NormqPCR workflow by matching your request. If the
  routing lands somewhere wrong, name the analysis explicitly (§2).
- **Absolute / standard-curve quantification is a gap.** If your goal is **absolute** copy number from a
  standard curve (not relative fold change), there is **no dedicated, confirmed standard-curve qPCR workflow**
  in the catalogue today. The connector has an internal `absolute_quantification` tag, but it does not resolve
  to a verified workflow. Do standard-curve fitting in your instrument software for now, or ask BioMate to fit a
  curve ad-hoc — and treat that as experimental. **This is a real coverage gap, stated plainly rather than
  faked.**
- **Melt-curve / primer-specificity QC is not part of this workflow.** Check your melt curves in the instrument
  software; the ΔΔCt workflow assumes your Cq values are already from specific, single-product reactions.
- **Other qPCR experiment types route elsewhere.** CRISPR-screen qPCR and ChIP-qPCR are handled by different
  pipelines (a MAGeCK-style screen workflow and a ChIP-seq analysis, respectively); this tutorial covers only
  relative expression.

---

## 7. Where to go next

| You want to… | Where |
|---|---|
| Connect the qPCR machine so runs arrive automatically | **Tutorial 6** |
| Bring a single Cq file in by hand | **Tutorial 4** |
| Understand the three-tab report in depth | **Tutorial 3** |
| Measure expression genome-wide instead of a few genes | **BaseSpace → RNA-seq tutorial** (`basespace-sequencing.md`) |
| Pick the most stable reference genes first | ask for `nf-core/stableexpression` |

The habit: **Launch the qPCR event → confirm it opened the ΔΔCt workflow → set housekeeping genes + control
label → run → read fold changes.**

---

## 8. Key terms

| Term | What it means — and why you care |
|---|---|
| **Cq / Ct** | The PCR cycle where a well's signal crosses the threshold. **Lower = more starting material.** The raw number per well. |
| **Housekeeping / reference gene** | A gene assumed not to change between your conditions (e.g. GAPDH, ACTB); used to cancel out loading differences. If it isn't actually stable, your result is unreliable. |
| **ΔCt (delta-Ct)** | Gene-of-interest Cq minus housekeeping Cq, per sample — corrects for how much sample was loaded. |
| **ΔΔCt (delta-delta-Ct)** | Your sample's ΔCt minus the control group's average ΔCt — compares to control. |
| **2^−ΔΔCt / fold change** | ΔΔCt turned into a readable multiple: 2 = twice control, 0.5 = half. ~1 cycle ≈ 2-fold. |
| **NormqPCR** | The published Bioconductor package behind the BioMate ΔΔCt workflow. |
| **Absolute quantification** | Copy number from a standard curve (not relative). **No dedicated validated workflow yet — a known gap.** |

---

_Grounded in: `biomate-connector/lab_instruments/qpcr_connector.py` (experiment-type → workflow routing) and the
BioMate workflow catalogue entry `normqpcr_delta_delta_cq_normalization` (Bioconductor NormqPCR, confirmed via
workflow search). Companion: Tutorials 3, 4, 6._
