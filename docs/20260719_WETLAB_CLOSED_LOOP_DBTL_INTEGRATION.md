# Wet-Lab Closed-Loop (DBTL) Integration — Plan Addendum

**Date:** 2026-07-19 · Extends the autoimmune + cyclic-peptide model-training plan.
**Key point:** the DBTL machinery is *already largely built* — we wire our models into it, we don't build it from scratch.

## 1. What already exists (audited)

**(a) AI tool DB — `lab_automation` domain (8 workflows), PyLabRobot-centric:**
| Tool | Role |
|---|---|
| Get Pylabrobot Documentation (Liquid / Material) | Retrieve PyLabRobot API docs for liquid-handling / labware |
| Test Pylabrobot Script | Simulate + validate a PyLabRobot protocol (tracking, timeout, report) |
| Run Async / Target / Pick First | PyLabRobot helper modules (async exec, targeting, selection) |
| **omixer** | Multi-well plate-layout randomization + sample-sheet generation (experimental design) |
| (HTML Output Test) | E2E test stub — ignore |

**PyLabRobot** = the hardware-agnostic Python framework that controls liquid-handling robots (Hamilton STAR, Opentrons, Tecan…). So the DB gives the **BUILD-script authoring/validation layer**; `omixer` gives the **plate-design layer**.

**(b) biomate-connector `lab_instruments/` — the DBTL controller + 10 instrument drivers:**
- `dbtl_controller.py` — a working **Design→Build→Test→Decide→Learn** loop (`DBTLController.run()`, `make_opentrons_design`, `make_biomate_analyze`, `threshold_policy`, `SimRobot` demo).
- Connectors: opentrons, benchling, cryoem, flow_cytometer, illumina_basespace, lcms, nanopore_minknow, plate_reader, qpcr, sila2_adapter, instrument_watcher.

**So the mechanics exist** (loop controller + robot scripting + instrument drivers + data ingestion). The gap (per prior audit): **no real model-in-the-loop active-learning refinement wired to a real assay.** That gap is exactly what this plan closes.

## 2. How it plugs into the model plan (the flywheel = the moat)

| DBTL role | Provided by |
|---|---|
| **DESIGN** | *our models*: macrocycle-ADMET/design model → permeable cyclic peptides vs the autoimmune PPI; SLE virtual cell → target/perturbation |
| **BUILD** | PyLabRobot script (assay prep / liquid handling) + `omixer` plate layout; peptide synthesis via CRO/synthesizer *(gap)* |
| **TEST** | instrument connectors ingest assays — permeability: `plate_reader`+`lcms`; binding: SPR/BLI *(gap)*; cell response: `flow_cytometer` + scRNA via `illumina`/`nanopore` |
| **DECIDE** | `threshold_policy` (exists) **+ uncertainty-guided acquisition (add)** |
| **LEARN** | ingest results → append to training set (S3) → retrain model → next round |

**This is the answer to "if it's public data, everyone can do it":** every wet-lab round produces **proprietary** data competitors can't get, and **prospective** validation (predictions holding on *newly synthesized* peptides) is Nature/Science-grade evidence — far stronger than a retrospective CycPeptMPDB R².

## 3. Per-track loop
- **Cyclic peptide (priority):** Design (macrocycle model) → Build (CRO SPPS + PyLabRobot assay prep, omixer layout) → Test (PAMPA/Caco-2 permeability; SPR affinity) → Learn (retrain) → benchmark vs voclosporin.
- **SLE virtual cell:** Design (perturbation/target) → Build (Opentrons/PyLabRobot stim plate) → Test (flow-cytometry immune state; scRNA) → Learn (refine virtual cell).

## 4. The one real methodological addition — active learning
Add an **acquisition function** (model uncertainty / Bayesian optimization) to `DBTLController`'s DECIDE step so each round synthesizes the *most informative* small batch (N≈20–50), not a threshold pass/fail. Store rounds in S3 (`cyclic_peptide/wetlab_rounds/round_k/`, `autoimmune_sc_corpus/wetlab_rounds/`) and retrain from the growing set.

## 5. Gaps to fill (honest)
1. **Peptide synthesizer connector or CRO API** — PyLabRobot/Opentrons is liquid handling, not solid-phase peptide synthesis. First rounds likely via a **CRO**.
2. **SPR/BLI binding-assay connector** — for affinity (permeability is already covered by plate_reader+lcms).
3. **Acquisition/BO in DBTLController** — currently a simple threshold policy.
4. **Real instrument creds / first CRO partner** — loop is `SimRobot`-simulated today.

## 6. Sequencing
Once the cyclic-peptide permeability baseline gate + first macrocycle model land: run the **first prospective round** — predict top-N → synthesize via CRO → measure PAMPA → ingest via connectors → refine. Small, cheap, and it delivers the first proprietary datapoints + validates the loop end-to-end. Implementation = provide DESIGN/LEARN fns to the existing `DBTLController`; reuse PyLabRobot (Build) + `plate_reader`/`lcms` (Test).
