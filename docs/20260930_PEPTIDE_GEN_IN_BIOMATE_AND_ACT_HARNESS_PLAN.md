# Cyclic-Peptide Generation: What's in BioMate + the ACT Round-1 Harness Plan

**Date:** 2026-09-30 · **Context:** ACT (Accelerator for Cancer Therapeutics) application, IO cyclic-peptide
program. Companion to `20260930_ACT_APPLICATION_WORKING_PROTOCOL.md` (§3 generation) and
`20260927_PEPTIDE_PARALLEL_WORK_PLAN.md` (the generator R&D).

## 0 · Correction (honesty contract)
An earlier claim — "the cyclic-peptide generation process is NOT in BioMate" — was WRONG. It came from grepping
only the LOCAL repo; but the BioMate workflow DB + `biomate-ai-tools/` live on dev/S3 (gitignored). Querying the
**live BioMate catalog** (MCP `search_workflow` / `get_workflow_spec`) shows cyclic-peptide + structure-based
generation **is** in the product. This is the under-count-from-memory failure mode flagged in
[[feedback_find_authoritative_docs_first]] — always query the live catalog/DB before asserting BioMate lacks X.

## 1 · What IS in BioMate now (verified via the live catalog)
| Workflow (in catalog) | What it does | Engine |
|---|---|---|
| **`cyclic_peptide_design`** (`biomate-ai-tools/cyclic_peptide_design/main.nf`) | 5-phase de-novo cyclic-peptide design: (A) target-pocket analysis (curated hotspot DB) → (B) **CyclicMPNN** seq design + **N-methylation** opt → (C) **macrocycle ADMET (Yudin 2015**: MW 500–1200, chameleonic, effective-HBD-after-N-Me — not Lipinski) → (D) **AlphaFold3** input for top-5 → (E) design report + **IND-prep summary**. Outputs: candidates.csv, macrocycle_admet_report.json, top5_af3_inputs/, rfdiffusion_input.json, report.html. Validated vs voclosporin/cyclosporin precedent. | ✅ Batch, chat/MCP |
| **`bionemo_structure_design`** | NVIDIA BioNeMo NIM: structure prediction (ESMFold, **Boltz2**, AF2), **RFdiffusion+ProteinMPNN** design, **docking** | ✅ Batch |
| **`REINVENT4 Generative Lead Design`** | AstraZeneca RL generative (de-novo / scaffold-hop / docking_gnina scoring) — small-molecule | ✅ Batch |

**Caveat (do not over-claim):** these EXIST in the catalog as defined, engine-invokable workflows. I have NOT
verified `cyclic_peptide_design` has been run end-to-end on a real target (per [[project_workflow_validation_gaps]],
some catalog workflows are defined-but-unvalidated). "In BioMate" = **defined + invokable**; "validated end-to-end
in BioMate" = needs a real run to confirm.

## 2 · What is NOT in BioMate (the research harness)
The newer generator stack I've been running for the ACT PD-L1 task is a **separate research implementation**,
standalone on AWS spot (NOT through the engine), NOT in the catalog:
`research/guangzhou_all_atom/` — **BoltzGen** (lead), **PepGLAD-M2c** (ours, DockQ 0.437 diversity arm),
**cyclic MM-GBSA** verify, **permeability GBM**, **GP-Pareto/HVI** select, **DMTA orchestrator**.

## 3 · The accurate picture — two parallel implementations
| | Production `cyclic_peptide_design` | Research harness `guangzhou_all_atom` |
|---|---|---|
| Generator | CyclicMPNN + RFdiffusion + AF3 | **BoltzGen** + PepGLAD-M2c |
| Target focus | **autoimmune** (IL-17A / IL-6R / calcineurin) | any structure — running **PD-L1 / IO** now |
| Developability | Yudin macrocycle ADMET, IND report | permeability GBM + MM-GBSA + GP-Pareto |
| In the engine? | ✅ yes | ❌ no (standalone spot) |
| Run evidence | defined; end-to-end run unverified | ✅ run on 4–6 targets (best iptm 0.79) |

The gap is narrower than first stated: NOT "cyclic-peptide gen is absent from BioMate," but (1) the production
workflow targets **autoimmune**, not IO, and (2) the research **BoltzGen/PepGLAD/MM-GBSA/DMTA** stack is not yet
reconciled into the production workflow.

## 4 · Decision + plan (user directive 2026-09-30: **harness first**)
**Chosen: (b) harness-first for ACT traction.** Rationale: BoltzGen has the measured results, the protocol §3
explicitly specifies the research harness, and it's runnable now. Productizing into BioMate is a separate,
later step (not a blocker for the ACT traction artifact).

### 4a · Now — ACT Round-1 PD-L1 generation (research harness)
`[0]` target-prep DONE — PDB **5O45** (PD-L1 chain A + macrocyclic peptide-71 chain B, 0.99 Å); pocket-build
verified **19 residues** at the PD-1 face, `design_len 10..16` (ncAA-inclusive pocket fix landed).
`[1]` GENERATE — BoltzGen 200 de-novo cyclic binders (in flight, `stage=design_5o45`, CUDA ok) + PepGLAD-M2c
diversity arm.
`[2]`–`[7]` re-rank chain — A3 gate → designability → **MM-GBSA ΔG** → permeability → **GP-Pareto/HVI → N=12–15**.
`[8]` order sheet = the **ACT traction artifact** (in-silico panel; wet-lab confirm = parallel session's quota line).
Thresholds: iptm ≥0.6 (strong ≥0.79); consistency ≥0.8; diversity ≥0.75. Compute ~$65–90/target/round, spot-only.

### 4b · Later — productize into BioMate (separate workstream, NOT gating ACT)
To make the platform claim literally true + honor "BioMate is the execution engine":
(1) reconcile the BoltzGen/PepGLAD/MM-GBSA/DMTA stack into the production `cyclic_peptide_design` workflow (or a
new IO variant); (2) add **IO/PD-L1 targeting** (production one is autoimmune-oriented); (3) end-to-end
validation run through the engine (Batch); (4) wire the DMTA loop as a first-class product feature.

## 5 · Status snapshot (2026-09-30)
- PD-L1 BoltzGen run: `i-03d8e208e11b8b0c5` (g6.2xlarge, us-west-2), RUN `boltzgen-oversample-5o45-…172457Z`;
  pocket verified, mid-generation. Poller `be2u0hk05`.
- On completion → drive the §3 re-rank → 12–15 PD-L1 panel.
