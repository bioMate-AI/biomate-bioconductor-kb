---
license: cc-by-4.0
---
# BioMate DrugDev Benchmark (working title — name TBD)

*Execution-grounded, cross-stage drug-development benchmarks for AI agents. A sibling series to [RealBio](../public_export/README.md), focused on the drug-development pipeline (target ID → hit discovery → hit-to-lead → lead optimization → preclinical → Phase I → regulatory).*

**Status: SCAFFOLD (2026-10-21).** This directory packages BioMate's existing drug-dev benchmarks (B1–B5) in the RealBio public-export format and stubs the net-new tasks. Design, landscape survey, and rationale: `docs/20261021_DRUGDEV_BENCHMARK_LANDSCAPE_AND_SERIES.md`.

## Why this series exists

The external benchmark landscape is almost entirely **single-stage prediction** (TDC/ADMET-AI, PDBbind/CASF/PoseBusters, OpenFE-FEP, GuacaMol, USPTO, TrialBench) or **QA / siloed-analysis agent tasks** (LAB-Bench, GPQA, HLE, BixBench, MedAgentBench). **No existing benchmark grades an execution-grounded, cross-stage drug-development pipeline against real run artifacts.** That is the white space this series owns. PBPK and graded dose-escalation decisions have **no external ML benchmark at all**; IND-narrative, FTO/novelty, formulation/stability, and closed-loop DMTA are entirely uncovered.

## Honesty constraints (carried into the manuscript)

- Report baselines unedited. Frontier LLMs are strong at ligand ranking (~0.69) but **near-useless at PBPK** (~0.075) and weak at dose-finding (~0.27); BioMate's PBPK same-item ties the best LLM and **does not lead**. The platform's advantage is execution / routing / QC / cross-stage orchestration, not single-task prediction.
- Any structure / co-folding / virtual-screening task MUST use **leakage-controlled, temporal/similarity-stratified splits** (the PLINDER / Runs-N-Poses finding that AF3/Boltz/Chai memorize rather than generalize).
- Use validated counts only (the firmly Batch-validated drug-dev workflow subset is 24, IDs 12861–12884; the "~215 workflows" figure is unconfirmed).

## Benchmarks

| Code | Benchmark | Stage | Items | Status | External baseline |
|---|---|---|---|---|---|
| B1 | `admet_benchmark` | S2 hit-to-lead | 20 | built (internal) — ready to export | TDC ADMET, ADMET-AI |
| B2 | `docking_benchmark` (drug_discovery_e2e) | S1 hit discovery | 15 | **public in RealBio** | PDBbind, CASF-2016, PoseBusters |
| B3 | `pbpk_benchmark` | S4 preclinical | 15 | **public in RealBio** | none (novel — no external PBPK ML benchmark) |
| B4 | `boin_benchmark` | S5/6 Phase I | 20 | **public in RealBio** | TrialBench dose-finding (BOIN itself is method-only) |
| B5 | `target_structure_benchmark` | S0 target ID | 10 | built (internal) — ready to export | CASP, CAMEO, PLINDER |
| N1 | `rbfe_benchmark` | S3 lead-opt | TBD | **planned (stub)** | OpenFE, JACS-FEP, Merck-FEP |
| N2+ | qsar, generation, retrosynthesis, stability, novelty_fto, ind_narrative, pipeline_e2e, cross_stage | various | TBD | planned | MoleculeACE / GuacaMol / USPTO / (novel) |

Scorers and adapters already exist internally for B1–B5 (`evaluation/scorers/{admet,pbpk,boin,docking}_scorer.py`, `evaluation/adapters/*_benchmark_adapter.py`; gold in `evaluation/datasets/{admet,pbpk,boin,target_structure}_benchmark/`, `drug_discovery_e2e/`). The L1–L6 execution-scored engine stays internal; this export layer provides public, comparable, reproducible packaging.

## Running (mirrors RealBio)

The runner/scorer reuse RealBio's machinery (`../public_export/run_all.py`, `score.py`, `models.yaml`). The model roster is the RealBio roster — frontier flagships + the four leading Chinese open families (Qwen, DeepSeek, GLM, Kimi) + BioMate + Biomni. Build/export of the internal gold into this bundle is performed by a `build_export.py` (to be added, mirroring `../public_export/build_export.py`).

**This is a scaffold, not a finished export.** Per-benchmark item files and the leaderboard are produced by the build/export + sweep steps, not committed here yet.
