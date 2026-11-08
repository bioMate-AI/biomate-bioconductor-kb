---
license: cc-by-4.0
---
# BioMate DrugDev Benchmark — target_structure_benchmark (B5)

*Part of the **BioMate DrugDev Benchmark** (see the suite README). Pipeline stage: S0 target discovery.*

**Task.** Given a target (FASTA / UniProt), predict the structure and detect the **druggable pocket** (identify the binding-site residues).

**Items.** 10 targets (× 2 query types = 20 tasks), each with `expected_pocket_residues`.
**Ground-truth field(s).** `expected_pocket_residues`.
**Scoring.** `evaluation/adapters/target_structure_adapter.py` (currently L1–L4: keyword / pocket / prerequisite). **Caveat:** a full L6 `structure_scorer.py` is specified in the design plan but not confirmed wired — verify before relying on L6 structure scoring.

**Status.** Built internally (gold `evaluation/datasets/target_structure_benchmark/cases.yaml`); **ready to export**.

**Design requirement (carried from the landscape survey).** Structure / co-folding tasks MUST use **leakage-controlled, temporal / similarity-stratified splits** — PLINDER and Runs-N-Poses show AF3/Boltz-1/Chai-1 memorize rather than generalize, so a naive-split structure benchmark overstates capability.

**External baseline.** CASP16 (added protein-ligand pose + affinity); CAMEO (continuous); PLINDER (leakage-aware); PoseBusters (pose validity).

**Attribution.** Targets and expected pockets curated from public structures; original benchmark.
