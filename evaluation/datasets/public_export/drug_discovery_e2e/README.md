---
license: cc-by-4.0
---
# RealBio Benchmark — drug_discovery_e2e

*Part of **RealBio Benchmark**: real-world execution benchmarks for bioinformatics AI agents (see the suite README).*

**Task.** Given a protein structure (PDB) and ligands with experimental Kd, reproduce the affinity rank order.

**Items.** 15  ·  **Ground-truth field(s).** `['ligand_rank_order']`  ·  **Scoring.** objective (see ../score.py) — no LLM judge required.

Any system can run this benchmark and be scored on the same items. 

**Attribution.** Structures: RCSB PDB. Affinities: experimental Kd (PDBbind-derived where noted).
