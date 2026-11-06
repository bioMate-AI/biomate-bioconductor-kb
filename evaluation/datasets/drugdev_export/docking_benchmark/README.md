---
license: cc-by-4.0
---
# BioMate DrugDev Benchmark — docking_benchmark (B2)

*Part of the **BioMate DrugDev Benchmark** (see the suite README). Pipeline stage: S1 hit discovery.*

**Task.** Given a protein and candidate ligands, rank by predicted affinity (Spearman ρ vs experimental Kd); 15 PDB systems (5 kinases / 3 GPCR / 3 protease / 2 NR / 2 other).

**Status: already PUBLIC in RealBio** as `drug_discovery_e2e` — canonical items + README live at `../public_export/drug_discovery_e2e/`. Scorer `evaluation/scorers/docking_scorer.py`. Do not fork the items; this series references the RealBio entry.

**External baseline.** PDBbind; CASF-2016; DUD-E; LIT-PCBA; PoseBusters (use leakage-controlled splits). Leaderboard reading: LLMs are good at ligand ranking (~0.69 mean).
