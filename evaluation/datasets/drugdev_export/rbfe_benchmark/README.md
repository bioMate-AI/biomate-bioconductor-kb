---
license: cc-by-4.0
---
# BioMate DrugDev Benchmark — rbfe_benchmark (N1) · **PLANNED STUB**

*Part of the **BioMate DrugDev Benchmark** (see the suite README). Pipeline stage: S3 lead optimization. This is the first net-new benchmark — the single biggest workflow-only white space in BioMate's drug-dev coverage.*

**Status: STUB (not yet built).** Workflows exist (`openfe_rbfe`, `amber_peptide_mmgbsa`, `peptide_mmgbsa`) but there is no benchmark. This README specifies the intended design; gold data and scorer are TODO.

**Task.** Given a congeneric series of ligands against one target and a reference ligand, predict **relative binding free energies (ΔΔG)** for each transformation. The agent selects and runs the free-energy workflow (RBFE/FEP or MM-GBSA), executes it, and returns per-edge ΔΔG.

**Proposed items.** Congeneric series drawn to overlap the public FEP baselines (so results are directly comparable): a subset of the JACS-FEP targets (BACE, CDK2, JNK1, MCL1, p38, PTP1B, Thrombin, Tyk2) and/or the Merck/Schindler pharma set — **held out with leakage-controlled, time/similarity-stratified splits** relative to any training data.

**Ground-truth field.** `ddg_ref` — experimental ΔΔG (kcal/mol) per transformation.
**Scoring (proposed).** RMSE and Kendall-τ / Spearman per series vs experiment, plus the BioMate L1–L6 execution layers (did the agent select + successfully run the FEP workflow and produce valid ΔΔG outputs?). This execution-grounded layer is the differentiator over the prediction-only external FEP benchmarks.

**External baseline.** OpenFE public benchmark (59 systems, 876 ligands, >7,000 calcs); JACS-FEP / "FEP+" (Wang 2015, 8 targets ~200 ligands); Merck/Schindler FEP (8 pharma targets ~264 ligands). Report BioMate against these on the shared series.

**Honesty.** Free-energy calculation is compute-heavy and accuracy is modest even for mature engines (JACS/Merck RMSE ~1 kcal/mol); the benchmark grades **whether the agent can correctly select, run, and return a valid FEP result**, not a claim of beating specialized FEP engines on accuracy.

**Items.** 8 congeneric series, 264 ligands (`data.jsonl`). **Ground-truth field.** `reference` (experimental ΔΔG per ligand, kcal/mol, relative to the series reference ligand). **Attribution.** Derived from the Merck/Schindler FEP benchmark — `github.com/MCompChem/fep-benchmark` (MIT), Schindler et al., *JCIM* 2020, 60:5457; ΔΔG = Exp.ΔG(ligand) − Exp.ΔG(reference). Ligand structures live in each target's public `ligands.sdf` (referenced via `source`, not embedded). Reproduce with `build_rbfe_gold.py` (needs the MIT source cloned). **Leakage note:** congeneric-series design; for the ML-training variant, split by target (leave-target-out) to measure cross-series generalization.

**TODO to build:** (1) ~~curate the gold~~ **DONE** (8 series / 264 ligands, real experimental ΔΔG, MIT-attributed); (2) ~~`evaluation/scorers/rbfe_scorer.py`~~ **DONE** (ΔΔG RMSE/MUE + Kendall-τ/Spearman rank fidelity + within-1-kcal + composite score; CPU `--selftest` 6/6); (3) ~~`evaluation/adapters/rbfe_benchmark_adapter.py`~~ **DONE** (L1–L4 routing/prereq scored offline from agent text; L5–L6 `score_execution(task, output_dir)` calls `parse_rbfe_output` + `score_rbfe_series`; exported from `evaluation/adapters/__init__.py`; CPU `--selftest` 10/10); (4) **GATED (live Batch):** dedicated `run_rbfe_benchmark.py` that launches `openfe_rbfe` / `*_mmgbsa` on Batch, collects the output dir, and calls `score_execution` — not built speculatively; (5) add to the sweep once the runner exists.

**Adapter contract (built).** `RbfeBenchmarkAdapter` generates 24 tasks (8 series × {complete, incomplete, negative_control}). `score(task, text)` → L1–L4 composite (routing to an FEP/RBFE/MM-GBSA workflow + target echo, prereq-ask on incomplete, correct non-routing on the RNA-seq negative control). `score_execution(task, output_dir)` → the full `rbfe_scorer` metric dict + `{ran, produced_valid_ddg, coverage}`, comparing the run's parsed ΔΔG to the series' experimental `reference`. A perfect prediction yields rmse/mue 0, within 1.0, Spearman 1.0; the composite `score` can sit just below 1.0 because Kendall-τ-a deflates on tied experimental ΔΔG (documented in `rbfe_scorer`).

**Scorer contract (built):** `rbfe_scorer.score_rbfe_series(predicted, reference, within_kcal=1.0)` → `{n, rmse, mue, kendall_tau, spearman, within_frac, score}`; `score_rbfe_batch([{predicted, reference}])` aggregates. Reference ΔΔG keyed by ligand/edge id (kcal/mol). Multi-signal score (rank + accuracy), not affinity-only.
