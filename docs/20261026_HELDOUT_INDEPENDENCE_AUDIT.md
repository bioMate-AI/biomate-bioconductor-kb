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
