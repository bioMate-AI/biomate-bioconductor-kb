---
license: cc-by-4.0
---
# BioMate DrugDev Benchmark — boin_benchmark (B4)

*Part of the **BioMate DrugDev Benchmark** (see the suite README). Pipeline stage: S5/6 Phase I.*

**Task.** Given a BOIN dose-escalation scenario, produce the correct MTD dose decision and safety flags; 20 scenarios.

**Status: already PUBLIC in RealBio** as `boin_benchmark` — canonical items + README at `../public_export/boin_benchmark/`. Scorer `evaluation/scorers/boin_scorer.py`. This series references the RealBio entry.

**External baseline.** TrialBench's dose-finding task is the nearest dataset proxy; **BOIN itself is a method (simulation operating-characteristics), not a shared labeled benchmark** — so a graded BOIN decision benchmark is novel. Honesty: LLMs are mediocre here (~0.27 mean).

**Attribution.** BOIN design: Liu & Yuan, JRSS-C 2015. Scenarios are original.
