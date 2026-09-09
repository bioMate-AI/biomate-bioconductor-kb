# Lane Arbiter — Catalog-Resonance Routing (measured)

**Date:** 2026-09-09
**Branch:** integration/dev-test (deployed to dev-public.biomate.ai)
**Commits:** b6e9f57a2 (arbiter + copy fix), 46763a2ea (guards)

## Problem

The composer's Instant/Cloud lane preview (spec 06 §6.2) is backed by the
server arbiter `/api/route/classify` → `route_classify` → `UnifiedIntentRouter`.
That router decides Cloud (a validated pipeline runs) purely from a **fixed,
genomics-heavy keyword vocabulary**. Whole domains it has no words for —
drug-discovery/ADMET, proteomics, cryo-EM — fell through to a general intent and
mis-routed to **Instant**. A live audit caught *"screen these SMILES for hERG
liabilities and rank them"* showing **"Instant · cited answer"** on dev.

Growing the keyword list per domain is the wrong fix (brittle, endless
whack-a-mole — the same gap would reopen for the next domain).

## Approach — ask the catalog, don't curate keywords

BioMate already indexes **2,455 workflows across 39 domains** with a warm dense
BGE-cosine prefilter (`unified_workflow_search._dense_workflow_prefilter`). The
arbiter now uses that as the generalizing signal:

```
lane = cloud IF keyword_router says cloud
       ELSE instant IF the text reads as a question        (_looks_like_question)
       ELSE instant IF it's an ad-hoc file calculation      (_looks_like_adhoc_compute)
       ELSE instant IF a confident answer-only intent        (tool rec/search/literature, conf>=0.6)
       ELSE cloud IF top dense cosine >= 0.60                (catalog resonance)
       ELSE instant
```

This generalizes to every domain and **self-updates as workflows are added** —
no per-domain vocabulary. Advisory only: the composer always offers the other
lane and nothing runs until the user sends.

Also fixed the `reads as reads as …` copy doubling in `lane-preview.tsx` (the
server `why` already begins with "reads as"; the render prefixed it again).

## Measurement

New benchmark (no prior lane-accuracy test existed):
`evaluation/runners/run_lane.py` + `datasets/lane_arbitration/instant_cases.yaml`.
- **Cloud-labeled:** the 200 `cross_domain_routing` tasks (each has a
  correct_workflow → must reach Cloud).
- **Instant-labeled:** 40 questions / ad-hoc compute / adversarial task↔question
  pairs (*"what is hERG?"* vs *"screen these SMILES for hERG"*).
Run against the live dev endpoint (the resonance signal needs the warm index +
real DB, which only exist on dev).

| Metric | Baseline (keyword-only) | + Resonance | + Guards (final) |
|---|---|---|---|
| Overall accuracy | 39.1% | 95.0% | **97.1%** |
| Cloud recall | 27.2% | 98.0% | **98.0%** |
| Instant precision | 21.5% | 88.9% | **90.2%** |
| Instant recall | 97.5% | 80.0% | **92.5%** |
| Adversarial (question-guard) | 100% | 100% | **100%** |
| Over-promise (instant→cloud) | 1 | 8 | **3** |

(A follow-up one-char fix — `correlat` → `correlat\w*`, a `\b` word-boundary bug
in the ad-hoc guard that let "Compute the correlation…" slip through — drops
over-promise to 2; shipped in a later commit.)

Baseline per-domain cloud recall exposed how systemic the under-promise was:
drug_discovery 7.7%, immunology 0%, proteomics 15%, metagenomics 15%,
single_cell 35%, rna_seq 53% — i.e. **73% of real pipeline requests were being
labeled "an instant cited answer."**

The +Resonance pass raised every domain to ~100% cloud recall but introduced 8
over-promises, cleanly bucketed: 5 ad-hoc file calculations (the Instant·compute
lane) + 2 confident answer-intents (recommend-a-tool / cite-the-literature) + 1
pre-existing keyword `'run'`-substring quirk. The +Guards pass adds an
ad-hoc-compute guard (0 of 200 cloud tasks match it) and an answer-only-intent
lock, predicted to drop over-promise to ~2 while holding cloud recall at 98%.

Results JSON: `evaluation/results/lane/{baseline,after,after_guards}_20260909.json`.

## Known residuals (documented, not fixed)

- **Under-promise on task-questions** (4): runnable tasks phrased interrogatively
  ("What bacteria are present…?", "DDA vs DIA… which pipeline?") are held Instant
  by the question-guard. Loosening the guard risks the adversarial cases; left as
  a conscious trade (advisory lane, user can override to Cloud).
- **q_int_001** ("Have we run…?") → Cloud via the keyword router's `'run'`
  substring match (`_requires_workflow`), independent of resonance. Pre-existing.
- **Resonance domain read** sometimes returns `general` (the matched workflow's
  stored domain) rather than a friendly domain label — cosmetic; lane is correct.

## UI impact

None to the ability-category surfaces. Three lane classifiers exist:
`readIntent`/`DOMAIN_RULES` (client, drives the **cold-start module cards** —
already covers drug discovery), `laneForText` (client instant fallback), and
`route_classify` (server, fixed here). Only the **composer lane-preview chip**
changes — a more accurate verdict + the copy fix. Same layout, no new category,
no visual regression. The honest smell: three hand-maintained classifiers that
can disagree; the durable follow-up is to make the server arbiter authoritative
and demote the client regex lists to instant-optimistic fallbacks.
