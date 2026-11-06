---
license: cc-by-4.0
---
# Clarification benchmark — interpret-or-clarify

Clarification is a first-class interaction task: for every **parameter**, **input file**, and context-dependent
**workflow branch**, an agent must either **interpret** the value (when the request determines it) or
**clarify** it (when it is genuinely ambiguous or a required value is missing) — and must be penalized for
BOTH *silently guessing wrong* (under-clarify, dangerous) AND *over-asking when it is clear* (over-clarify,
annoying).

**Why this benchmark.** The product already ships the clarification surface (intent-clarification card, param
clarification card, a clarification gate with ~15 workflow fork-points and regex resolvers that decide
fire-vs-suppress). That capability was unmeasured. This benchmark measures the *decision*, grounded in the real
fork-points: every branch item is self-checked so the "interpretable" phrasings match the deployed resolver and
the "ambiguous" phrasings do not.

## Items (`data.jsonl`, n=32, balanced 16 interpret / 16 clarify)
- **branch** (20): a workflow fork (germline↔somatic, bulk↔single-cell, DDA↔DIA, ChIP↔ATAC, …) — ambiguous
  phrasing → clarify; resolved phrasing → interpret.
- **param** (6): organism→genome, strandedness — stated/inferable → interpret; missing-required → clarify.
- **input** (6): SMILES, receptor PDB, counts matrix — provided → interpret; missing-required → clarify.

## Scoring (`score.py`)
- **decision_acc** — correct interpret-vs-clarify.
- **over_clarify** — of interpret-gold items, fraction wrongly clarified.
- **under_clarify** — of clarify-gold items, fraction wrongly interpreted (silent guess).
- **outcome** (primary) — slot fully correct = right decision AND right value/question.

Sanity: an *always-interpret* system scores under_clarify = 1.0 (dangerous); an *always-clarify* system scores
over_clarify = 1.0 (annoying); the oracle scores 1.0 / 0 / 0 / 1.0.

## Run (`run_clarification.py`)
Matched **bare** (query + slot) vs **+ clarification knowledge** (the fork's two options; the fill-only-if-stated
rule) — the deployed clarification layer's contribution.
