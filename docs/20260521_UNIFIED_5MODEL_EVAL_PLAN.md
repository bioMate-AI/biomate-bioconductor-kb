# Unified 5-Model Regulatory LLM Eval — Implementation Plan

**Date:** 2026-05-21
**Status:** Plan only. Implementation deferred to a follow-up session.
**Purpose:** Replace projected numbers in `docs/20260521_REGULATORY_LLM_COMPETITIVE_COMPARISON.md` with measured ones.

This plan was scoped via a Plan agent during the 2026-05-21 IND-test session. It's actionable as a single contained body of work (~1.5 days for an engineer familiar with the codebase).

---

## Goal

A single eval runner that scores 5 model variants side-by-side on the same held-out IND §2.6 corpus using all 9 BioMate regulatory checkers:

1. **BioMate `regulatory_llm_v6`** — Qwen3-8B + LoRA, local GPU. The product.
2. **Base Qwen3-8B** — no LoRA, same hardware. The critical baseline that proves the adapter is doing real work.
3. **Claude Sonnet 4.6 + Opus 4.7** — Anthropic API. Frontier zero-shot.
4. **GPT-4o + o3-mini** — OpenAI API.
5. **Gemini 3 Flash Preview + 2.5 Pro** — Google API.

## Architecture

```
held-out IND §2.6 corpus (~100 sections, data/regulatory_training/tasks/splits_v6/test.jsonl)
        │
        ├── ModelAdapter.generate(messages) ──┐
        │   (5 adapters, uniform interface)    │
        │                                      ▼
        │                             CheckerSuite.run_all()
        │                             (9 checkers, deterministic + 1 LLM-judge)
        │                                      │
        └─────► JSONL per model + summary.csv  ▼
                                  evaluation/results/regulatory_llm_5model_v1/
```

## File layout (new)

- `evaluation/runners/multi_model_eval.py` — orchestrator / CLI
- `evaluation/runners/adapters/`
  - `local_qwen.py` — loads `regulatory_llm_v6` LoRA or base Qwen3-8B (`--no-adapter` flag)
  - `anthropic_adapter.py` — Sonnet 4.6, Opus 4.7
  - `openai_adapter.py` — GPT-4o, o3-mini
  - `gemini_adapter.py` — Gemini 3 Flash Preview, 2.5 Pro
- `evaluation/runners/checker_suite.py` — registry that imports all 9 checkers
- `evaluation/runners/corpus.py` — held-out split loader
- `evaluation/runners/prompts.py` — `sft_style` (Qwen) vs. `instruction_style` (API) templates

## Key signatures

```python
class ModelAdapter(Protocol):
    name: str
    def generate(self, messages: list[dict], max_new_tokens: int) -> str: ...
    def close(self) -> None: ...  # free GPU memory between local runs

def run_eval(adapter: ModelAdapter,
             corpus: list[Example],
             checkers: dict[str, Checker]) -> Iterator[dict]: ...
```

## Reuse — don't reimplement

| Existing | What to reuse | Location |
|---|---|---|
| Local-model load + Qwen3 generation with `enable_thinking=False` | `load_adapter`, `generate` | `scripts/evaluate_v6.py:104-175` |
| LoRA loader pattern | `_call_local_regulatory_llm` | `backend/lib/galaxy/ai/drug_discovery/ind_assembly.py:231` |
| Citation-accuracy harness (judge + governance table) | `GUIDELINE_GOVERNANCE`, `GUIDELINE_MISMATCHES`, judge prompt | `scripts/evaluate_regulatory_llm.py` |
| Held-out corpus | `test.jsonl` | `data/regulatory_training/tasks/splits_v6/` |

Generalize `load_adapter` by making `lora_path` Optional — `None` → base Qwen3-8B baseline. This is the cleanest way to get the no-LoRA comparison number.

## The 9 checkers — where each lives

| # | Checker | Implementation |
|---|---|---|
| 1 | MRSD computation | `backend/lib/galaxy/ai/drug_discovery/mrsd_verifier.py` + `scripts/evaluate_v6.py::check_mrsd` |
| 2 | Skeleton completion | `scripts/evaluate_v6.py::check_skeleton` + `scripts/generate_skeleton_sft_task.py` |
| 3 | Phase gating | `backend/lib/galaxy/ai/drug_discovery/phase_gating.py` + `check_phase_gating` |
| 4 | Tabulated summary | `backend/lib/galaxy/ai/drug_discovery/tabulated_summary.py` + `check_tabulated` |
| 5 | Adversity language | `backend/lib/galaxy/ai/drug_discovery/adversity_language.py::detect_adversity` |
| 6 | Cross-section consistency | `backend/lib/galaxy/ai/drug_discovery/cross_section_consistency.py` |
| 7 | Structural validator | `backend/lib/galaxy/ai/drug_discovery/structural_validator.py` |
| 8 | Model/sci validation (numeric ranges) | `backend/lib/galaxy/ai/drug_discovery/model_validation.py` + `checker_overrides.py` |
| 9 | Citation accuracy (LLM judge) | `scripts/evaluate_regulatory_llm.py` (rule layer + judge) |

Checkers 1-5 are already wired into `scripts/evaluate_v6.py::CHECKERS`. The runner just extends that dict with #6-9.

## Output

`evaluation/results/regulatory_llm_5model_v1/`
- `regulatory_llm_v6.jsonl`, `qwen3_8b_base.jsonl`
- `claude_sonnet_4_6.jsonl`, `claude_opus_4_7.jsonl`
- `gpt4o.jsonl`, `o3_mini.jsonl`
- `gemini_3_flash.jsonl`, `gemini_2_5_pro.jsonl`
- `summary.csv` — rows=models, cols=9 checker pass-rates + macro avg

## Cost estimate (100 sections × ~1.5k in / 1.2k out tokens, judge adds ~0.4k each)

| Model | Cost |
|---|---|
| Claude Sonnet 4.6 | ~$1.20 |
| Claude Opus 4.7 | ~$18 |
| GPT-4o | ~$1.50 |
| GPT-o3-mini | ~$0.90 |
| Gemini 3 Flash Preview | ~$0.40 |
| Gemini 2.5 Pro | ~$3.50 |
| Judge calls (Sonnet 4.6, ~900 = 9 checkers × 100) | ~$3 |
| **Total** | **~$28-35 per full pass** |

## Wall-clock (single GB10-class GPU)

- Local Qwen3-8B 4-bit NF4 generation: ~12s/section × 100 × 2 models = ~40 min
- Frontier APIs in parallel (per-provider concurrency cap): ~15 min for slowest (Opus)
- 9 checkers (mostly rules, judge async): ~10 min
- **End-to-end: ~70-80 min**, dominated by Opus + local base Qwen

## Top failure modes + mitigations

1. **GPU OOM swapping LoRA ↔ base** — load one at a time; `del model; torch.cuda.empty_cache()` in `close()`. Never co-resident. Run base Qwen first (cold cache).
2. **Frontier rate limits / 429s** — async client with `tenacity` exponential backoff, per-provider concurrency cap (Anthropic 4, OpenAI 8, Google 4), checkpoint JSONL after each example so re-runs resume.
3. **Judge inconsistency** — fix judge to Sonnet 4.6, temperature=0, seed every prompt, run each judgement 3× and take majority (already a pattern in `evaluate_regulatory_llm.py`).
4. **Qwen3 `<think>` leakage breaking regex checkers** — reuse `enable_thinking=False` + post-hoc `<think>` strip from `scripts/evaluate_v6.py:145-175`. Apply same strip to frontier outputs defensively.
5. **Prompt-format unfairness to frontier models** — SFT format ≠ natural API format. Build two prompt templates in `evaluation/runners/prompts.py`: `sft_style` for Qwen variants, `instruction_style` for API models. Document the asymmetry in the results README.
6. **o3-mini / Gemini-3-Flash refusing to emit numeric tables** — provide a 1-shot exemplar in the system prompt; treat refusal as auto-fail (do not retry silently).

## When to actually run this

Before any external publication of the comparison numbers — investor deck, customer pitch, marketing material — that cites the per-model checker pass rates. The directional claims in the current comparison doc are sound; the exact percentages are not yet measured.

Until then, the comparison doc carries the warning at the top: numbers are projections.

## Estimated effort

~1.5 engineer-days for someone familiar with the codebase. Most of the work is plumbing (4 API adapters + 9 checker imports + CLI + summary CSV writer). Real-eval execution is ~70-80 min. Total wall: ~2 days including documentation update.
