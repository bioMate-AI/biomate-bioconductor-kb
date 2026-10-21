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

**TODO to build:** (1) curate the congeneric-series gold with leakage-aware splits — real experimental ΔΔG from the public FEP sets (Merck/Schindler `github.com/MCompChem/fep-benchmark` CC-BY; JACS-FEP; OpenFF Protein-Ligand Benchmark); **do not invent ΔΔG values**; (2) ~~`evaluation/scorers/rbfe_scorer.py`~~ **DONE** (ΔΔG RMSE/MUE + Kendall-τ/Spearman rank fidelity + within-1-kcal + composite score; CPU `--selftest` 6/6); (3) add `evaluation/adapters/rbfe_benchmark_adapter.py` (L1–L6, calls `parse_rbfe_output` + `score_rbfe_series`); (4) export items here; (5) add to the sweep.

**Scorer contract (built):** `rbfe_scorer.score_rbfe_series(predicted, reference, within_kcal=1.0)` → `{n, rmse, mue, kendall_tau, spearman, within_frac, score}`; `score_rbfe_batch([{predicted, reference}])` aggregates. Reference ΔΔG keyed by ligand/edge id (kcal/mol). Multi-signal score (rank + accuracy), not affinity-only.
