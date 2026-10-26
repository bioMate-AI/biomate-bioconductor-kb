# Multi-channel publication plan — own-LLM / benchmark / harness program

**Date:** 2026-10-24 · Plan to publish this program across channels, with the **no-external-method-
disclosure** rule and an **honest framing** that matches what the evidence actually supports.

## The honest framing (what the evidence supports — and does NOT)
This session's measurements set the story (updated 2026-10-26 after the benchmark error-analysis,
`docs/20261025_BENCHMARK_ERROR_ANALYSIS_ROOTCAUSE.md`):
- **Supported, strong:** the **harness / knowledge + rule layer carries biomedical workflow automation.**
  base+harness routes at **0.90** (0.880→0.885 scorer fix→0.900 gold corrections); the open-model
  bare→+harness dividend is large and converges small open models to ~80–94% (on-prem/China story).
  NEW and even stronger: the public benchmark **under-measured** BioMate by testing the raw LLM with the
  production rule layer OFF — running the actual rule layer, **param_prefill = 0.634 → 0.843** (+21pp,
  zero retraining; rule layer 0.96-precision + IO-param guardrail). This is Paper B's thesis, now the
  honest headline: *the knowledge/harness layer is the lever, not the weights.*
- **Supported:** the **benchmarks** (RealBio, DrugDev) as objective, execution-grounded, bare-vs-harness
  evals; BixBench-exec 87.5% ≈ Biomni Lab after the run_code fix. Scorer now measures **semantic**
  correctness (genome/bool aliases, underscore≡space), not string identity — lifts every system uniformly.
- **NOT supported (do not claim):** "our fine-tuned model beats frontier." BOTH SFT attempts regressed —
  the bare-query clean SFT (routing 0.885→0.53) AND the condition-matched deployment SFT (param 0.634→0.52,
  decomp→0.0): naive routing/param SFT on a strong base+harness **intrinsically harms** (catastrophic
  forgetting). GRPO-on-binary **stalled**. The honest model line is "a small on-prem model + harness reaches
  frontier-parity on domain tasks," never "our SFT wins."
- **Methodology caveat (must honor in any roster leaderboard):** large **reasoning models** return
  `content=None`/`finish_reason=length` when `max_tokens` is consumed by thinking tokens, producing fake
  ~0 scores and ±20pp run-to-run swings. The on-prem `qwen3.5-9b` is by contrast **perfectly deterministic**
  (0.000 spread over 3 rounds, 0 empties, ~2% stable hallucination). Any published roster number must come
  from an **empties-aware harness** (budget max_tokens past thinking tokens, retry, flag empties) — else the
  reasoning-model rows are untrustworthy.

## Papers on this topic (6)
A RealBio (benchmark) · B Harness-vs-LLM (KB-dividend) · D On-prem domain LLM (consolidated) ·
E Execution-first QC-governed platform · F Source→Nextflow conversion (plan) · DrugDev-Bench.

## Disclosure split (the hard gate)
| Tier | Papers | External treatment |
|---|---|---|
| **Public-by-design** | RealBio (A), DrugDev-Bench | Full external: benchmarks describe *what is measured*, not proprietary method. Post broadly. |
| **Thesis, careful** | Harness-vs-LLM (B) | Postable as the *finding* ("knowledge layer carries automation") without the training recipe. |
| **Method — protect** | On-prem LLM (D), platform internals (E) | External = **capability framing only** (what we deliver + light tag). Full method stays internal. |

## Channel × paper matrix
| Channel | A RealBio | DrugDev-Bench | B Harness | D On-prem | E Platform |
|---|---|---|---|---|---|
| **arXiv/bioRxiv preprint** | ✅ | ✅ | ✅ (finding only) | capability-only | capability-only |
| **GitHub** (public_export / drugdev_export: data+leaderboard+MANIFEST+LICENSE) | ✅ | ✅ | — | — | — |
| **Hugging Face** (dataset + leaderboard) | ✅ | ✅ | — | — | — |
| **Project website** (webpage_design_v2, capability framing) | ✅ summary | ✅ summary | ✅ | ✅ (capability) | ✅ (capability) |
| **Blog / social** (announce) | ✅ | ✅ | ✅ | — | — |

RealBio already has a GitHub/HF-ready bundle (`evaluation/datasets/public_export/`: README, README_GITHUB, MANIFEST, LICENSE, leaderboard.csv + 5D).

## Prerequisite before posting (updated 2026-10-26 after the error-analysis)
Do NOT post the benchmark leaderboards with holes or with the instrumentation bugs now known:
1. **Re-run the whole roster through the CORRECTED harness** uniformly, as the single source of truth —
   corrected semantic scorer (landed), patched workflow descriptions (landed), gold corrections (landed),
   and an **empties-aware** request path for reasoning models (budget max_tokens past thinking tokens, retry,
   flag empties). The current leaderboard mixes provenances and the reasoning-model routing cells are
   empties-contaminated — do not publish them as-is.
2. **Relabel the param_prefill rows:** the rows shown as "BioMate 9B (base/SFT)" are the RAW LLM with the
   rule layer OFF (they under-state BioMate). Add a "BioMate on-prem (production: rule layer + 9B)" row at
   F1≈0.84 via `evaluation/runners/run_param_prefill.py` against the live backend (the canonical number).
3. Build a **DrugDev leaderboard** — DONE in honest form (`drugdev_export/leaderboard.py`, 3 adequate-n tasks;
   the 17 micro-tasks (n=2–10) need pooling, not per-task scoring).
4. Complete protocol/autofix/workflow_gen for missing models; run **proteomics_search**.
(LAB-Bench/BioAgentBench/SAB are EXTERNAL — improvement-track only, NOT published as ours.)

## New publishable finding (methodological, Paper A/B)
"The public benchmark under-measured the shipping system": testing the raw LLM bypasses BioMate's deterministic
rule layer (`_rule_based_param_inference` + `_validate_extracted_params`, wired live) and a too-strict scorer
hid correct answers — correcting both recovers +21pp on param and +2pp on routing with **zero retraining**.
This is a clean, honest contribution (how to evaluate an agentic system vs. its raw LLM) and strengthens the
KB-dividend thesis. Framing: a measurement/methodology result, not a model-training claim.

## Sequence
1. **Complete RealBio + DrugDev leaderboards** (the gap-fill sweeps) — gating for a credible benchmark post.
2. **Post the benchmarks** (arXiv + GitHub + HF) with the bare-vs-harness result front and center.
3. **Post Paper B** (harness-vs-LLM finding) alongside — the honest headline.
4. **Website/capability** pages for D/E (no method).
5. Blog/social announce.

## Constraints honored
- No-method-disclosure: method papers external = capability-only.
- No Artifact tool (never publish via it).
- Can't auto-submit to arXiv/bioRxiv (manual accounts) — this plan + the prepared bundles are the deliverable; submission is a manual step.
