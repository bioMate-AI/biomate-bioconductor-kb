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

## FULL-HARNESS arm — live BioMate retrieval (dev /api/workflows/search), n=40
Unlike the bare/+KB arms (model picks from the FIXED sibling menu), this runs each query through the real
product retrieval over the full 4,209-workflow catalog (Pass-0 LLM catalog browse).

- **recall@8 (gold method in top-8 candidates): 0.825** (33/40)
- **retrieval@1 (product's single top pick == gold): 0.375** (15/40)

**Interpretation (honest + actionable).** The product **surfaces the right method 82.5% of the time but
ranks it #1 only 37.5%** — 20 of 25 @1-misses have the gold in the top-8 ("inK"). The rank-1 is frequently a
*generic/adjacent* workflow (generic "Gene Set Enrichment Analysis" instead of the specific clusterprofiler/
reactomepa/dose GSEA variant; nf-core/differentialabundance instead of bare deseq2/edger). So the live
product's weakness is **retrieval RANKING**, not candidate coverage — distinct from the SELECTION weakness
the in-context arm measured.

**The three arms compose into the product recommendation:**
1. retrieval recall is strong (0.825@8) → the right method is almost always surfaced;
2. in-context KB selection is strong (9B 0.95 given the siblings) → the model picks well when shown grounded
   descriptions;
3. but retrieval rank-1 is weak (0.375) → **the product should run the KB-grounded SELECTION step over the
   retrieved top-k (with descriptions) rather than taking retrieval's rank-1.** That is exactly the
   described-menu/widened-window mechanism already shipped for routing — apply it to method selection.
Caveats: @1 is strict (a generic-GSEA top pick is arguably acceptable for a GSEA query — recall@8 is the
fairer retrieval metric); some golds have reasonable acceptable-alts not yet encoded.

Raw: `results/full-harness_retrieval.jsonl`.

## COMPOSITE arm — retrieve → KB-grounded selection (validates the product fix), n=40
Runs the real product path: live retrieval (top-8) THEN a KB-grounded selection step over the retrieved
candidates (gpt-4.1 selector), instead of taking retrieval's rank-1.

| metric | value |
|---|---:|
| retrieval@1 (rank-1 alone) | ~0.38–0.53 (non-deterministic LLM retrieval) |
| recall@8 (gold in retrieved top-8) | 0.825 |
| **composite@1 (retrieve → KB-select)** | **0.800** |
| conditional-select (pick gold \| gold retrieved) | **0.97** |

**Conclusion — the fix is quantified.** Adding a KB-grounded selection step over the retrieved top-k roughly
DOUBLES end-to-end top-1 (≈0.38–0.53 → 0.80). When the gold method is retrieved, the selector picks it 97%
of the time (composite ≈ recall@8 × conditional-select = 0.825 × 0.97 ≈ 0.80). So **selection is essentially
solved; the remaining ceiling is retrieval RECALL (0.825), not the LLM.** Product action: route retrieved
top-k (with descriptions) through the selection step rather than surfacing retrieval rank-1; the next lever
to raise the ceiling is retrieval recall (better embeddings / candidate coverage), not a better selector.

### Four-arm summary (bioc method selection, n=40)
- bare (names, fixed siblings): 9B 0.80, frontier ~1.0
- +KB (described, fixed siblings): 9B 0.95 (+15pp), invalid-regime 0.125→0
- full-harness retrieval@1 (live, full catalog): ~0.38–0.53 (ranking-limited); recall@8 0.825
- composite (retrieve→KB-select): 0.80, conditional-select 0.97 → the right product design

## Acceptable-alts (firm up retrieval@1) — 2026-10-04
Added a principled `accept_retrieval` field (scientifically-valid alternatives that respect the correct
analysis REGIME for the stated input; e.g. a DB-agnostic GSEA tool for an un-pinned GSEA query, any NB
count-DE for a generic count-DE query, a two-color microarray tool for two-color data). Applied ONLY to the
full-catalog retrieval@1 metric — the in-context discrimination arms (bare/+KB) stay STRICT on the specific
gold so the discrimination signal is not diluted. Reporting both:

| metric | strict (gold only) | with scientifically-acceptable alts |
|---|---:|---:|
| full-harness retrieval@1 (earlier run) | 0.375 | **0.625** |

(Composite run's retrieval@1 was ~0.525 strict — LLM-retrieval is non-deterministic run-to-run.) So the
product's rank-1 is a *scientifically-valid* method ~62.5% of the time; the gap to recall@8 (0.825) is the
remaining ranking headroom. In-context arms unchanged (9B +KB 0.95, frontier ~1.0). accept_retrieval sets
are auditable per-item in `data.jsonl` + `build_dataset.py` (ACCEPT_RETRIEVAL).

## Retrieval-recall root cause + fix (2026-10-04)
**Root cause (diagnosed, file:line):** a flat **−8.0 penalty on every Bioconductor subworkflow**
(`unified_workflow_search.py:1814-1818` via `_is_component_subworkflow:175`) that generic pipelines escape
— PR #188 exempted the domain catalog but intentionally left the bioconductor subtree penalized; the
deferred per-entry pass never ran, and this benchmark is 100% bioconductor, so it was maximally exposed.
Amplified by the Pass-0 LLM prompt ("never rank a subworkflow above a pipeline"). Net swing vs a generic
rival ≈ −20 pts, dwarfing the ≤+0.5 dense bonus. (Embeddings absent locally + dense rescue hard-disabled is
a secondary gap — irrelevant until the penalty is gated.)

**Fix shipped (code):** gate the −8 bioc/biomni penalty on `_detect_pipeline_intent(query)` — penalize a
bioconductor METHOD only when the user actually wants a raw-data PIPELINE; for method-level queries (gene
list / count matrix / ranked statistic / processed object) the specific executable method is the right
answer. Keeps the −12 nf-core-internal penalty. Mirrors PR #188's exemption, extended to the bioc subtree.

**Predicted effect (verified offline before deploy, per review-before-expensive-run):** of the 40 queries,
**37 now ESCAPE the penalty**; only 3 still trip it (pr_04, h_msnb_1, h_msnb_2 — proteomics DDA/mzML queries
that also legitimately signal nf-core/proteomicslfq, already credited as accept_retrieval). Expect recall@8
→ ~0.95+ and retrieval@1 up sharply.

**Verification pending:** needs dev deploy (sync) + re-run the 40 queries — HELD for explicit go (shared-dev
deploy from a non-main worktree). Follow-up fixes ranked: #2 de-bias the Pass-0 prompt for method queries;
#3 per-entry reclassification of the bioc subtree (durable root fix); #4 rebuild embeddings + gated dense
rescue.
