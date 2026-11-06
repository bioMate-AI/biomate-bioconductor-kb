---
license: cc-by-4.0
---
# BioMate DrugDev Benchmark — cross_stage_benchmark (N9) · **PLANNED STUB**

*Part of the **BioMate DrugDev Benchmark** (see the suite README). Track 4 (execution-grounded, cross-stage). Every external benchmark is stage-siloed; this one grades reasoning that **connects** stages.*

**Status: STUB (not yet built).**

## Task

Given a multi-stage drug-dev situation, the agent must carry a decision across stages with the right causal dependencies. Example chains:
- **hERG liability → reformulate / re-design → re-screen → re-estimate PK** (does a flagged cardiac risk correctly propagate to a design change and a revised PK expectation?).
- **Low oral bioavailability → formulation choice → revised dose → dose-escalation implication.**
- **Off-target selectivity hit → scaffold change → re-dock → re-ADMET.**

**Ground truth:** the correct downstream action(s) and the quantitative/qualitative revision each stage implies, keyed objectively (not prose). Partial credit per correctly-propagated link.

## Scoring

Per-link correctness (did the agent propagate the stage-N result into the correct stage-N+1 decision?) + end-state correctness, as a vector. Reward correct causal linkage, penalize stage-siloed answers that ignore the upstream result.

## Design requirements

- **Leakage control:** held-out chains; no overlap with training chain templates.
- **Anti-gaming:** multi-link scoring, not a single end-state metric.
- **Honesty:** this measures cross-stage *reasoning*; it is novel (no external analog) but should be positioned as reasoning quality, not a claim of beating single-stage predictors.

## TODO to build

1. Curate ~15–20 causal chains with keyed per-link ground truth, spanning common liabilities (hERG, bioavailability, selectivity, PK).
2. Add `evaluation/adapters/cross_stage_adapter.py` (per-link scoring).
3. Wire into the series `run_all.py`.
