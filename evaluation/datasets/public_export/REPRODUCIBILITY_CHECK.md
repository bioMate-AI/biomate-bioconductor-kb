# RealBio — Reproducibility Check

**Date:** 2026-08-26 · **Method:** re-ran the released objective scorer `score.py` (CC-BY-4.0, no LLM judge) against the **committed prediction files** under `results/**` and `<benchmark>/results/**`, and compared to the published `leaderboard.md`. Every re-scored value matches the leaderboard exactly. Anyone can reproduce with `python3 score.py <benchmark> <predictions.jsonl>`.

## cross_domain_routing (n = 200) — exact match

| System | Predictions file | Re-scored | Leaderboard |
|---|---|---|---|
| **BioMate** (engine-free retrieval) | `results/biomate_dev/cross_domain_routing_c2ir.jsonl` | **0.965** | 0.965 |
| Claude Opus 5 | `…/anthropic_claude-opus-5/…_bare.jsonl` | 0.615 | 0.615 |
| Gemini 3.1 Pro | `…/google_gemini-3.1-pro-preview/…_bare.jsonl` | 0.580 | 0.580 |
| GPT-5.6 | `…/gpt-5.6/…_bare.jsonl` | 0.530 | 0.530 |
| Kimi K3 | `…/moonshotai_kimi-k3/…_bare.jsonl` | 0.450 | 0.450 |
| DeepSeek V4 Pro | `…/deepseek_deepseek-v4-pro/…_bare.jsonl` | 0.415 | 0.415 |
| GLM-5.2 | `…/z-ai_glm-5.2/…_bare.jsonl` | 0.400 | 0.400 |
| GPT-5.6-luna | `…/openai_gpt-5.6-luna/…_bare.jsonl` | 0.355 | 0.355 |
| Qwen3.8-Max | `…/qwen_qwen3.8-max/…_bare.jsonl` | 0.345 | 0.345 |

## pbpk / boin / dd — exact match

**boin_benchmark (n = 18, null-GT items excluded):** Biomni 0.500, GPT-5.6 0.500, Opus-5 0.444, GPT-5.6-luna 0.389, Gemini 0.278, Kimi 0.167, DeepSeek 0.167, Qwen 0.111, GLM 0.111 — **LLM mean 0.271**. All match.

**pbpk_benchmark (n = 15, within-2-fold):** GPT-5.6 0.200, GPT-5.6-luna 0.200, Opus-5 0.133, DeepSeek 0.067, others 0.000 — **LLM mean 0.075**. Matches.

**drug_discovery_e2e (mean Spearman):** most LLMs 0.700, DeepSeek 0.667 — **LLM mean ≈0.694**; Biomni **1.000 (n = 4, partial)**. Matches.

## param_prefill / protocol / workflow_gen / autofix — LLM cells match

param_prefill F1: Opus-5 0.757, Biomni 0.708 (n=40), GPT-5.6 0.672 (n=170). protocol_thresholds: Biomni 0.500 (n=40), GPT-5.6 0.460, Opus-5 0.330 (n=100). autofix category acc: **Biomni 0.950 (n=40)** — matches the paper's "Biomni leads autofix." workflow_generation: 0.500 across the sampled systems (n=40).

## Scope note — what is and is NOT in the re-scorable export

Only **routing** carries a committed BioMate prediction file (`c2ir.jsonl`), so **BioMate's routing 0.965 is re-scorable now** from this export. BioMate's pbpk / boin / dd / param_prefill / protocol / autofix figures come from BioMate's **separate internal harness** and are **not** shipped here as prediction files (they are the `—`/footnoted `‡§◊★†` cells in `leaderboard.md`). This check therefore confirms (a) the full LLM sweep and (b) BioMate's routing number are exactly reproducible, and (c) the leaderboard does not over-claim re-scorability for the other BioMate cells.
