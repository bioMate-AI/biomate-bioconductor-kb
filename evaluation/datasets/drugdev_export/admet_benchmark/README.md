---
license: cc-by-4.0
---
# BioMate DrugDev Benchmark — admet_benchmark (B1)

*Part of the **BioMate DrugDev Benchmark** (see the suite README). Pipeline stage: S2 hit-to-lead.*

**Task.** Given a compound (SMILES), predict ADMET liabilities — hERG (toxic <1 µM / moderate 1–10 / safe >10), DILI, Ames mutagenicity, Rule-of-Five — and physicochemical properties. Scored over six execution layers (L1 intent → L2 routing → L3 params → L4 prerequisites → L5 execution → L6 output validity).

**Items.** 20 compounds (× 3 query types = 60 L1–L4 tasks; L5–L6 execution on 20).
**Ground-truth field(s).** `reference` (ChEMBL / PharmaBench measured).
**Scoring.** objective — `evaluation/scorers/admet_scorer.py` (`score_admet_case/_batch`; class accuracy + Spearman on IC50). No LLM judge.

**Status.** Built internally (adapter `evaluation/adapters/admet_benchmark_adapter.py`, gold `evaluation/datasets/admet_benchmark/cases.yaml`); **ready to export** into this bundle via the build step — item files not committed here yet.

**External baseline.** TDC ADMET Group; ADMET-AI (Chemprop-RDKit); PharmaBench. BioMate reports an IND ADMET-AI concordance set (n=39): hERG Acc 0.615 / DILI 0.487 / Ames 0.795 — report as-is.

**Attribution.** Measured endpoints from ChEMBL / PharmaBench / Redfern 2003 (hERG) / DILIrank / Hansen (Ames). Cases are original.
