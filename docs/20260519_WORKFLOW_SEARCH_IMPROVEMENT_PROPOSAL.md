# Workflow-Search Improvement — Proposal & Investigation Plan

**Date:** 2026-05-19
**Status:** Proposal — investigation step (~30 min benchmark categorization) pending before any build work.
**Sandbox:** `sandbox/workflow_search_v2/` (new, mirrors `sandbox/retrieval_v2/` pattern).
**Related:** `20260518_SESSION_FINAL_RETRIEVAL_PRODUCTIZATION.md` (wrapper-level work; this proposal extends the pattern up one layer).

## Question

> "Could the workflow-level search be improved in the same way as the wrapper-level fix?"

## Honest answer

**The library pattern transfers, but the problem shape is different.**

### Similarities (pattern reuses)

- Same flow: free-text query → ranked candidates → top-1 quality matters.
- Same priority-boost concept: user types "RNA-seq" → workflows in that family (`nf-core/rnaseq`, `nf-core/scrnaseq`, `nf-core/differentialabundance`) should outrank unrelated ones (`nf-core/atacseq`).
- Same data-not-schema lesson: a curated YAML beats schema migration.

### Differences (why a drop-in wouldn't work)

| Dimension | Wrapper layer (just shipped) | Workflow layer |
|---|---|---|
| Catalog size | 12,274 noisy rows | ~30 nf-core + ~10 biomate ≈ 40 canonical |
| Duplicates | Yes — 5 DESeq2 wrappers from different authors | No — `nf-core/rnaseq` IS the canonical name |
| Failure mode | "Right family buried under noise" | "Adjacent workflow chosen" (rnaseq vs scrnaseq, sarek vs raredisease) |
| Retrieval stack | FTS5 BM25 only | FTS + BGE dense + chain search + LLM verification |
| Existing UX | None | Disambiguation card already fires when top-2 gap < 3.0 |
| Existing benchmark | We built a 40-query set | 155-case `cross_domain_routing/queries.yaml` (≈80% baseline per memory) |

So the workflow stack is **already much more sophisticated than the wrapper stack was**. The headroom is smaller, and failures aren't ranking noise — they're semantic adjacency.

## Three candidate levers (in priority order)

### Lever 1 — Intent-anchor canonical map (highest leverage *if* failures match)

A curated YAML codifying intent→workflow expertise:

```yaml
bulk_rnaseq:
  workflow: nf-core/rnaseq
  trigger_terms: [rna-seq, bulk rna, fastq to counts, gene expression]
  disqualified: [nf-core/scrnaseq, nf-core/smrnaseq]

single_cell:
  workflow: nf-core/scrnaseq
  trigger_terms: [single-cell, scrnaseq, 10x, cell ranger, starsolo]

variant_germline:
  workflow: nf-core/sarek
  trigger_terms: [variant calling, germline, gatk haplotypecaller, snv calling]
  disqualified_intent: [somatic]

variant_somatic:
  workflow: nf-core/sarek
  workflow_mode: somatic
  trigger_terms: [somatic mutations, tumor vs normal, mutect2]

rare_disease:
  workflow: nf-core/raredisease
  trigger_terms: [trio analysis, rare disease, scout, mendelian]
  disqualifies: [nf-core/sarek]  # raredisease is the right choice when trio context present
```

Then a library function `prioritize_workflow_by_intent(query, candidates)` that:
1. Scans the query for `trigger_terms` matches.
2. If a clear match (one intent fires with high confidence), boost its `workflow` to position 1 of the candidate list.
3. If multiple intents fire (genuine ambiguity), pass through unchanged so the disambiguation card UX handles it.
4. Honor `disqualified` and `disqualifies` lists to suppress wrong adjacent picks.

**This codifies the routing-prompt knowledge as data** instead of growing the inline LLM rules in `galaxy-assistant.ts` per the existing `routing_prompt_optimization` note in memory.

### Lever 2 — Domain-gated context injection (mentioned in memory as deferred)

Today the routing prompt cargo-cults all routing rules into every LLM call. Instead: detect the domain (RNA, variants, metagenomics, proteomics, ...) from the query, then inject only the 3-4 rules relevant to that domain.

**Library shape:** reuse `_infer_target_family()` pattern from `family_dedup.py` — same predictive logic over a smaller, domain-level alias map. Drops the LLM verification prompt size by 60-80% and reduces irrelevant-rule distraction.

### Lever 3 — Tighter disambiguation gate

Today the gate fires whenever `top-2 score gap < 3.0`. Some of those are easy wins where one candidate is *clearly* canonical for the query (per Lever 1's intent-anchor map) and the user doesn't need to be interrupted. Use the intent-anchor lookup to skip the card when there's a confident canonical match.

**Risk:** over-suppressing the card could hide legitimate ambiguity. Mitigation: only skip when the matched intent has high `trigger_terms` density AND no competing intent has matches.

## What's NOT proposed

- ❌ A workflow-level alias/dedup mapping. Workflows are already canonical names; no fragments to merge.
- ❌ Replacing FTS or BGE or chain search. Those are working; the proposal adds a thin priority layer on top.
- ❌ Touching `UnifiedWorkflowSearch` or `ai_assistant.py` directly in any first PR. All work lives in `sandbox/workflow_search_v2/` until the lift is measured.

## The investigation step before building anything

Run the existing 155-case benchmark **now** and categorize failures:

| Failure category | If majority of failures match | Right lever |
|---|---|---|
| Wrong adjacent workflow chosen (rnaseq when user meant scrnaseq) | → 1 | Intent-anchor map (~3 hr to build + measure) |
| Disambiguation card fires too often on clear cases | → 3 | Tighter gate + canonical priority (~2 hr) |
| LLM picked wrong even with right candidates in top-3 | → 2 (or none) | Prompt engineering, not retrieval |
| Right candidate not in top-10 at all | → none | Retrieval-engine issue (BGE, FTS); out of scope here |

**~30 minutes of investigation tells us which lever to pull.** Building a workflow alias map blind, without knowing the failure mix, is exactly the trap the audit doc flagged.

## Validation plan (once a lever is picked)

1. Build the lever-specific YAML and library function under `sandbox/workflow_search_v2/`.
2. Re-run the 155-case benchmark (IR mode against the existing search stack + the new library function).
3. Compare top-1 / top-3 / mean-disambiguation-fire-rate before-vs-after.
4. Only if top-1 lifts ≥ 5pp without raising disambiguation false-positives, propose production wiring behind `BIOMATE_WORKFLOW_INTENT_PRIORITIZE=1` env flag.

## Sandbox structure

```
sandbox/workflow_search_v2/
  data/             # intent_anchors.yaml (built when Lever 1 picked)
  scripts/          # measure_workflow_routing.py (155-case A/B harness)
  docs/             # findings from each investigation step
```

Mirrors `sandbox/retrieval_v2/` pattern — nothing in here imported by production until validated. The 155-case benchmark + the canonical-rerank approach in `family_dedup.py` are both reusable; the workflow-level library would be a parallel module, not a modification of the wrapper-level one.

## Why this is conservative (vs my earlier session)

In the wrapper-level work I made architectural proposals before measuring (proposing the canonical-tools DB schema before knowing the dedup compression ratio). The measurement showed only 1.43× compression — much less than I claimed — and the real lever turned out to be the alias map, not the schema. Same risk applies here: proposing an intent-anchor map before seeing the 155-case failure distribution would repeat that mistake.

**Investigation first. Lever choice after.** That's the cheap insurance.

## What's awaiting user decision

1. Proceed with the **~30 min investigation step** (run the 155-case benchmark, categorize failures, return with a concrete recommended lever)?
2. Or hold here while the user reviews this proposal?

The investigation is read-only against the existing search stack (no production touches), result is a sandbox doc with the failure categorization. Lever build happens only after that report.
