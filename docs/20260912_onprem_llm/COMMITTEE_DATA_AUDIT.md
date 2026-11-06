# Committee DATA Audit — data_pool_v2 (2026-09-22)

**gpt-5.6 + gemini-3.8-flash + Claude, on the rebuilt pools (graph anchors + committee distillation +
self-mining) with real samples + agreement stats. Both external members converged.** Raw:
`committee_reviews/data_audit_{openai,gemini}.md`.

## Verdict (unanimous): DO NOT train on data_pool_v2 as-is
The pool is **recoverable and potentially strong**, but currently suffers **"label-space schizophrenia"**
— three incompatible target representations for the same concepts: (1) free-form teacher *concepts*,
(2) arbitrary DB *slugs*, (3) web-app *plumbing* from mined commits. Training on it flat → the model
emits concepts when slugs are required, invalid param JSON, and web-API patches when a Nextflow pipeline
crashes. **The audit-before-train gate just prevented a wasted retrain.**

## The core issue = supervision-contract mismatch (my prelim diagnosis, confirmed + extended)
Committee distillation's low DB-gold agreement (0.27) is **~90% a grounding-context bug, not weak
teachers**: teachers were asked to "name the workflow" with **no candidate list / schema**, so they gave
`GSEA`/`PCA` (correct concept, wrong string) instead of `clusterprofiler_gene_set_enrichment_analysis`.
The 0.27 measures *string collision*, not correctness. BUT low teacher-teacher consensus (0.30–0.49)
still flags genuine query ambiguity + the single-slug gold fallacy.

## Findings + fixes by source
**Committee distillation (P0 — quarantine + regenerate):** unusable as hard targets for routing/param/
wfgen (concept-level, not catalog/schema-level). **Fix: rerun teachers the way BioMate runs** —
retrieval top-k candidates + the workflow's JSON schema in-prompt, constrained decoding to valid
slugs/schema-keys, allow `NO_MATCH`/clarify; measure candidate-recall separately from selection.
Salvage current output only as **query-paraphrase augmentation** (concept→slug map) + a coarse autofix
symptom taxonomy. Consensus flag = triage, not truth.

**Gold validity (P0):** "one DB slug = only correct answer" is invalid (GSEA≡clusterProfiler≡fgsea for a
ranked list; topGO is not). **Routing gold = query-conditional accept-sets** (preferred/acceptable/
clarify/incompatible) via functional equivalence classes `(input_types, core_op, output_types)`; score
Precision@1∈accept-set + recall@k, not exact-slug. **Param gold = schema-valid typed JSON instance**
with status tags (explicit/normalized/inferred/defaulted/unspecified); defaults ≠ extraction labels;
strip env constants (threads/memory/outdir).

**Self-mining (P0 — purge noise):** the commit-fix sample ("Export-to-CRO button → wire REST endpoint")
is **React/API plumbing, not pipeline logic** — if mixed into autofix, the model suggests web patches
when DESeq2 fails to converge. Docs-QA ("how many workflows implement params.mock_mode") is DevOps
meta-QA, not user-facing bioinformatics. **Fix: execution-boundary filter** — keep only commits/docs
touching `*.nf/*.wdl/*.smk/*.cwl/*.sh/*.R/*.py` execution code + real execution errors (exit codes,
runtime exceptions, tool-syntax); purge frontend/API/CI/meta. Require provenance (commit hash, file:line,
recomputed counts, temporal validity) — docs-QA is snapshot-dependent → retrieval-grounded only.

**Graph anchors (P1 — validate):** deterministic ≠ clean. Decompose gold is a *linear UI-label list*, not
a typed DAG → **run a DAG-compilation test** (edges = real I/O deps); map UI labels → actual tool nodes;
validate param enums/defaults vs runtime schema; 902 param anchors leave big coverage gaps → measure
coverage; the subworkflow extraction miss (found 1) needs fixing.

**Leakage (P0 — rebuild split):** prefix-family hash is insufficient (modular pipelines share 80% DAG
across prefixes; paraphrase queries leak). **Fix: tool-set Jaccard + graph-edit clustering (Louvain),
partition whole clusters; semantic query dedup (cos<0.85);** eval tracks = In-Distribution (5%),
Cold-family/OOD (10%), + temporal + adversarial-constraint. Human-adjudicated test set fully isolated.

## Top 3 fixes BEFORE training (both members)
1. **Rerun committee distillation grounded** — retrieval candidates + JSON-schema in-prompt, constrained
   decoding; quarantine current free-form output (salvage as paraphrase aug only).
2. **Purge web-dev/maintenance noise from self-mining** — execution-boundary file+error whitelist.
3. **Rebuild splits via tool-graph Jaccard clustering + semantic dedup** — deprecate prefix-hash;
   warm/cold-family/temporal tracks.
Plus: redefine routing→accept-sets and param→schema-valid-JSON contracts + structural validators; 100%
schema-valid + near-100% DAG-valid release gates; per-source/per-task weights (don't flatten tiers).

## Bottom line
The three-source strategy is right, and self-mining + graph anchors are the strongest parts — but the
**label contracts, teacher grounding, noise filtering, and split** must be fixed first. Same lesson as
the eval saga: get the *contract and measurement* right before scaling. Net raw pool ~16.8k+ examples,
but a large fraction needs regeneration/filtering before it's trainable.

---

## Fixes APPLIED + results (2026-09-22)
All three fixes executed (API/DB-only, no GPU):

- **Fix 3 — Jaccard-clustered split** (`build_jaccard_split.py`): 4,172 wf → 3,955 tool-clusters;
  train 3,547 / eval 625 (family-disjoint, whole-cluster). Deprecates prefix-hash.
- **Fix 2 — execution-boundary filter** (`fix_selfmining_filter.py`): commit-fixes **0/377 kept** —
  the entire mined commit source is app-dev (web/API/CI) noise, NOT pipeline logic → autofix training
  = the DB's 1,719 real `real_exec_err`, exactly as TRAINING_DATA_SOURCES warned. docs-QA 1,812/1,996 kept.
- **Fix 1 — grounded re-distillation** (`build_committee_grounded.py`): teachers rerun the way BioMate
  runs (retrieval candidates + schema). RESULTS confirm the diagnosis:
  - routing: raw ungrounded agreement 0.27 → **grounded selection-given-recall 0.83**
    (candidate_recall@20 0.81; overall exact 0.67). Retrieval, not teacher selection, is the bottleneck.
  - param: free-form → **0.95 schema-valid** keys.

**Net:** the pool is now trainable — real graph anchors (14.4k) + grounded/usable teacher distillation
(routing 0.83 selection, param 0.95 schema-valid) + cleaned self-mining (1,812 QA) + family-disjoint
split + corrected gold contracts (routing accept-sets, param schema-JSON). The committee-audit→fix cycle
worked: the 0.27 "teacher quality problem" was a grounding bug, now fixed.
