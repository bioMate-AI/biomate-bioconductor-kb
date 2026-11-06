# Target-ID deck data (for Claude Design)

**Date:** 2026-10-25. **For:** Claude Design — one disease → ranked-targets result to fill the
target-id screens. **The targets, ranks, and marketed-drug precedents are REAL** (from the
cross-disease scorecard `docs/20260727_CROSS_DISEASE_TARGET_SCORECARD.md`, live Open Targets GraphQL
v4 run, 8 autoimmune diseases, 25 targets each). The per-channel z-scores and the exact fused scores
are **illustrative** (consistent with the real output schema `target_id/types.py`). Shown as a demo
result, swappable for a live run.

Output schema per target (real): `rank`, `target`, `score`, `tier` (corroborated ≥2 strong channels /
nominated ≥1 / none / vetoed), `fired_channels`, `per_channel_z` — every value traces to its channel.

---

## Result — disease → ranked targets (psoriasis, MONDO_0005083)

**Input:** "Find drug targets for psoriasis." → three evidence channels run in parallel
(**genetics** = Open Targets association · **network** = STRING PPI / pathway proximity to known
disease genes · **LLM-reasoned** = frontier-model target evidence) → fused by the Open Targets
harmonic-sum arbiter → ranked, each target carrying its evidence.

| rank | target | score | tier | channels that fired (per-channel evidence) | real precedent (why it's believable) | → modality |
|---|---|---|---|---|---|---|
| 1 | **IL12B** | 0.94 | corroborated | genetics 0.91 · network 0.78 · LLM 0.88 | IL-12/23 p40 — ustekinumab | antibody |
| 2 | **TYK2** | 0.89 | corroborated | genetics 0.74 · LLM 0.85 · network 0.69 | TYK2 — **deucravacitinib** (allosteric) | small molecule |
| 3 | **IL17A** | 0.86 | corroborated | genetics 0.82 · LLM 0.80 | secukinumab / ixekizumab | antibody · (cyclic-peptide option → peptide loop) |
| 4 | **TNF** | 0.82 | corroborated | genetics 0.70 · network 0.72 · LLM 0.77 | adalimumab / infliximab | antibody |
| 5 | **IL23A** | 0.79 | nominated | genetics 0.76 · LLM 0.58 | risankizumab / guselkumab | antibody |
| 6 | **IL17F** | 0.74 | nominated | genetics 0.61 · LLM 0.63 | bimekizumab (dual A/F) | antibody |

Pan-autoimmune hubs to surface as a cross-disease signal (real): **IL12B** and **TYK2** both recur in
the top-10 of **4/8** autoimmune diseases — the shared IL-12/23 → TYK2 signalling spine.

## What the screens show
1. **Disease in → ranked targets out**, each row expandable to its **per-channel evidence** (the three
   bars above), with a click-through to the source (Open Targets / STRING / the LLM rationale).
2. **Confidence tier** per target (corroborated = ≥2 strong channels agree; nominated = 1) — so the
   researcher can judge each.
3. **Modality routing** on the top targets (antibody / small-molecule / cyclic-peptide) — and the
   cyclic-peptide route hands off into the peptide design loop (ties the demos together).

## Honest framing (per the target-id requirement)
Frame as **evidence-grounded prioritization with transparent provenance** — the ranking rediscovers the
actual marketed targets (ustekinumab, deucravacitinib, secukinumab, adalimumab…), which is *why it's
trustworthy*. Do **not** claim "novel-target discovery by AI" or "out-ranks Open Targets." Real sources
only (Open Targets, STRING, the LLM-reasoned channel).

---
**For Design:** targets / ranks / drug precedents / the 4-of-8 hub fact = **real** (use as-is). The
per-channel z numbers and the fused score column = illustrative (correct schema/shape) — show as a demo
result. A second striking example if you want variety: **myasthenia gravis → C5 (#1, eculizumab) +
FcRn/FCGRT (#2, efgartigimod)** — the two mechanisms of the actual approved drugs.
