# Instrument tutorial — Benchling ELN / LIMS → drug-discovery ADMET screening

> **Who this is for:** anyone whose lab records compounds and assay results in Benchling (an electronic lab
> notebook / sample-tracking system) and wants those results to drive a BioMate drug-discovery analysis. No
> coding needed to read this.
> **Time:** ~10 minutes.
> **Where it fits:** Tutorial 6 showed how to *register* a connection. This tutorial answers: *"My compounds
> and assay numbers live in Benchling — what analysis does BioMate run on them, how do I start it, and how do I
> read the result?"*

---

## 1. The problem this solves

Benchling is not an instrument that measures anything — it is the **system of record** where a drug-discovery
team keeps its compounds (with their chemical structures) and the assay numbers measured against them (potency,
toxicity, and so on). The analysis question is: *given this growing list of compounds and their measured
results, which ones are worth making next, and are any of them likely to be unsafe?*

BioMate answers that with its **drug-discovery campaign** — a running project that ingests assay results,
predicts safety and drug-like properties for each compound, ranks them, and can assemble the regulatory
paperwork. Benchling's job is to **feed** that campaign: the compounds and their measured assay values flow
from Benchling into the campaign, so you do not re-type them.

> **In one sentence:** Benchling supplies the compounds and measured assay results; BioMate's drug-discovery
> campaign predicts each compound's safety/ADMET properties, ranks them, and keeps the record — so the team
> knows which molecules to pursue.

---

## 2. What this "instrument" produces

From Benchling, BioMate reads:

- **Compounds / samples** — each with a chemical structure written as **SMILES** (a text string that encodes a
  molecule), plus identifiers like a batch number, concentration, and plate position.
- **Assay results** — the measured numbers for those compounds (e.g. an **IC50** in nanomolar, a measure of how
  potent a compound is — lower means more potent), each tied to a compound and an assay type.
- **Notebook context** — the free text of a notebook entry, for provenance.

These are **wet-lab facts**: real molecules and the numbers measured on them. They become the *input* to the
analysis in §3.

---

## 3. The BioMate analysis it drives (and why)

The analysis Benchling data drives is **ADMET screening inside a drug-discovery campaign**. Two real pieces
confirm this path:

1. **The campaign pulls assay results from Benchling.** BioMate's drug-discovery module exposes an endpoint to
   pull Benchling assay results into a campaign (`…/lims/poll`) and ingest them (`…/ingest-assay`), which then
   updates the compound ranking. This is the "automatic assay-result pulling for drug-discovery campaigns"
   noted in Tutorial 6 — it is the campaign flow, separate from the plain instrument registry.
2. **The predictive analysis is a real catalog workflow.** The compounds' SMILES feed BioMate's ADMET
   workflow — **Predict ADMET Properties (AI)** (`predict_admet_properties`), which uses graph-neural-network
   models (ADMET-AI, Swanson et al. 2023) trained on millions of experimental measurements to predict ~15
   endpoints, including **hERG cardiotoxicity**, CYP enzyme inhibition, blood–brain-barrier penetration,
   solubility, and half-life.

Putting it together, the campaign cycle is: **Benchling supplies compounds + measured assays → BioMate predicts
ADMET/safety for each compound → compounds are ranked (measured results + predictions) → risky compounds are
flagged, promising ones rise → (optionally) results push back to Benchling and the regulatory IND paperwork is
assembled.**

**Why ADMET:** most drug candidates fail not because they are weak, but because they are unsafe or behave badly
in the body (poor absorption, fast clearance, heart-rhythm risk from hERG). Screening every compound's ADMET
profile early, against the measured potency, is how a team avoids spending months on a molecule that was never
viable.

> **What ADMET means:** **A**bsorption, **D**istribution, **M**etabolism, **E**xcretion, **T**oxicity — the
> properties that decide whether a potent molecule can actually become a safe, usable drug.

<!-- CAPTURE route=/drug-discovery-cro ; state=CRO Library / drug-discovery campaign view showing a compound ranking table with ADMET columns (incl hERG) and a measured assay column ; focus=campaign-ranking ; note=show the campaign compound ranking combining Benchling assay values with predicted ADMET -->
*(Figure to add: a drug-discovery campaign ranking — compounds from Benchling with their measured assay value
alongside predicted ADMET columns including hERG.)*

---

## 4. Before you start — connecting Benchling

Do Tutorial 6 (*Connecting instruments*) first for the connection basics:

- Benchling is a **cloud** service, so its residency badge is **cloud** — **data leaves your organisation's own
  systems** when BioMate reads from it. Check this is acceptable for your data before connecting.
- It connects with an **API key / token** (not a host/port) — you provide a Benchling API key for your tenant
  (e.g. `yourorg.benchling.com`).
- The key lets BioMate **check and store** the connection; the *automatic assay pulling* into a campaign is the
  separate drug-discovery campaign flow (above), set up by an admin, not from the plain instrument registry.
- You will create or open a **drug-discovery campaign** (the **CRO Library** in the sidebar is the entry point
  for this area) and point it at the Benchling assay schema that holds your results.

---

## 5. Step by step — run the screening

1. **Open the drug-discovery area.** From the sidebar, go to **CRO Library** (the drug-discovery / campaign
   surface) and open or create your campaign.
2. **Pull the compounds and assays from Benchling.** With the Benchling connection configured, the campaign
   ingests the assay results for your compounds (the `lims/poll` → `ingest-assay` path). Each compound arrives
   with its SMILES and its measured assay value.
3. **Run ADMET prediction.** The compounds' SMILES feed the **Predict ADMET Properties (AI)** workflow. You can
   also launch it directly in chat: *"Run ADMET screening on these compounds"* with the SMILES list. Review the
   settings before confirming.
4. **Confirm and run.** BioMate predicts the ~15 ADMET endpoints for every compound on cloud computers.
5. **Read the ranked result and the safety flags** (see §6). If a safety gate is configured (e.g. a hERG
   threshold), compounds that cross it are flagged rather than silently ranked high.

> **Nothing runs until you confirm**, and predictions never overwrite your measured Benchling values — they sit
> alongside them.

---

## 6. Reading the result

- **The compound ranking** — the campaign orders compounds by combining their **measured** assay values (from
  Benchling) with **predicted** ADMET properties. The top of the list is where the team looks first.
- **ADMET columns per compound** — predicted values for each endpoint. The one to watch is **hERG** (heart
  ion-channel risk): a compound predicted to block hERG strongly is a cardiac-safety concern, no matter how
  potent it is. Others — solubility, CYP inhibition, blood–brain-barrier — flag absorption, drug–drug
  interaction, and brain-exposure issues.
- **The two-tab report** (Tutorial 3) for an ADMET run — Summary (plain-language findings built from the real
  output files), Outputs (the per-compound predictions), and the Reproducibility record.
- **Export / paperwork** — the campaign can export a CRO order and, further along, assemble the regulatory IND
  document — the formal output a team hands to a contract research organisation or a regulator.

**How to act on it:** promote the compounds that are both potent (measured) and clean on ADMET (predicted);
hold or redesign the ones flagged for hERG or poor absorption. Predictions are a *filter that focuses the next
round of real experiments*, not a final verdict.

<!-- CAPTURE route=/drug-discovery-cro ; state=After-run ADMET report Outputs section showing per-compound predicted endpoints incl hERG, with a safety flag on one compound ; focus=admet-outputs ; note=show the ADMET per-compound predictions and a hERG safety flag -->
*(Figure to add: the ADMET After-run Outputs — per-compound predicted endpoints including hERG, with one
compound flagged on a safety gate.)*

---

## 7. Honest limits — what to expect

- **The Benchling connector has a mock mode — know which you are in.** The drug-discovery Benchling connector
  **falls back to synthetic data** when no real API key is configured (`mock_mode`). In that mode it returns
  *made-up* compounds and IC50 numbers for development and testing — **not your lab's data.** Before trusting a
  result, confirm a real Benchling API key is configured; otherwise you may be looking at synthetic placeholder
  compounds (e.g. generic `BNG-0001`-style IDs), not your molecules.
- **ADMET numbers are predictions, not measurements.** The ADMET workflow itself states its limits: predictions
  are estimates requiring experimental validation; the training data is biased toward drug-like small molecules;
  it may not generalise to unusual chemistry. Use the predictions to prioritise, then confirm the important
  calls in the lab.
- **The safety gate firing live is not fully proven here.** The ADMET workflow and its auto-loop (re-running
  with adjusted settings when a gate fails) are a core BioMate capability, but there is a known note that the
  hERG safety gate has not been confirmed to fire on a live run in all cases. Read the hERG value yourself;
  don't assume the gate caught everything.
- **Benchling is cloud residency.** Reading from Benchling means data leaves your organisation's own systems —
  account for that with restricted data.
- **Predictions sit beside measurements, never replace them.** Your measured Benchling assay values remain the
  ground truth; the ADMET predictions are an added layer.

---

## 8. Where to go next

| You want to… | Where |
|---|---|
| Connect Benchling / check residency | **Tutorial 6 — Connecting instruments** |
| Design new compounds to screen | **Tutorial 1 — Design & generate** |
| Understand the closed learning loop (measured data improving models) | **Tutorial 2 — Models & the closed loop** |
| Read any workflow's two-tab report | **Tutorial 3 — Running a workflow and reading the report** |
| Analyse a compound plate you physically prepared | **Opentrons instrument tutorial** |

The habit for this instrument: **connect Benchling (real key, not mock) → pull compounds + assays into a
campaign → run ADMET prediction → read the ranking and hERG flags → promote the safe, potent compounds.**

---

## 9. Key terms

| Term | What it means — and why you care |
|---|---|
| **ELN / LIMS** | Electronic lab notebook / sample-tracking system. Where compounds and assay results are recorded — the system of record. |
| **SMILES** | A text string that encodes a molecule's structure. The input the ADMET workflow reads for each compound. |
| **Assay result (e.g. IC50)** | A measured number for a compound (IC50 = potency; lower = more potent). The measured half of the ranking. |
| **Campaign** | A running BioMate drug-discovery project that ingests assays, predicts ADMET, and ranks compounds. |
| **ADMET** | Absorption, Distribution, Metabolism, Excretion, Toxicity — the properties that decide if a potent molecule can be a safe drug. |
| **hERG** | A heart ion channel; blocking it causes dangerous rhythm problems. The key safety endpoint to watch. |
| **Mock mode** | A fallback that returns synthetic (fake) data when no real Benchling key is set — useful for testing, dangerous if mistaken for real results. |
| **IND document** | The formal regulatory paperwork a campaign can assemble — the hand-off to a CRO or regulator. |

---

> **Honesty verdict for this instrument:** *Available; the predictive workflow is real, but disclose two
> caveats.* The Benchling→campaign path is real (the `lims/poll`/`ingest-assay` endpoints exist) and the ADMET
> workflow **Predict ADMET Properties (AI)** exists in the catalog and is a core capability. **Caveat 1:** the
> Benchling drug-discovery connector has a **mock mode** that returns synthetic data without a real API key —
> confirm you are on live data. **Caveat 2:** ADMET values are predictions requiring experimental validation,
> and the hERG safety gate is not confirmed to fire on a live run in all cases. Read the numbers yourself.

_Companion references: `docs/user-manual/tutorials/T6-connecting-instruments.md`;
`docs/user-manual/tutorials/T2-models-and-the-closed-loop.md` (how measured data feeds back);
`docs/user-manual/tutorials/T3-running-a-workflow-and-reading-the-report.md`._
