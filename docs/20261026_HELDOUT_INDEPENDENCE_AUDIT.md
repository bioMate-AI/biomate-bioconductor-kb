# Held-out independence audit (committee blocker #3)

**Date:** 2026-10-26. The committee flagged that the semantic scorer, the organism→genome rule layer, and the
3 workflow-description fixes were changed AFTER examining errors on the original items — so their gains are
dev-set. This audit tests whether they **generalize** to a fresh held-out set
(`evaluation/datasets/public_export/heldout_independence/`, authored without reusing any tuned item).

## Part 1 — deterministic fixes (rule layer + semantic scorer): DONE, POSITIVE, FREE (no LLM)
`check_independence.py` runs the ACTUAL production `_rule_based_param_inference` + `_validate_extracted_params`
+ the semantic scorer on 20 held-out param items grouped by which fix each probes:

| probe class | held-out result |
|---|---|
| assembly alias (hg19→GRCh37, mm10→GRCm38, hg38) | **3/3** |
| organism→genome (new human/mouse/rat phrasings), strandedness kits (TruSeq/NEBNext/SMART-seq/dUTP), booleans | **11/12** |
| IO guardrail (new input/accession hallucination traps) | **0 must_not_fill violations** |
| **generalization (covered classes)** | **15/17 = 88%, zero hallucinations** |
| honest boundary (pig Sscrofa11.1, chicken GRCg7b — uncovered organisms) | rule **correctly ABSTAINED** (did not hallucinate a wrong genome) → falls to the LLM |

**Conclusion:** the deterministic post-hoc changes are NOT overfit to the dev items — they generalize to new
instances of the same classes, and fail safe (abstain, no hallucination) on out-of-coverage organisms. This
is the rebuttal the committee asked for, and it cost no API.

## Part 2 — description fix + routing (LLM bare-vs-harness): BILLABLE FOLLOW-UP
`routing_heldout.jsonl` (15 new items) probes the scnanoseq/scrnaseq/mhcquant description fix on NEW phrasings
(10x↔Nanopore, DIA↔LFQ, Comet→mhcquant) + underscore scorer cases + domain breadth. Measuring whether the
description fix generalizes requires an LLM bare-vs-harness run on the held-out menu — a bounded OpenRouter
spend, held for approval (same pattern as the roster re-run).

## Status vs committee blocker #3
Deterministic half (the sharper integrity concern — scorer + rule layer) is **closed, positive**. The
LLM/description half is authored and ready; its eval is the billable next step.

## Part 2 result — description/harness generalization (2026-10-26, corrected)
Two runs (the first exposed a construction error in this audit, recorded for honesty):
- **Mis-specified run (INCONCLUSIVE):** menu built from only the ~12 held-out golds → bare is an easy 12-way
  pick; dividend flat/negative (qwen 0.867→0.600, gemini/opus flat). This does NOT match the main benchmark's
  conditions and is not evidence either way — my error.
- **Corrected run (matches main conditions: bare = NO list / +harness = full 63-workflow described catalog):**
  the harness dividend **reproduces on held-out queries**, with the same inverse-scaling pattern:
  | model | bare | +harness | dividend |
  |---|---|---|---|
  | qwen3.5-9b (on-prem) | 0.133 | 0.933 | **+0.800** |
  | gemini-3.1-pro | 0.667 | 1.000 | +0.333 |
  | opus-5 | 0.800 | 0.933 | +0.133 |

**Conclusion (blocker #3 CLOSED, positive, both halves):** the deterministic fixes generalize (88%, 0
hallucinations) AND the harness dividend generalizes to unseen queries (+0.80 on the on-prem 9B, down to +0.13
for the frontier) — consistent with the main benchmark. The gains are not dev-set overfit. (Lesson: a held-out
routing test must use the full-catalog menu, not just the held-out golds, or bare is trivially easy.)
