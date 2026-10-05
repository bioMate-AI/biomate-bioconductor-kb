# Bioconductor method-selection — multi-LLM × harness matrix (first run)

**Date:** 2026-10-04
**Benchmark:** `evaluation/datasets/bioc_method_selection/` (24 items, 5 PASS groups; design gate
`docs/20261004_BIOC_METHOD_SELECTION_DESIGN_GATE.md`). Run via OpenRouter (`run_bioc_matrix.py`),
scored by `score.py` (top-1 + invalid-regime failure + hallucination).

## Results (frontier models; bare names vs +KB-described candidates)
| model | bare top1 | +KB top1 | KB dividend | invalid-regime | hallu (bare→kb) |
|---|---:|---:|---:|---:|---:|
| openai/gpt-5.6 | 1.000 | 1.000 | 0 | 0 | 0 → 0 |
| anthropic/claude-opus-5 | 0.958 | 0.958 | 0 | 0 | 0.042 → 0 |
| google/gemini-3.1-pro-preview | 0.958 | 1.000 | +4.2pp | 0 | 0 → 0 |
| deepseek/deepseek-v4-pro | 0.875 | 0.917 | +4.2pp | 0 | 0.083 → 0.083 |

## Interpretation (honest)
1. **Frontier LLMs already select fine-grained Bioconductor methods well from NAMES alone (0.96–1.0).**
   Unlike coarse nf-core routing (opaque pipeline names → 9B needed descriptions, +20pp), the candidate
   names here (clusterProfiler ORA/GSEA, limma, edgeR, DESeq2, MSstatsTMT/LiP/PTM, scran…) are well-known
   Bioconductor packages whose semantics a frontier model knows from pretraining. So the **KB dividend is
   small for frontier models (0 to +4.2pp)** and mainly removes hallucination (Opus 0.042→0).
2. **invalid-regime failure = 0 for every model/condition.** No model put ORA on ranked data, limma on
   counts, or a TMT method on label-free — validating both the models and that the benchmark's
   gold/discriminators are sound (the correct choice really is predictable from the stated data shape).
3. **Therefore the "KB, not the model" dividend for this task must be measured on the SMALL/on-prem model,
   not frontier.** Frontier doesn't need the KB because it already knows Bioconductor; the harness value
   shows up when the base model is weak — exactly as in routing (base 9B 0.68→0.885 with descriptions).

## Next (the real test)
Add the **base Qwen3.5-9B arm** (bare vs +KB) on this same 24-item set — serve the 9B (OpenAI-compatible
vLLM, as in the routing eval) and run the two conditions. Expected: larger bare→+KB dividend for the 9B,
and the model-invariance claim becomes "frontier knows Bioconductor; the KB lets a small on-prem model
match it." Optionally harden the benchmark with more obscure/confusable method triples so it discriminates
even strong models (current set is near-ceiling for frontier).

Raw predictions: `evaluation/datasets/bioc_method_selection/results/*.jsonl`.

## HARDENED 40-item matrix — incl. base-9B arm (the real test)
Added 16 obscure same-package variant triples (edgeR/DESeq2/fgsea/GSEA-ontology/MSnbase/scran) and the
base Qwen3.5-9B arm (served on vLLM, bare vs +KB).

| model | bare top1 | +KB top1 | KB dividend | invalid-regime bare→kb |
|---|---:|---:|---:|---:|
| openai/gpt-5.6 | 1.000 | 1.000 | 0 | 0 → 0 |
| anthropic/claude-opus-5 | 1.000 | 0.975 | −2.5pp | 0 → 0 |
| google/gemini-3.1-pro-preview | 0.975 | 1.000 | +2.5pp | 0 → 0 |
| deepseek/deepseek-v4-pro | 0.825 | 0.923 | +9.8pp | 0 → 0 |
| **base Qwen3.5-9B (on-prem)** | **0.800** | **0.950** | **+15.0pp** | **0.125 → 0** |

**Headline (honest):** the KB dividend scales inversely with model strength. Frontier models already know
these Bioconductor methods (≈0 dividend, near-ceiling even on obscure variant triples); the weaker open
model gains +9.8pp; the **small on-prem 9B gains +15pp (0.80→0.95), landing next to frontier (0.975–1.0).**
Critically, the 9B made **invalid-regime method choices on 12.5% of items without the KB** (e.g. ORA on
ranked data) and the KB drove that to **0** — so the KB is both an accuracy and a *correctness/safety* lever
for a small model. This is the Bioconductor-method-granularity analog of the routing result (9B 0.68→0.885
with descriptions) and the direct evidence that "the KB, not the model, lets a small on-prem system pick the
right Bioconductor method from scientific context." Frontier is near-ceiling, so to discriminate strong
models further the set would need even more obscure methods; the on-prem claim is already clean.
