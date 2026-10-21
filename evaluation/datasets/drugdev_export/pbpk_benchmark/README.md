---
license: cc-by-4.0
---
# BioMate DrugDev Benchmark — pbpk_benchmark (B3)

*Part of the **BioMate DrugDev Benchmark** (see the suite README). Pipeline stage: S4 preclinical.*

**Task.** Given a compound (SMILES), dose and route, predict PK (Cmax / AUC / t½); within-2-fold of published clinical PK; 15 compounds.

**Status: already PUBLIC in RealBio** as `pbpk_benchmark` — canonical items + README at `../public_export/pbpk_benchmark/`. Scorer `evaluation/scorers/pbpk_scorer.py`. This series references the RealBio entry.

**External baseline.** **None — no external PBPK ML benchmark exists** (the field is mechanistic: Simcyp / GastroPlus / PK-Sim); this is a novel benchmark. Honesty: LLMs are near-useless here (~0.075 mean); BioMate same-item = 0.20, ties best LLM and does **not** lead — report as-is.
