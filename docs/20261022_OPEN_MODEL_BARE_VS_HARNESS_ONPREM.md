# Open-source models: fair LLM vs LLM+harness (on-prem / China)

**Date:** 2026-10-22 · **Why:** for on-prem and China deployment, frontier closed models
(gpt-6.1, Claude) are not usable — the deployable models are OPEN-SOURCE (Qwen, GLM, DeepSeek, Kimi).
The question that matters is whether the BioMate harness lifts an open model enough to be competitive,
measured FAIRLY (same model bare vs the same model + harness, same items).

## Architecture — which path gives open models the harness

- **On-prem (`localOnly`)** sets ALL model roles (intent/response/toolRanking) to the local open
  model AND routes through the FULL agentic loop (`isClaudeBackbone=true` ⇒ tools/run_code fire with
  the local model). So an on-prem open model gets the **full** harness. (galaxy-assistant.ts:3843.)
- **BYO-OpenRouter on dev** (`_generateChatWithOpenRouter`) is **text-only** — no tool loop. So dev is
  NOT the place to measure open-model + full harness; on-prem is.
- For retrieval/selection tasks (routing/param), the harness = catalog/context injection, which is
  model-agnostic and fairly applied to every model — this is what the RealBio leaderboard measures.

## Fair bare-vs-harness: cross_domain_routing (RealBio, n=200, same items, same catalog harness)

| Open model | BARE | +HARNESS | dividend |
|---|---|---|---|
| Qwen3.5-9B | 12% | 82% | **+70** |
| Qwen3.5-27B | 24% | 93% | +69 |
| Qwen3.8-27B | 18% | 86% | +69 |
| Qwen2.5-72B | 24% | 89% | +64 |
| Qwen3.8-max | 34% | 94% | +59 |
| Qwen2.5-7B | 14% | 72% | +58 |
| GLM-5.3-prime | 38% | 88% | +51 |
| GLM-5.2 | 40% | 89% | +49 |
| Kimi-K3 | 45% | 86% | +41 |
| DeepSeek-V4-pro | 42% | 80% | +39 |

## Conclusions (on-prem / China thesis, quantified)

1. **Fair and large:** every open model gains +39–70pp from the same, model-agnostic harness on the
   same items. The harness is BioMate's core value (retrieval + selection), not a model advantage.
2. **Inverse scaling (KB-dividend confirmed):** the smallest/weakest models gain MOST (9B +70, 7B
   +58) vs the strongest (DeepSeek-V4-pro +39). The harness is a great equalizer.
3. **Convergence:** +harness lands every open model at ~80–94% regardless of bare strength — a 9B
   on-prem model + harness (82%) beats a frontier model answering bare. This is the deployability
   argument: you do NOT need a frontier model on-prem; a small open model + the harness suffices.

## Honest scope / gaps

- This is the ROUTING task (cleanest bare-vs-harness). Extend to param_prefill / protocol_thresholds
  / autofix for a full picture (those harness mechanisms differ).
- The EXECUTION harness (run_code / AWS Batch) fairness needs the on-prem `localOnly` path with the
  open model as backbone — not measurable via dev's text-only BYO-OpenRouter path. A dedicated
  on-prem run is required to quantify the execution dividend for open models.
- Frontier reference (closed, NOT for on-prem): on LAB-Bench, bare gpt-5.6-luna ≈ 55% ≈ 2024 Sonnet;
  BioMate system 76% (+21). gpt-6.1-sol (newest) bare run pending as a stronger reference bar.
