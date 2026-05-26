# Unified 5-Model Regulatory LLM Eval

Scaffold for the eval described in `docs/20260521_UNIFIED_5MODEL_EVAL_PLAN.md`.
Scores 5 model variants on the held-out IND §2.6 corpus using all 9 checkers.

## Quickstart

```bash
# Dry-run — verifies wiring, no GPU, no API keys, ~2 sec
python -m evaluation.runners.multi_model_eval --dry-run

# Subset run — first 20 examples per model
ANTHROPIC_API_KEY=sk-ant-...  \
OPENAI_API_KEY=sk-...          \
GEMINI_API_KEY=AI...           \
python -m evaluation.runners.multi_model_eval --limit 20

# Full run — all 326 test examples, ~70-90 min, ~$30 API cost
ANTHROPIC_API_KEY=...  OPENAI_API_KEY=...  GEMINI_API_KEY=... \
python -m evaluation.runners.multi_model_eval

# Run only specific models
python -m evaluation.runners.multi_model_eval --models regulatory_llm_v6 qwen3_8b_base
```

## What it produces

```
evaluation/results/regulatory_llm_5model_v1/
├── regulatory_llm_v6.jsonl     # one row per example
├── qwen3_8b_base.jsonl         # critical baseline — same hardware, no LoRA
├── claude_sonnet_4_6.jsonl
├── claude_opus_4_7.jsonl
├── gpt_4o.jsonl
├── o3_mini.jsonl
├── gemini_3_5_flash.jsonl
├── gemini_2_5_pro.jsonl
└── summary.csv                 # rows=model, cols=9 checker pass rates + macro_avg
```

The numbers in `summary.csv` are what should replace the projection table at the
top of `docs/20260521_REGULATORY_LLM_COMPETITIVE_COMPARISON.md`.

## Architecture

```
held-out corpus (data/regulatory_training/tasks/splits_v6/test.jsonl)
        │
        ▼
   corpus.load_corpus() → Example records
        │
        ▼
   prompts.render(adapter.style, ex) → (system, user)
        │
        ▼
   adapter.generate(system, user) → str
        │
        ▼
   checker_suite.run_all(text, ex) → 9 CheckerResults
        │
        ▼
   JSONL row per example + summary.csv aggregation
```

### Resume + checkpoint

Each row appends to `<model>.jsonl` immediately after evaluation. If the run
crashes or you Ctrl-C, re-running picks up where it left off (by example_id).
Pass `--no-resume` to force re-eval.

### GPU memory discipline

The two local models (LoRA-equipped Qwen and base Qwen) share the same 8B
base weights but cannot be co-resident in VRAM with `device_map="auto"` on a
typical single-GPU box. The orchestrator loads them sequentially, calling
`adapter.close()` (which does `del model; torch.cuda.empty_cache()`) between
runs. **Order is deliberate**: LoRA first (HF cache cold), base Qwen second
(reuses cached weights, ~3× faster load).

### Per-provider concurrency caps

To avoid 429s:

| Provider | Concurrent requests |
|---|---|
| Anthropic | 4 |
| OpenAI | 8 |
| Google (Gemini) | 4 |
| Local | 1 (no parallelism) |

## The 9 checkers

Implemented in `checker_suite.py`. Each returns `{passed, score, detail}`:

| # | Checker | What it verifies |
|---|---|---|
| 1 | `mrsd_calc` | MRSD calc + FDA 2005 grounding signals |
| 2 | `adversity_tense` | No "well tolerated" / "no adverse effects" overclaims |
| 3 | `phase_gating` | PBPK section cites EMA criterion / within-2-fold |
| 4 | `tabulated_vs_prose` | Numbers in prompt preserved in narrative |
| 5 | `citation_accuracy` | Section-appropriate ICH guideline cited |
| 6 | `hedge_language` | No "proves" / "guarantees" / "no risk" |
| 7 | `structural` | Min length, sentence shape, no degenerate repetition |
| 8 | `numeric_ranges` | Half-life / bioavailability in plausible bounds |
| 9 | `cross_section_consistency` | Prompt compound id referenced in prose |

These are lightweight reimplementations aligned with the production checkers
referenced in the plan doc. Aligned ≠ identical — for a first measurement
pass, that's intentional (the runner is faster + has no Galaxy dependency).

## Two prompt templates — `sft_style` vs `instruction_style`

`prompts.py` picks per `adapter.style`. The Qwen variants get the SFT-trained
chat-template format (terse system, `/no_think` user prefix). The frontier
APIs get the same content plus an explicit instruction preamble listing the
output rules (citation, tense, numeric preservation, disclaimer prefix).

Documenting this asymmetry upfront so reviewers see we did not unfairly
prompt-engineer either side.

## Cost / wall-clock estimates

For the full 326-example run:

| Provider | Cost (est) | Wall-clock |
|---|---|---|
| Claude Sonnet 4.6 | ~$1.20 | ~4 min |
| Claude Opus 4.7 | ~$18 | ~12 min |
| GPT-4o | ~$1.50 | ~3 min |
| o3-mini | ~$0.90 | ~5 min |
| Gemini 3.5 Flash | ~$0.40 | ~3 min |
| Gemini 2.5 Pro | ~$3.50 | ~6 min |
| **Total API** | **~$25-30** | (run in parallel — ~12 min wall) |
| Local Qwen (v6) | $0 | ~30 min (incl 80s cold load) |
| Base Qwen | $0 | ~25 min |

Plus the citation-accuracy LLM judge (Sonnet 4.6) if you re-enable it from
`scripts/evaluate_regulatory_llm.py` — adds ~$3 + ~5 min.

End-to-end: **~70-90 min wall, ~$28-35 cost** for one full pass.

## When to re-run

- Every time `regulatory_llm_v6` is retrained (the v7 promotion pipeline)
- Before any external publication (investor deck, customer pitch) of the
  comparison numbers
- After any change to `checker_suite.py` (numbers shift if checkers tighten)
- Quarterly as a regression test against frontier model upgrades

## Known limitations of this scaffold

1. **Checker implementations are lighter than production.** Production
   uses a real LLM-judge for citation accuracy (`evaluate_regulatory_llm.py`)
   plus more granular rule sets. The numbers here will track production but
   not be byte-equal.
2. **Cross-run nondeterminism.** Temperature is 0.3, so two passes will
   differ on the margins. Run 3× and average for any number going external.
3. **API model deprecation risk.** `claude-sonnet-4-6` / `gpt-4o` / etc are
   names that drift. The orchestrator will hard-fail with a clear error
   message if a model is retired by the provider — update model strings in
   `multi_model_eval.py::_registry` when that happens.
