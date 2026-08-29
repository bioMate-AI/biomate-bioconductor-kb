# RealBio cost estimate — derived from saved artifacts, no re-run

**Date:** 2026-08-17
**Track:** `scope` / cost — **derived, zero spend.** No benchmark runs, no LLM API calls, no EC2. Every token count below is *measured* by reconstructing the exact prompts from the saved data; prices are *public list prices*; nothing was billed.
**Why this exists:** the harness (`run_baseline.py`) saved only `{id, prediction}` — it discarded `resp.usage`. So exact billed cost is **not** recoverable. But a defensible estimate is: the input prompt is fully reconstructable from the frozen `TASKS`/`GEN` specs + the committed `data.jsonl`, and the saved prediction gives an output floor. This doc computes that.

---

## TL;DR (the honest headline)

1. **The RealBio LLM benchmark is cheap.** One full pass over all 6 scored task-modes is **~166k input + ~4.9k output tokens** per model. At current list prices that is **$0.025 (DeepSeek V4) to $0.95 (Claude Opus 5)** per model per full pass; **all priced models together ≈ $1.9 per full sweep**. Re-running the *LLM baselines* is a coffee, not a budget item.
2. **The workload is input-dominated (34 : 1).** Cost is driven almost entirely by the input prompt, which is **identical across models** — so the cost *ranking* is just the *price* ranking, not a capability difference.
3. **The real money is elsewhere and is NOT derivable here:** (a) the **agentic** systems — BioMate and Biomni — make many LLM calls + tool executions per item, so their per-item cost is far above this single-prompt floor and is not in the saved artifacts; (b) the **workflow-execution comparison** (the 16 real-pipeline use-cases in `20260817_COMPARISON_TASKLIST_REPRESENTATIVE_USECASES.md`) costs **AWS Batch compute**, not LLM tokens, and has never been run. Those two are what an instrumented run must measure.

---

## Methods — what is measured vs estimated vs unavailable

| Quantity | Status | How |
|---|---|---|
| **Input tokens / item** | **measured** | reconstructed the exact prompt each item sent (`run_baseline.py` `TASKS`/`GEN` `instr` + label list + `inp(r)`) over committed `data.jsonl`; tokens = chars/4 |
| **Output tokens** | **floor** | chars/4 of the saved `prediction`; true completions (with any reasoning/verbosity) were discarded, so this is a lower bound |
| **Per-token price** | **public list price** | provider/OpenRouter sheets ~mid-2026 (sources below); approximate, confirm live at run time |
| **True billed cost** | **unavailable** | `resp.usage` was never saved |
| **Latency** | **partially available** | present in only ~47/55 result cells from the earlier pass; not re-derived here |
| **Agentic (BioMate/Biomni) token cost** | **unavailable** | multi-call agent traces were not saved as usage; single-prompt floor does not apply |
| **Workflow-execution (16-task) cost** | **not derivable** | never run; needs an instrumented run (AWS Batch compute + agent tokens) |

Token heuristic: **chars/4**. This is the standard rough proxy; a real tokenizer would shift absolute counts ±10–20% but not the ranking or the order of magnitude.

---

## Measured token sizes (one full pass, one model)

| Task / mode | n | input tok/item | input tok total | output-floor tok total |
|---|---:|---:|---:|---:|
| routing (bare / C0) | 200 | 98 | 19,658 | 821 |
| routing (+catalog / C1) | 200 | 451 | 90,158 | 1,086 |
| autofix | 100 | 188 | 18,827 | 461 |
| protocol QC | 100 | 110 | 11,044 | 150 |
| param_prefill | 170 | 128 | 21,820 | 2,276 |
| workflow_gen | 40 | 112 | 4,480 | 126 |
| **TOTAL** | **810** | — | **165,986** | **4,920** |

**Input : output ≈ 34 : 1.** The `routing +catalog` mode dominates input (the candidate workflow list is in-context — that is the "RAG-fair" C1 condition). The prompt text is **model-independent**, so every model processes the same ~166k input tokens; only the tiny output varies.

---

## $ estimate per full pass (input-dominated formula)

`$ = 0.166 M × price_in + 0.00492 M × price_out`

| Model | $/1M in | $/1M out | **$ / full pass** | price note |
|---|---:|---:|---:|---|
| Claude Opus 5 | 5.00 | 25.00 | **$0.95** | Opus-tier list price |
| Gemini 3.1/3.2 Pro | 2.00 | 12.00 | **$0.39** | Gemini Pro tier |
| Qwen3-max | 1.40 | 4.40 | **$0.25** | ~GLM-class (approx) |
| GLM-5.2 | 1.40 | 4.40 | **$0.25** | z-ai GLM-5.2 |
| DeepSeek V4 | 0.14 | 0.28 | **$0.025** | cheapest tier |
| GPT-5.6 | — | — | *price N/A* | 5.6 price not public-verified |
| Kimi-k3 | — | — | *price N/A* | open-weight, price not verified |
| luna (gpt-5.6-luna) | — | — | *price N/A* | variant, price not public |

**Sum over the 5 priced models, one full pass each ≈ $1.9.** Even pricing the 3 unknowns at the Opus ceiling adds <$3, so a **complete 8-model re-sweep of the RealBio LLM baselines is ≲ $5.** These are floors/estimates, **not billed amounts.**

---

## The two costs this does NOT capture (where the money actually is)

1. **Agentic per-item cost (BioMate C2, Biomni).** These do not answer from a single prompt — they route, retrieve, call tools, and (BioMate) execute workflows with a QC auto-loop. Each item is many LLM calls + compute. The saved `{id, prediction}` carries none of that, so their true cost is **higher than the single-prompt floor by an unknown multiple** and is not estimable from artifacts. This is the honest reason the LLM-baseline cheapness above does **not** transfer to BioMate/Biomni.
2. **Workflow-execution comparison (the 16 real use-cases).** Running `nf-core/rnaseq`, `sarek`, cryo-EM, docking, etc. through BioMate vs Biomni vs Claude Code/Codex is **AWS Batch CPU/GPU-hours** (cryo-EM and MD are GPU; WGS is CPU-heavy) plus each agent's token cost — potentially **dollars-to-tens-of-dollars per task**, dominated by compute, not tokens. `20260817_COMPARISON_TASKLIST_REPRESENTATIVE_USECASES.md` defines *what* to run; its cost/time columns are blank precisely because only an instrumented run can fill them.

---

## What an instrumented run would add (the `instrument` step)

Add `resp.usage` capture to `run_baseline.py` (prompt_tokens, completion_tokens, and latency) and, for the agentic paths, per-call usage + AWS Batch job cost. That converts every "floor/estimate/unavailable" cell above into a measured one, and it is the only way to get the two costs in the section above. It is a small code change to the harness; the LLM-baseline re-sweep it enables is ≲ $5.

---

## Sources (public prices, ~mid-2026 — confirm live at run time)
- costgoat.com/pricing/openrouter · betonai.net OpenRouter pricing 2026 guide · pricepertoken.com · morphllm.com/llm-api
- Prices are list prices and drift; the token measurements above are the stable part of this estimate.
