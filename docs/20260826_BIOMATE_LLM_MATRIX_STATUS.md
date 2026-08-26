# BioMate×LLM Matrix — Status & Procedure (Suppl. S5.4 upgrade)

**Date:** 2026-08-26 · **Owner:** Y. Zhang · **Depends on:** `resolve_model` refactor (PR #170, deployed to dev).

## Status: mechanism VERIFIED, sweep GATED on a configured backend

The `resolve_model(role)` refactor makes BioMate's backend model settable by one env var, `BIOMATE_MODEL`
(per-role: `BIOMATE_MODEL_<ROLE>`). This unblocks the BioMate×LLM matrix. **Verified end-to-end** on the
deployed code (fresh-process invocations of the merged `model_resolver`):

| Condition | `resolve_model('response')` |
|---|---|
| default (no env) | `claude-sonnet-4-5` |
| `BIOMATE_MODEL=gpt-5.6` | `gpt-5.6` |
| `BIOMATE_MODEL_RESPONSE=gemini-3.1-pro` | `gemini-3.1-pro` |
| `user_overrides={'model': …}` (BYOK) | wins over all |

The deploy itself is confirmed: the sync's health gate + smoke tests passed, i.e. the Galaxy backend
loaded all 18 migrated modules + `model_resolver` **without crash-looping** (a bad import would have
crash-looped and auto-rolled-back).

## Why the sweep is not run here

Running BioMate *through* each model requires the **backend** to see the new `BIOMATE_MODEL` and reload.
Neither path is clean right now:
- **Dev** — an env change on the dev container is a direct dev modification (forbidden ad-hoc: SSM is
  read-only; sync-or-nothing). It must go through the sanctioned deploy/config path.
- **Local in-process** — env incomplete here: `google.generativeai` missing, `ANTHROPIC_API_KEY` unset,
  and the BiomniEval1 adapter routes generation through the backend client.

**S5.4 does not wait on this** — it is already grounded in real cross-model data (`multitask_crossjudge`).
The matrix would *upgrade* S5.4 from that proxy to BioMate-specific BiomniEval1 numbers.

## Procedure (one command, when a backend is available)

Runner: `evaluation/runners/run_biomate_llm_matrix.py`. It sweeps `--models`, runs a D3 benchmark
through the BioMate pipeline per model, and writes `results/biomate_llm_matrix/<benchmark>.csv`
(model · n · accuracy · CI · median/max latency) — paste-ready for S5.4.

- **Sanctioned dev arm** (backend already set to one model via the proper config path):
  `BIOMATE_BASE_URL=https://dev-public.biomate.ai python3 runners/run_biomate_llm_matrix.py --models <M> --no-restart`
- **Local sweep** (after `pip install google-generativeai`, export `ANTHROPIC_API_KEY`, bring up the backend):
  `BIOMATE_BASE_URL=http://localhost:5000 python3 runners/run_biomate_llm_matrix.py --models claude-sonnet-4-5 gpt-5.6 gemini-3.1-pro-preview --n 30`

**Expected result** (the point of the matrix): engine-free tasks flat across models (the S5.2 invariance,
no model call); BiomniEval1 (D3) varies with the backend model (the S5.4 dependence) — quantifying the
"floor under a mid-tier generator" claim with BioMate's own numbers.

## Also gated the same way
- **LitQA2 recall verification** (PR #169) — needs the retrieval stack running to re-score recall
  before/after (target recall ≥50% AND confabulation ~0, measured together).
