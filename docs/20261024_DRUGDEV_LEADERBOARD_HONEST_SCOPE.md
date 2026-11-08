# DrugDev-Bench leaderboard — honest scope & what a credible sweep requires

**Date:** 2026-10-24 · Decision note for the multi-channel publication plan
(`docs/20261024_MULTICHANNEL_PUBLICATION_PLAN.md`, prerequisite #3: "Build a DrugDev
leaderboard"). Written after auditing what the DrugDev export actually contains.

## What exists (built this session)
`evaluation/datasets/drugdev_export/leaderboard.py` + `leaderboard.csv` + `leaderboard.md`
now aggregate the DrugDev tasks that are **adequately powered and already scored**, reusing
the same objective `../public_export/score.py` every RealBio system is graded by. Three columns,
12 models, every cell traced to a committed predictions file:

| task | metric | n | note |
|---|---|---|---|
| `pbpk_2fold` | fraction within 2-fold | 15 | universally weak (0.0–0.2) — a real PK-projection gap, consistent across all models incl. frontier |
| `boin_mtd` | MTD-selection accuracy | 20 | **BioMate 9B base = 0.778**, best of the open/small models; frontier 0.11–0.5 |
| `dd_spearman` | mean Spearman rank | 15 | clusters at 0.70 (Biomni 1.0 on its n=4 partial) |

These three were already in the RealBio board; the new file is the **standalone DrugDev view**
with per-task n shown, so the numbers are never read without their sample size.

## Why the other 17 tasks are NOT leaderboard columns (the hard call)
The remaining 17 DrugDev task groups are **decision-probes with n=2–10 items** (74 items total):

```
fep_selection 2 · qsar_benchmark 2 · retrosynthesis_benchmark 2 · target_id_benchmark 2 ·
dose_decision 3 · dose_projection 3 · dose_schedule 3 · leadopt_triage 3 · tissue_exposure 3 ·
workflow_chain 3 · special_population 4 · process_knowledge 6 · rbfe_benchmark 8 ·
target_structure_benchmark 10 · admet_benchmark 20 (scored via the separate TDC path)
```

Per the project rule against tiny-dataset LLM scoring, an **n=2 task cannot carry a credible
per-task accuracy** — a single item flips the score by 50pp, so a 17-column leaderboard built on
these would be noise presented as evidence. Publishing it would violate the honest-framing
commitment. They are therefore deliberately excluded from the scored leaderboard, not silently
dropped.

## What a credible DrugDev leaderboard expansion requires (the gated work)
Not a blind 17-task × roster sweep. The correct design, in priority order:

1. **Pool the micro-tasks into adequate-n capability categories** so each column has n≥15:
   - **PK / dosing** = dose_projection + dose_schedule + dose_decision + tissue_exposure +
     special_population + pbpk  → ~31 items
   - **Med-chem / structure** = qsar + rbfe + fep_selection + leadopt_triage +
     target_structure + target_id → ~27 items
   - **Synthesis / process** = retrosynthesis + process_knowledge + workflow_chain → ~11 items
     (still thin — hold as qualitative until more items are authored)
2. **Author more items** for the thin categories to clear n≥15 (the benchmark is under-sized,
   a real content gap — not a sweep gap).
3. **Then** run the pooled categories bare-vs-harness across the roster. At 74 items × ~12 models
   this is a **small, bounded sweep (~900 calls)**, not a GPU-scale spend — but it is only worth
   firing once the pooling + item-authoring above make the columns credible. Running it now would
   score n=2 noise.

## Status vs. the publication plan
- Prerequisite #3 ("Build a DrugDev leaderboard") is **met in its honest form**: the three
  adequately-powered tasks are now a standalone, reproducible, traced leaderboard.
- The **expansion to a full capability-category leaderboard is content-gated** (needs item
  authoring + pooling), not merely compute-gated. Documented here so it is not mistaken for a
  one-command sweep.
- RealBio's bare-vs-harness thesis (the actual publication headline) is unaffected and remains
  publish-ready.
