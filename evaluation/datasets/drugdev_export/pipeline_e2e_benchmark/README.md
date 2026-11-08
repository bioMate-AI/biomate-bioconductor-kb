---
license: cc-by-4.0
---
# BioMate DrugDev Benchmark — pipeline_e2e_benchmark (N8) · **FLAGSHIP · PLANNED STUB**

*Part of the **BioMate DrugDev Benchmark** (see the suite README). Track 4 (execution-grounded, cross-stage). This is the differentiating benchmark: no external benchmark grades a full drug-development pipeline **run** against real artifacts.*

**Status: STUB (not yet built).** The engine exists (`evaluation/local_trial/execution_grader.py` — terminal success + S3 output-content validation with a tiered 0→1 reward and per-workflow correctness contracts). What's missing is the benchmark layer: a held-out task set + an end-to-end scorer that composes execution grading with selection/QC/interpretation layers.

## Why this is the white space

Every external drug-dev benchmark grades a single stage's *prediction* (ADMET value, pose RMSD, ΔΔG, trial outcome) or an agent's *QA/analysis*. None grades whether an agent can take a real request, **select the right workflow, run it, pass QC, interpret the real outputs, and report** — judged against the actual terminal state and S3 artifacts. That is exactly what BioMate's execution engine does, and it is unoccupied territory.

## Task

Given a natural-language drug-dev request (optionally with input data pointers), the agent must drive the full loop: **request → workflow selection → parameter prefill → prerequisite check → execution → QC gate → output interpretation → report**. The benchmark grades the *run*, not a predicted number.

**Input (per case):** `prompt` (e.g. "Screen this SMILES series for hERG and CYP3A4 liability and flag anything that fails the gate"), optional `inputs` (S3/data pointers), `scenario_stage` (S0–S6).

**Ground truth (per case):** `expected_workflow(s)` (+ acceptable alternatives), `output_contract` (required output files + content checks, reusing `execution_grader` `register_contract`), `expected_findings` (objective keys the interpretation must surface — e.g. "compound X fails hERG gate at <1 µM"), and the QC-gate outcome.

## Scoring (multi-signal, anti-reward-hacking by design)

Compose the existing 6 execution layers with the execution grader, as a **vector**, never a single gameable scalar:
- **L1–L4** intent / routing / params / prerequisites (did it select + configure the right workflow?) — reuse routing/param scorers.
- **L5 execution** — `execution_grader.grade_detailed` terminal tier (completed + ≥1 non-versions output >0 bytes).
- **L6 output validity** — per-workflow `output_contract` (CSV rows, JSON keys, molecular-identity checks) via the contract registry.
- **Interpretation** — did the report surface `expected_findings` (objective, keyed), not prose vibes.
- **QC** — did the gate fire correctly (halt/advisory/pass) when it should.
Report the vector + a documented weighted composite; **no affinity-only or single-metric success** ("Beyond Affinity" lesson).

## Design requirements (from the landscape survey)

- **Leakage control:** task prompts drawn from held-out scenario templates with no lexical/structural overlap with training request templates; input compounds/targets time- or similarity-split from any training data.
- **Honest positioning:** LLMs used directly *cannot execute* — this benchmark primarily separates agent **platforms that actually run pipelines** (BioMate, Biomni) from direct LLMs (which should score ~0 on L5/L6). That is the point: it measures execution capability the single-stage benchmarks cannot.
- **Real artifacts only:** grade against the actual terminal state + S3 outputs, never a self-reported claim.

## Example cases (to curate, spanning stages)

1. S2 ADMET screen of a SMILES series → hERG/CYP gate → flag failures → report. (contract: admet)
2. S1 virtual-screen/dock a ligand set vs a target → rank → report top hits. (contract: docking)
3. S4 PBPK for a compound+dose+route → Cmax/AUC → compare to a target exposure. (contract: pbpk)
4. Cross-domain: RNA-seq DE → pathway enrichment → interpret (tests general routing + execution).

## TODO to build

1. Curate ~15–25 held-out end-to-end cases (prompt + inputs + expected_workflow + output_contract + expected_findings), spanning S0–S6, with leakage-aware templates.
2. Add `evaluation/adapters/pipeline_e2e_adapter.py` composing L1–L6 + `execution_grader`.
3. Add `register_contract` entries for any case workflows not already covered.
4. Wire into the series `run_all.py`; produce the per-model leaderboard (expect direct-LLM rows ≈0 on execution, agent-platform rows meaningful).
5. **Requires the live execution stack (AWS Batch) to produce real run artifacts** — this is NOT an offline-only benchmark; schedule a gated run, do not fabricate artifacts.
