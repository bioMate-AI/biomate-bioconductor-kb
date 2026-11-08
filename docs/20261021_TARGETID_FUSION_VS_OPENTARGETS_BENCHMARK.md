# Target-ID: does the evidence-FUSION beat OpenTargets-alone? (multi-disease contribution benchmark)

Date: 2026-10-21
Question (same rigor applied to the immune-FM base, which failed): the target-ID system fuses
OpenTargets + STRING-PPI (+ pathway/clinical) via a harmonic-sum arbiter. Its one recorded pass (P1,
melanoma) beat OpenTargets-alone by only **+0.013**. Does the FUSION *robustly* beat OpenTargets-alone
across diseases, past a permutation null? Or is "target-ID" essentially just querying OpenTargets?

## Setup (honest, reproducible)
- Benchmark: `backend/lib/galaxy/ai/target_id/benchmark_multidisease.py` (live OT + STRING; curated
  DisGeNET-derived gold `gold_targets_io/immune/infectious.json`; scored by `run_demonstration`:
  system vs each single channel vs 300-perm null; AUROC/AP/prec@k).
- Channels INDEPENDENT of the gold: `genetics_ot` (OT association, live) + `ppi_string` (STRING
  proximity to OT's top-20 hits, live). DisGeNET is NOT a channel (gold is DisGeNET-derived → circular).
- Two fusion modes: STRING **expands** the candidate universe (default) vs **corroborates** OT's own
  candidates only (fair — no PPI-neighbor dilution).

## Result — 17 IO cancers (clean regime: OT-alone strong)
| Mode | mean system AUROC | mean OT-alone AUROC | fusion > OT-alone | pass P1 |
|---|---|---|---|---|
| STRING expands | 0.707 | **0.902** | **0/17** | 0/17 |
| STRING corroborates (fair) | 0.583 | 0.610 | 3/17 | 2/17 |

**The fusion does not beat OpenTargets-alone.** Expansion actively hurts (STRING adds PPI-neighbors that
aren't targets → dilutes ranking, −0.195 mean). Corroboration-only removes the dilution but still doesn't
help on average (−0.027; the 3/17 wins are thin/noise-level). OpenTargets alone is a strong baseline
(cancer AUROC 0.76–0.97).

## Immune sample (confounded — reported for honesty, not a verdict)
Many MeSH-style gold names don't resolve to EFO; where they do (Psoriatic/Reactive Arthritis, Alopecia,
Sickle Cell), **OT-alone is itself at/below chance** vs the DisGeNET-immune gold (OT and DisGeNET disagree
for those diseases — a gold-source mismatch, not a fusion verdict).

## Honest conclusion
The target-ID system's **fusion contribution over just querying OpenTargets is not established** — the same
pattern as the immune-FM base vs PCA ([[project_immune_fm_run_state]]). The defensible, honest target-ID
product is therefore: **a well-engineered OpenTargets query + provenance + the gate/conflict/veto UX**, NOT
a claim that the multi-channel fusion beats OpenTargets. The genuinely contributing pieces to validate next
are ORTHOGONAL evidence (DepMap essentiality for oncology; the **clinical/predictive responder arm**, field
bar IMPRES 0.598) — a different capability than evidence-fusion target ranking, and the one place a real
contribution might still live. Not config-fishing: two motivated fusion modes × 17 diseases × null is enough
to call the OT+STRING fusion.

Meta-lesson (consistent across base AND system this session): rigorous, null-controlled, baseline-anchored
evaluation repeatedly shows the simple existing tool (PCA / OpenTargets) is as good as or better than the
complexity we add on top. The honest value delivered is (1) that evaluation methodology and (2) engineering/
provenance — not a model or a fusion that beats the baseline.
