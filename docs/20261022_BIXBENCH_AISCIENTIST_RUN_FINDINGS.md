# BixBench (open-science AI-scientist comparison) — live run findings

**Date:** 2026-10-22
**Endpoint:** dev-public.biomate.ai (model served: `gpt-5.6-luna`), canonical fixture
`lifeifei163361@163.com`, E2E bypass token. Config override in scratchpad (not committed).
**Context:** "compare other AI scientists — open science, Biomni and others." SAB/BAB are blocked on
gated external data; **BixBench** (FutureHouse, arXiv:2503.00096) is the runnable open-science
comparator (adapter + runner + local capsule data present).

## What ran (small, reviewed, incremental — not scaled)

| Step | Scope | Result | Verdict |
|---|---|---|---|
| dry-run | 5 tasks, enumerate | tasks/verifiers/categories parse from HF | setup OK (zero cost) |
| login smoke | — | token obtained vs dev-public | auth OK |
| MCQ smoke | 5 tasks | **1/5 (10%)**, 73.6 s/q, $0.0068/q | integration OK; frame wrong for an agent |
| biomate_exec smoke | 2 tasks | **0/2**, 73.3 s/q, $0.025/q | **BLOCKED — run_code not firing** |

Published baselines (for reference): Biomni Lab 88.7% (exec), Claude Code 65.3%, GPT-4o 40.2%
(MCQ), Claude 3.5 Sonnet 45.0% (MCQ), BioMate 23.3% (MCQ, session-5).

## Root causes (from the stored raw responses, not inferred)

1. **MCQ is the wrong frame for an execution engine.** BioMate answers as an *agent* ("I processed
   your request using the available tools", "I need to flag a critical issue with the question"),
   not an MCQ letter-picker. 10% on n=5 is consistent with the noisy 23.3% baseline. Not a bug —
   closed-book MCQ simply isn't what BioMate is for.

2. **`biomate_exec` does not actually execute `run_code` in the live-chat path.** The dominant
   blocker. Evidence from the saved responses:
   - q2: BioMate emitted a ```python``` block to parse the capsule notebook, then printed
     `ANSWER: 0.031` with **no computed stdout between the code and the answer** — i.e. it wrote
     code as text and *guessed* a number (GT 1.9E-05). A real execution would surface the printed
     cell outputs.
   - q1: response was 76 chars — "I'll extract the notebook outputs and analyze the DESeq2 +
     enrichGO results." — a truncated preamble, stream ended early (no code, no answer).
   So the 0/2 reflects a **broken execution path**, not BioMate's ability to compute a DESeq2 padj.
   This is the known "agentic tools / run_code dead in live chat" issue — and it is **broader than
   Gemini** (reproduced here on `gpt-5.6-luna`).

3. **Minor: early-stream truncation** (q1, 76 chars) — the harness captured an opening chunk, not
   the final message. Secondary to (2).

## Why this stopped at a smoke (discipline win)

Scaling to all 205 BixBench tasks in `biomate_exec` would have cost ~$5 and hours of wall-clock to
measure a harness/architecture bug (run_code not firing), producing a fake "BioMate ≈ 0% vs Biomni
88.7%" that is meaningless. The 2-task smoke surfaced the blocker for ~$0.05. This is the
"review/diagnose before scaling expensive runs" rule paying off.

## What a VALID Biomni-comparable BixBench number requires (prereq, not yet done)

`run_code` must actually execute in the eval path. Options:
- make the live-chat path fire `run_code` (fix the agentic-tool firing — the general gap in
  `project_agentic_tools_gemini.md`), OR
- route `biomate_exec` through the data-plane / execution path where agentic tools DO run, then
  re-run the smoke → confirm computed stdout appears → scale to 205.

Only after run_code fires is a BioMate-vs-Biomni-Lab (88.7%) number honest. Until then, report
BioMate's execution standing as **"blocked on run_code firing in the eval path,"** not a score.

## Status of the broader AI-scientist comparison

- **Biomni**: already a RealBio comparator row (routing 0.95 / boin 0.5 / pbpk 0.0) + biomni_eval1.
- **BixBench**: integration validated; exec comparison blocked on run_code (this doc).
- **SAB / BAB**: blocked on gated external data (SAB gold behind password OneDrive + stale adapter;
  BAB source unconfirmed).
- **TxAgent / FutureHouse / STELLA**: not yet added as rows.
