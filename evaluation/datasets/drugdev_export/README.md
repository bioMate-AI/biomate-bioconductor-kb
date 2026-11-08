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

## Design requirements (mandatory, carried from the landscape survey)

1. **Leakage-aware splits** (temporal / similarity-stratified) for every structure/affinity/VS/target task — the 2024–2026 state of the art (LP-PDBBind, CleanSplit/GEMS, PLINDER, Runs-N-Poses, DockGen, BayesBind, TDC-DTI-DG). A naive-split benchmark is obsolete on arrival.
2. **Anti-reward-hacking, multi-objective, physical-validity metrics** — not affinity-only ("Beyond Affinity" shows Vina-as-reward is gameable; GenBench3D shows most generated molecules are 3D-invalid).
3. **Execution-grounded scoring** where BioMate is differentiated.
4. **Exclude data-boundary tasks** (Phase II/III outcomes, PopPK, survival, RWE).

## Benchmarks — organised in four tracks

The series is NOT only tool/execution workflows. Early-stage target discovery, perturbation, search, and knowledge are first-class tracks (they are well-benchmarked externally — we **compete + cite**, we do not claim to own them). Track 4 is the genuine white space BioMate owns.

**Track 1 — molecular / tool-workflow** (compete + cite): B1 `admet_benchmark` (20; vs TDC/ADMET-AI) · B2 `docking_benchmark` (15; **public in RealBio**; vs PoseBusters/PLINDER, leakage-split) · N1 `rbfe_benchmark` (vs OpenFE/JACS/Merck) · N2 `qsar_benchmark` (vs MoleculeACE) · N3 `generation_benchmark` (vs GuacaMol/PMO + GenBench3D validity) · N4 `retrosynthesis_benchmark` (vs PaRoutes/Syntheseus).

**Track 2 — early-stage / target & perturbation** (compete + cite): T2a `target_id_benchmark` (vs Open Targets/PrimeKG/TxGNN) · T2b `perturbation_benchmark` (vs GEARS/PerturBench/Virtual Cell Challenge/BioDiscoveryAgent) · B5 `target_structure_benchmark` (10; vs CASP/CAMEO/PLINDER).

**Track 3 — search / retrieval & knowledge** (compete + cite): T3a `retrieval_benchmark` (vs PaperQA2/STaRK-PRIME/LitQA2) · T3b `knowledge_benchmark` (vs ChemBench/MoleculeQA/BioKGBench).

**Track 4 — execution-grounded & cross-stage (OWN — white space):** B3 `pbpk_benchmark` (15; **public in RealBio**; no external PBPK ML benchmark) · B4 `boin_benchmark` (20; **public**; dose-from-data) · N5 `stability_benchmark` · N6 `novelty_fto_benchmark` · N7 `ind_narrative_benchmark` · **N8 `pipeline_e2e_benchmark` (flagship)** · **N9 `cross_stage_benchmark`**.

**Priority build order:** N8 end-to-end (flagship, reuses `execution_grader`) → N9 cross-stage → N1 RBFE → export B1/B5 → N5/N6/N7 → Track 2/3.

Scorers and adapters already exist internally for B1–B5 (`evaluation/scorers/{admet,pbpk,boin,docking}_scorer.py`, `evaluation/adapters/*_benchmark_adapter.py`; gold in `evaluation/datasets/{admet,pbpk,boin,target_structure}_benchmark/`, `drug_discovery_e2e/`). The L1–L6 execution-scored engine stays internal; this export layer provides public, comparable, reproducible packaging.

## Running (mirrors RealBio)

The runner/scorer reuse RealBio's machinery (`../public_export/run_all.py`, `score.py`, `models.yaml`). The model roster is the RealBio roster — frontier flagships + the four leading Chinese open families (Qwen, DeepSeek, GLM, Kimi) + BioMate + Biomni. Build/export of the internal gold into this bundle is performed by a `build_export.py` (to be added, mirroring `../public_export/build_export.py`).

**This is a scaffold, not a finished export.** Per-benchmark item files and the leaderboard are produced by the build/export + sweep steps, not committed here yet.
