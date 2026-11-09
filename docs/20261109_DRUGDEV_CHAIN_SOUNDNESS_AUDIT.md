# Drug-development multi-phase chains — deployment & soundness audit

**Date:** 2026-11-09
**Scope:** verify the multi-step/phase drug-development chain capability is deployed on dev and sound (runs steps, passes data between phases, produces correct results).
**Method:** read the engine, submit real chains to the live dev engine (`/api/workflows/chain`) as the E2E fixture, poll to completion, inspect per-step state and the inter-phase data handoff; plus an offline audit of all drug-dev/pharmacology chain-template connections against the real workflow param schemas.

## Verdict

| Layer | State |
|---|---|
| **Deployment** | ✅ sound — engine (`workflow_chain.py`), DAG engine (`galaxy/chain/dag.py`), `chain_planner.py`, orphan reconciler, `_PARAM_TRANSFORMS`, and all **70 chain templates** are on dev. |
| **Engine mechanics** | ✅ sound — resolves workflow name → nextflow_path, runs steps sequentially (and DAG), **pre-validates each connection's `to_input` against the target workflow's declared params and fails fast** with a precise error. A valid 2-step chain (ADMET→CiPA) ran both steps to `succeeded`. |
| **Inter-phase data handoff** | ❌ **largely non-functional for drug-dev chains** — the actual value of a multi-phase chain. Two independent defects below. |

## Defect 1 — 11/24 template connections reference non-existent target params (hard fail)

Audit of every output→input connection in the 19 drug_discovery + 3 pharmacology chain templates: **11 of 24 connections** name a `to_input` that the target workflow does not declare or reference anywhere in its `.nf`. Confirmed live: the `admet_to_cipa_cardiac` chain ran step 1 (ADMET) to success, then the engine rejected the connection — `admet_results → admet_context`, and `cipa_cardiac_safety_ode` declares no `admet_context`. 7 templates affected:

| Template | Broken `to_input` |
|---|---|
| `target_to_lead_full` (6-step flagship) | GROMACS MD ← `docked_poses` |
| `admet_to_cipa_cardiac` | CiPA ← `admet_context` |
| `rnaseq_to_lincs_moa` | differentialabundance ← `counts` |
| `pbpk_renal_impairment_chain` | ← `pk_parameters`, `pk_model` |
| `phase2_dose_justification_chain` | ← `er_model`, `phase3_predictions` |
| `target_tractability_assessment` | AlphaFold ← `candidate_targets` |
| `mrna_codon_optimization_chain` | ← `candidate_constructs` |
| `cyp450_ddi_chain` | ← `in_vitro_ddi`, `human_pk` |

These chains run their first step and then hard-fail at the wiring to the next step — as stored they cannot complete end-to-end.

## Defect 2 — valid connections silently no-op; chain still reports `succeeded`

A corrected 2-step chain (ADMET → CiPA, wiring only the valid `herg_ic50_nM`) reported **`succeeded`** — but step 2's `handoff_warnings` held `"No artifact 'herg_ic50_nM' found from step 1"`, step 1's `artifacts` was `{}`, and CiPA ran on its **default** `herg_ic50_nM` (1000 nM), not the ADMET prediction.

Root cause: `_apply_connection_handoffs` matches `from_output` against the upstream's published **filenames** (`pick_artifact_file`). The templates author connections semantically (`from_output: herg_ic50_nM`), but ADMET publishes `admet_results.json`, not a `herg_ic50_nM` file — so no match, soft warning, fall back to default. A scalar handoff needs the real upstream output filename **plus a transform** to extract the scalar; the templates have neither.

So a multi-phase chain can report `succeeded` while **no data actually passed between phases** — a silent false success. The `handoff_warnings` are not surfaced to the user and do not gate success.

## What a fix requires (per template, not mechanical)

1. **Correct each connection to the real schema:** set `to_input` to a param the target workflow actually declares, and `from_output` to a filename the upstream actually publishes.
2. **Add scalar-extraction transforms** where the handoff is a number inside a results file (e.g. `admet_results.json` → `herg_ic50_nM`) — extend `_PARAM_TRANSFORMS` (today it has file-level transforms like `smiles_file_to_json_list`).
3. **Add a transform where shapes differ** (e.g. docking `vina_poses` → a best-pose ligand file for GROMACS's `ligand`).
4. **Engine hardening (recommended):** a chain with an unresolved declared handoff should not silently report `succeeded` — surface `handoff_warnings` and/or gate success, so Defect 2 cannot hide.
5. **Guardrail:** a template-connection validator (the offline audit here) wired into CI/registration so a connection naming a non-existent param is rejected at authoring time.

## Evidence
- Live runs (dev): `chain_1794261172_f64373` (admet_context rejected), `chain_1794261408_d60f70` (succeeded with silent default).
- Audit: 11/24 drug-dev/pharma connections reference params absent from the target `.nf` (verified against `params.<name>` references, not just declarations).

Related: [[project_composer_execution_bottleneck]] · [[project_drugdev_capability]] · workflow_chains (70 templates).
