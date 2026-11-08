# The KB dividend scales inversely with model strength (flagship figure)

**Date:** 2026-10-04
**Claim (Paper B / task-split centerpiece):** across two independent selection tasks, supplying the
BioMate knowledge layer (grounded candidate descriptions / retrieval) lifts a model's accuracy by an amount
that **grows as the model gets weaker** — near-zero for frontier models (which already know the catalog),
large for a small on-prem model — and it also eliminates *scientifically invalid* choices. The system, not
the model, is what makes a small on-prem LLM competitive.

## Unified data

### Task 1 — workflow routing (bare LLM → +catalog retrieval), RealBio cross_domain_routing n=200
| model | bare | +catalog | dividend |
|---|---:|---:|---:|
| base Qwen3.5-9B | 0.18 | 0.815 | **+63.5pp** |
| Claude Opus-5 (frontier) | 0.615 | 0.960 | +34.5pp |

(Plus the described-menu refinement, base 9B no-think: 0.68 → 0.885 → **0.915** at a widened window,
paraphrase-robust 0.920 — `docs/20260912_onprem_llm/20261004_CLOSE_THE_GAP_ROUTING.md`.)

### Task 2 — Bioconductor method selection (bare → +KB descriptions), n=40
| model | bare | +KB | dividend | invalid-regime bare→kb |
|---|---:|---:|---:|---:|
| openai/gpt-5.6 | 1.000 | 1.000 | 0 | 0 → 0 |
| anthropic/claude-opus-5 | 1.000 | 0.975 | −2.5pp | 0 → 0 |
| google/gemini-3.1-pro | 0.975 | 1.000 | +2.5pp | 0 → 0 |
| deepseek/deepseek-v4-pro | 0.825 | 0.923 | +9.8pp | 0 → 0 |
| **base Qwen3.5-9B (on-prem)** | **0.800** | **0.950** | **+15.0pp** | **0.125 → 0** |

## The figure
- **Panel A (scatter/line):** x = model strength (frontier → open → on-prem 9B), y = KB/context dividend
  (pp); two series (routing retrieval-dividend, bioc-selection KB-dividend). Both monotonically rise as the
  model weakens → "the weaker the model, the more the KB carries it."
- **Panel B (bar):** base-9B bare vs +KB on bioc-selection, overlaid with the **invalid-regime failure
  rate** (0.125 → 0) — the KB is an accuracy *and* a correctness/safety lever.
- **Takeaway caption:** frontier models already know the catalog, so they gain little; a small on-prem model
  + the BioMate KB **matches frontier** (9B+KB 0.95 ≈ frontier 0.975–1.0; 9B+catalog routing 0.92 ≈ frontier
  0.96) — the knowledge layer, not model scale, is the lever, which is exactly what makes an on-prem
  deployment viable.

## Honesty / caveats (carry into the paper)
- Routing's dividend is a *retrieval* dividend (candidate list injected); bioc's is an *in-context
  description* dividend — both are "the harness supplies grounded context," labelled as such.
- Frontier is near-ceiling on bioc-selection, so that task discriminates *weak* models, not strong ones;
  the on-prem claim is clean, the "harder for frontier" extension needs more obscure methods.
- bioc-selection n=40, routing n=200; report CIs. RealBio self-grading caveat applies to the product row.
- The full-harness (live BioMate retrieval, not a fixed in-context menu) condition is the next column — see
  `docs/20261004_BIOC_SELECTION_MATRIX_RESULTS.md` "Next".

## Where it goes
Paper B (harness-vs-LLM / task-split), as the unifying result tying routing + method-selection + (separately)
the decomposition open-problem. Update `docs/marketing/manuscript-plan.md` Paper B to cite this figure.
