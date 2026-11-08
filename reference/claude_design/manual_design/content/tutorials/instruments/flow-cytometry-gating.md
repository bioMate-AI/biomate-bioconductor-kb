# Instrument tutorial — flow cytometer → gating & immunophenotyping (FCS)

> **Who this is for:** anyone who runs a flow cytometer (BD FACSAria/Canto/Celesta, Beckman CytoFLEX, Miltenyi
> MACSQuant, Sony SH800, or any FCS-compliant instrument) and wants its `.fcs` files turned into
> **"which cell populations are present, and what fraction of cells each one is"** — no coding needed.
> **Time:** ~10 minutes to read; a run is typically a couple of minutes per sample.
> **Where it fits:** Tutorial 6 (T6) explains how to *connect* a cytometer so its files reach BioMate. This
> tutorial explains **the analysis that data drives, how to run it, and how to read it.**

---

## 1. What this instrument produces

A flow cytometer pushes cells one at a time past lasers and records, for every cell (an "event"), how much it
scatters light and how brightly it glows in each fluorescence channel. One sample = one **`.fcs` file**
(Flow Cytometry Standard format), containing tens of thousands to millions of events, each with values for
channels such as:

- **FSC** (forward scatter) ≈ cell **size**; **SSC** (side scatter) ≈ cell **granularity/complexity**.
- Fluorescence channels tied to **markers** you stained for — e.g. CD3, CD4, CD8, CD19 — each telling you
  whether a given protein is present on that cell.

**The raw `.fcs` file is a giant table of dots, not an answer.** To get biology out of it you have to **gate**:
draw boundaries that pick out meaningful groups of cells (first the real cells, then specific populations). That
gating-and-counting is the analysis BioMate runs.

---

## 2. The BioMate analysis it drives (and why)

The everyday question from a stained panel is **immunophenotyping**: *"What cell populations are in this sample,
defined by their surface markers, and what percentage is each?"* (e.g. "what fraction of live cells are
CD3+CD4+ helper T cells?"). Doing this means **gating** in sequence — a decision tree:

1. **Remove junk** — gate on FSC/SSC to keep real, single cells (exclude debris and clumps). *(Why: debris and
   doublets create fake "populations" if you don't.)*
2. **Pick lineages** — gate on markers to define each population (e.g. CD3+ = T cells; within those, CD4+ vs.
   CD8+). *(Why: this is how a "population" is actually defined — by a combination of marker thresholds.)*
3. **Count and report** — report each population as a **percentage of its parent** and an absolute count.

**The workflow BioMate routes this to:** **`Analyze Flow Cytometry Immunophenotyping`** (BioMate's
`cell_biology` domain) — described as *"analyse flow cytometry data to identify and quantify specific cell
populations based on surface markers."* Its real parameters are:

| Parameter | What it is / where to get it |
|---|---|
| **`fcs_file_path`** | The `.fcs` file to analyse. From your instrument export. |
| **`gating_strategy`** | The decision tree, written as named populations with marker thresholds. The panel pre-fills an example like `{"lymphocytes": [["FSC-A","between",[50000,150000]], ["SSC-A","between",[10000,80000]]]}` — you adapt the channel names and cut-offs to **your** panel. |
| **`compensation_matrix`** *(required)* | A spillover/compensation matrix to correct for fluorescence overlap between channels. *(Why it matters: dyes bleed into each other's channels; without compensation, a CD4 signal can masquerade as CD8. See §6 — this is the field people most often get stuck on.)* |

BioMate also has sibling workflows for other cytometry assays, routed automatically by what the file looks like:

| Your assay (what you stained/measured) | Workflow BioMate offers |
|---|---|
| Surface-marker panel, "what populations and what %" | **`Analyze Flow Cytometry Immunophenotyping`** (the main one) |
| **CFSE / CellTrace dye-dilution** to measure cell division | **`Analyze Cfse Cell Proliferation`** (reports division/proliferation; param `cfse_channel`, e.g. `FL1-A`) |
| **Intracellular cytokines** (ICS) in CD4+ T cells (IFN-γ, IL-17) | **`Analyze Cytokine Production In Cd4 Tcells`** |
| **Apoptosis / senescence** (Annexin V, PI) | **`Analyze Cell Senescence And Apoptosis`** |

> **Honest note up front:** the flow-cytometer *connector* tags each file group with an internal routing label
> (e.g. `immunophenotyping`, `cfse_proliferation`) based on the file/folder name and channels. That label is a
> **hint** — when you Launch, BioMate routes to the real workflow above. If it guesses the wrong assay, just say
> what you did (e.g. "this is a CFSE proliferation assay") in the chat. See §6 for validation status.

---

## 3. Before you start — get the data in (see T6)

- **Connect the cytometer (best for a core facility or regular use).** Register a **Flow cytometer** instrument
  in **Connectors → Instruments** and have your admin point its file-watcher at your FACSDiva / CytExpert output
  folder. The watcher groups `.fcs` files by experiment folder and surfaces each completed run as a **New data
  event**. Full steps: **Tutorial 6**.
- **Upload by hand (one-off).** Bring a single `.fcs` file in from the Data area. Full steps: **Tutorial 4**.

**What you need to know before running:** your **channel names** (exactly as the instrument wrote them, e.g.
`FSC-A`, `SSC-A`, `FL1-A`, or marker names), the **gating logic** you'd normally draw by hand, and your
**compensation matrix** (usually produced from single-stain controls on the instrument).

---

## 4. Step by step — run it

<!-- CAPTURE route=/ ; state=New data events list showing a flow-cytometry event (experiment type "immunophenotyping", source flow cytometer watcher, N FCS files) with Launch + Dismiss ; focus=instrument-event ; note=show a flow-cytometry New-data event card: FCS file count, cytometer name, experiment-type badge, Launch button -->
*(Figure to add: a flow-cytometry New-data event — number of FCS files, cytometer name, the "immunophenotyping" badge, and the Launch button.)*

1. **Start from the data event (or ask).** Click **Launch** on the cytometry event (opens a pre-filled draft,
   nothing runs yet), or type e.g. *"Immunophenotype this FCS file; gate lymphocytes on FSC/SSC, then CD3+ T
   cells, then CD4 vs CD8; report population percentages."*
2. **Check the workflow.** The panel should open **Analyze Flow Cytometry Immunophenotyping** (not "undefined").
   If your file is a CFSE/cytokine/apoptosis assay and it opened the wrong one, say which assay it is (§2).
3. **Set the gating strategy** (`gating_strategy`). Edit the pre-filled example to match **your** panel: use your
   real channel names and your own cut-offs for each population. Think of it as writing down, in text, the gates
   you'd otherwise draw with a mouse.
4. **Provide the compensation matrix** (`compensation_matrix`, required). Supply the spillover matrix from your
   single-stain controls. *(If you genuinely acquired pre-compensated data, see §6.)*
5. **Attach the `.fcs` file** if not already linked from the event, then **Confirm & Run**.

<!-- CAPTURE route=/ ; state=Workflow panel pre-run for Analyze Flow Cytometry Immunophenotyping, param strip showing fcs_file_path, gating_strategy, compensation_matrix ; focus=workflow-panel ; note=show pre-run panel: workflow name, the gating_strategy text field, the required compensation_matrix field, Confirm & Run -->
*(Figure to add: the pre-run workflow panel — the gating-strategy field with a worked example, the required compensation-matrix field, and the Confirm & Run button.)*

---

## 5. Reading the result / report

Open the **After run** section (two tabs — see **Tutorial 3**):

- **Summary** — the populations found and **what fraction of cells each one is**. Read it as a gating tree:
  e.g. "lymphocytes 62% of singlets → of those, CD3+ 71% → of those, CD4+ 43% / CD8+ 29%." Percentages are the
  headline number in immunophenotyping; compare them across your conditions.
- **Outputs** — the per-population counts and percentages as tables (`json`/`txt`/`csv`), filed under the step
  that produced them, plus any gating plots the workflow emits. Downloadable for your figures.
- **Reproducibility record** — the exact gating strategy, compensation matrix, and software version used, so the
  gating is documented and repeatable (not a one-off hand-drawn set of gates no one can reproduce).

> **What good looks like, and what to watch.** A sensible result has a clean singlet/lymphocyte gate (most
> events retained, not 90% thrown away) and population percentages that sum sanely within each parent. Be
> cautious if a population is a tiny fraction (a "0.1% CD4+" is easily noise or a gating artefact), or if
> uncompensated spillover is inflating a marker — that usually shows up as a smear rather than a clean cluster.

---

## 6. Honest limits — what to expect

- **Status: available, not yet validated on real data end-to-end.** `Analyze Flow Cytometry Immunophenotyping`
  and its CFSE / cytokine / apoptosis siblings are **real, indexed BioMate workflows** (confirmed in the
  catalogue, with real parameter schemas). They run on BioMate's `biomni_local` runtime (~16 GB RAM). However,
  BioMate has **no recorded real end-to-end FCS run** proving these on the development site, and flow-cytometry
  coverage is known to be thin. Treat them as *available-but-untested*: expect to verify the first run's gates
  and percentages against your manual analysis (e.g. in FlowJo) before trusting them.
- **The connector label is a routing hint, not a literal workflow.** The watcher's internal tags
  (`immunophenotyping`, `cfse_proliferation`, etc.) do **not** resolve verbatim to catalogue IDs; BioMate routes
  your Launch to the real workflow by matching your request. Steer it in chat if it guesses the wrong assay.
- **Compensation is on you.** The immunophenotyping workflow **requires** a compensation matrix and does not
  compute one from your single-stain controls for you. Get the matrix from your instrument/acquisition software.
  If you feed uncompensated data without a matrix, populations can be wrong in ways that *look* plausible.
- **One file at a time.** The immunophenotyping and dye-dilution workflows take a **single `.fcs` path**. For a
  multi-sample experiment, run per sample (or per tube) and compare the resulting percentages yourself — there
  is no built-in batch/concatenation or statistical comparison across many FCS files in these workflows today.
- **No automated/unsupervised clustering here.** These workflows do **threshold-based gating** from the strategy
  you supply — they are not FlowSOM/UMAP-style unsupervised population discovery. If you need that, say so in
  chat and treat the result as exploratory.

---

## 7. Where to go next

| You want to… | Where |
|---|---|
| Connect the cytometer so runs arrive automatically | **Tutorial 6** |
| Bring a single `.fcs` file in by hand | **Tutorial 4** |
| Understand the two-tab report | **Tutorial 3** |
| Measure cell division instead of phenotype | ask for **`Analyze Cfse Cell Proliferation`** |
| Measure cytokine production in CD4+ T cells | ask for **`Analyze Cytokine Production In Cd4 Tcells`** |

The habit: **Launch the cytometry event → confirm the right assay workflow → write your gating strategy +
supply compensation → run → read population percentages.**

---

## 8. Key terms

| Term | What it means — and why you care |
|---|---|
| **FCS file** | One sample's flow data — every cell's scatter + fluorescence values. Big table of dots, not an answer. |
| **Event** | One cell (or particle) measured. "100,000 events" = 100,000 cells recorded. |
| **FSC / SSC** | Forward scatter ≈ size; side scatter ≈ granularity. Used for the first "keep real cells" gate. |
| **Gating** | Drawing boundaries to pick out populations, step by step. The core of flow analysis. |
| **Gating strategy** | The gating decision tree written down (populations + marker thresholds) so it's reproducible. |
| **Marker (CD3, CD4, …)** | A protein you stained for; its channel tells you if a cell has that protein. |
| **Compensation / spillover matrix** | A correction for dyes bleeding into each other's channels. **Required** here; get it from single-stain controls. |
| **Immunophenotyping** | Identifying and counting cell populations by their marker combinations. |

---

_Grounded in: `biomate-connector/lab_instruments/flow_cytometer_connector.py` (experiment-type → workflow
routing) and the BioMate catalogue entries `Analyze Flow Cytometry Immunophenotyping` (cell_biology),
`Analyze Cfse Cell Proliferation` (immunology), `Analyze Cytokine Production In Cd4 Tcells` (immunology),
`Analyze Cell Senescence And Apoptosis` (cancer_biology) — all confirmed via workflow search. Companion:
Tutorials 3, 4, 6._
