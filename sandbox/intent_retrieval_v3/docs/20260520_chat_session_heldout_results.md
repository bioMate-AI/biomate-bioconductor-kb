# Chat-Session Adapter Held-Out Results (n=30)

**Date:** 2026-05-20
**Eval set:** `sandbox/intent_retrieval_v3/data/chat_session_heldout_eval.yaml`
**Adapter:** `sandbox/intent_retrieval_v3/adapters/chat_session.py`

## What this measures

Unlike rerank adapters, chat_session is a DECISION adapter. The held-out test is whether decisions are correct on queries the YAML wasn't explicitly designed for — including biological terms that might collide with trigger substrings, neutral queries that should fall back to metadata, and mixed signals.

Three failure modes to count separately:
  - **false NEW** (adapter said 'new' wrongly) — high cost, loses session
  - **false RESUME** (adapter said 'resume' wrongly) — UX/privacy risk
  - **false UNCERTAIN** (adapter said 'uncertain' when stronger signal expected) — recoverable miss

## Headline

| Metric | Value |
|---|---|
| Total | 30 |
| Correct | 30/30 (100.0%) |
| **False NEW** | **0** |
| **False RESUME** | **0** |
| False UNCERTAIN | 0 |

## Expected vs actual decision distribution

| Decision | Expected | Actual |
|---|---|---|
| resume | 16 | 16 |
| new | 5 | 5 |
| uncertain | 9 | 9 |

## Failures (0)

## Interpretation

✅ **No high-cost mistakes.** The adapter never wrongly said NEW or RESUME — every miss is in the safer 'uncertain' direction. Disqualifier discipline holds across biological-term collisions and neutral queries.

