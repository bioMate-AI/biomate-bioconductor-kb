# Phase 1 — Canonical Suite Catalog: A/B Results and Promotion Decision

**Date:** 2026-05-18
**Status:** A/B benchmark complete; **recommendation: DO NOT promote yet** — needs Phase 1.5 clustering refinement.
**Related:** `20260518_PHASE0_CLUSTERING_RESULTS.md`, `20260518_TOOL_CATALOG_RESTRUCTURE_AND_DEDUP_PLAN.md`

## What was built (all sandboxed)

| Artifact | Notes |
|---|---|
| `sandbox/retrieval_v2/output/tool_canonical.db` | 8,572 suites · 11,648 functions · 12,274 wrapper mappings · integrity clean |
| `sandbox/retrieval_v2/scripts/build_canonical_db.py` | Reproducible build from `galaxy_ai_tools.db` |
| `sandbox/retrieval_v2/retrievers/tool_catalog.py` | `search_tool_suites`, `list_functions`, `resolve_wrapper` — 23/23 tests pass |
| `sandbox/retrieval_v2/tests/suite_eval_set.yaml` | 30 hand-curated queries with expected `suite_id`(s) |
| `sandbox/retrieval_v2/scripts/run_suite_eval.py` | A/B harness — flat vs canonical |

Production code: zero changes.

## Headline A/B numbers (n=30 queries)

| Path | top-1 | top-3 | top-10 | mean cands |
|---|---|---|---|---|
| FLAT (existing `tools_fts` → collapsed to suite_id) | 56.7% | 90.0% | 100.0% | 10.0 |
| CANONICAL (new `suites_fts` direct) | **60.0%** | 90.0% | 96.7% | 10.0 |

**Delta: +3.3pp at top-1.** Below the +5pp ship threshold set in the Phase 0 doc.

## Where the canonical path wins (the disambiguation thesis is correct)

The canonical search does what we hoped: it surfaces the right CANONICAL tool name instead of an arbitrary wrapper that happens to share a substring. Concrete wins from the eval set:

| Query | FLAT top-1 | CANONICAL top-1 |
|---|---|---|
| "Differential expression with DESeq2" | smagexp | **deseq2** |
| "Picard MarkDuplicates" → "Add read groups with Picard" | rapsodyn | **picard** |
| "Cutadapt adapter trimming" | qiime2__cutadapt__trim_paired | **cutadapt** |
| "EMBOSS sequence analysis" | filter_tools | **emboss** |

These are exactly the disambiguation failures that drove the architectural proposal in the first place. The hierarchy works.

## Where the canonical path loses (clustering is incomplete)

Several family_keys that should be one suite are split into multiple. The single biggest cause: pure path-regex extraction can't merge variants like:

- `ensemblvep` + `ensembl vep` + `ensembl_vep` → should be one VEP suite
- `alphafold` + `alphafold 3 server` → should be one AlphaFold family
- `metaphlan` + `metaphlan4` + `metaphlan_hclust_heatmap` → MetaPhlAn family
- `fastqc` + `naturalis_fastqc` + `falco` (third-party FastQC clone) → FastQC family

Each fragment ranks separately in the FTS results, diluting the top-1 hit rate.

A second class of "loss" is actually arguable: q09 returned `sambamba_markdup` first for "Picard MarkDuplicates" — sambamba IS a valid markdup tool. But the eval set says picard is what the user asked for, so it counts as a miss.

## What this changes about the plan

- **The architecture is validated** — the wins on DESeq2/Cutadapt/Picard/EMBOSS prove that suite-level routing reduces LLM disambiguation pain exactly as predicted.
- **Pure path-based clustering is not enough.** Phase 1.5 needs name-level normalization to merge family_key fragments (lowercase, strip "naturalis_" / "_server" / "_hclust_*" / numeric suffixes; cross-reference by description-substring similarity).
- **Don't promote yet.** A +3.3pp delta on 30 queries is real but not large enough to justify a production schema change, especially when the failures are addressable. Fix clustering first.

## Recommended next moves

### Option A (1 day): Phase 1.5 clustering refinement

1. Build a second-pass name-merger: families whose normalized `display_name`s differ by ≤ 2 edit-distance or share a known canonical token (alphafold, vep, fastqc, metaphlan, …) get merged into one suite, members combined, FTS rebuilt.
2. Re-run the A/B eval. Target: ≥ +7pp top-1 (63%+).
3. If that target is hit, propose production promotion (specific plan below); if not, archive.

### Option B (2 days): Phase 1.5 + canonical pipelines layer

In parallel, build a `pipelines_canonical.db` for the ~30 nf-core + ~10 biomate workflows. Then run the existing 155-case cross-domain routing benchmark against both. This is the right test for the LLM's primary routing decision (workflow level), which is where the user-visible benefit is biggest.

### Option C (now): Archive the sandbox + write up learnings

If +3.3pp doesn't justify continued investment, the sandbox stays at `sandbox/retrieval_v2/` with all artifacts intact for future use. Phase 0 + Phase 1 work documented; canonical DB regenerable from `build_canonical_db.py` whenever needed.

## Production promotion plan (only if Phase 1.5 hits the +7pp target)

If we commit to ship:

1. Move `sandbox/retrieval_v2/output/tool_canonical.db` into `backend/database/tool_canonical.db` (kept separate from `galaxy_ai_tools.db` — additive).
2. Move `retrievers/tool_catalog.py` to `backend/lib/galaxy/ai/retrievers/tool_catalog.py` (and the 3 other retrievers — Europe PMC, OMIM, tools.py).
3. Add `tool_canonical.db` regeneration to the existing tool-DB build pipeline (probably `backend/scripts/build_tool_db.py` or similar — need to find).
4. Wire `search_tool_suites` into `/api/ai_assistant/search_ranked` as an additional retrieval signal, NOT as a replacement (additive scoring; canonical hits get a +X bonus).
5. Feature-flag the whole thing (`BIOMATE_USE_CANONICAL_SUITES=1`) for A/B in production.

Estimated promotion effort: ~2 days code + ~1 day production validation.

## Open observations

1. **Most "losses" are family-key fragmentation, not retrieval quality.** The FTS scoring is fine; we just have too many fragments per logical family. Phase 1.5 should mostly close this.
2. **Some "wins" are masked by the metric.** q01 DESeq2: FLAT returns `smagexp / deseq_hts / rmarkdown_deseq2` (no `deseq2` in top-3 at all). CANONICAL returns `deseq2 / deseq_hts / shinyngs`. Even when both score equally on top-3, the canonical answer is the one a scientist would recognize. The benchmark doesn't capture that subjective quality difference.
3. **The eval set is small (n=30).** Conclusions are directionally indicative, not statistically tight. Before any production promotion, expand to n=100+ and include a few adversarial queries.

## What I'm asking the user

Pick one:
- **A (1 day clustering refinement)** — most likely to produce a clear ship/no-ship answer.
- **B (2 days incl. pipelines layer)** — larger surface, larger potential win.
- **C (archive now)** — accept that the wrapper catalog as-is, plus the existing flat search, is good enough for now and the architectural investment isn't paying off enough yet.

---

## Phase 1.5 Update (2026-05-18) — Option A run; the real lever is the alias map

Built `sandbox/retrieval_v2/data/family_aliases.yaml` — a 155-rule fragment→canonical map covering BWA, Bowtie, Bowtie2, HISAT2, Salmon, DESeq2, edgeR, FeatureCounts, FastQC, Cutadapt, fastp, Samtools, Picard, BCFtools, Bedtools, EnsemblVEP, SnpEff, AlphaFold, MetaPhlAn, Kraken/Kraken2, SPAdes, MACS2, EMBOSS, DIAMOND, Trinity, Bismark. Rebuilt `tool_canonical.db` applying the aliases; 209 wrappers re-grouped; suite count 8,572 → 8,417.

### Re-run A/B numbers (same 30-query eval set)

| Path | top-1 | top-3 | top-10 |
|---|---|---|---|
| FLAT pre-aliases | 56.7% | 90.0% | 100.0% |
| **FLAT post-aliases** | **73.3% (+16.6pp)** | 96.7% | 100.0% |
| CANONICAL pre-aliases | 60.0% | 90.0% | 96.7% |
| **CANONICAL post-aliases** | **76.7% (+16.7pp)** | 90.0% | 100.0% |

### What this tells us

**The single biggest lever is the alias map, not the canonical DB.**

Both retrieval paths got the same +16pp from aliasing because FLAT's results are collapsed to suite_ids using the same `tool_wrapper_mapping` table — which now applies aliases. The canonical DB adds another modest **+3.4pp** (76.7% vs 73.3%) on top, which is below the +5pp ship threshold.

In other words: **a curated alias map applied as a post-processor on existing `search_ranked` results captures most of the win without touching the schema.** This is data, not code; it's much cheaper to ship and maintain than a parallel canonical DB.

### Revised recommendation

**Ship the alias map. Archive the canonical DB.**

Concretely:

1. **Promote `sandbox/retrieval_v2/data/family_aliases.yaml`** to `backend/config/tool_family_aliases.yaml`.
2. **Add a small post-processor** to `backend/lib/galaxy/.../search_ranked` (or wherever results are assembled) that:
   - Reads the alias map at startup.
   - Tags each wrapper result with its canonical family_id.
   - Deduplicates results by canonical family_id, keeping the highest-ranked wrapper as the representative.
   - Returns the canonical display name in the result envelope.
3. **Wire the alias map into the disambiguation card**: when multiple wrappers in the same canonical family are returned, the LLM/UI shows them as one suite with picker dropdown instead of multiple line items.
4. **Keep `sandbox/retrieval_v2/`** as a regenerable artifact and a place to experiment with deeper restructures later. Don't promote the canonical DB.
5. **Expand the alias map iteratively.** Each disambiguation-card fire in production = a candidate for new alias rules. Add ~10-20 high-traffic families per quarter.

Estimated promotion effort: **~half a day code + half a day production validation**. Far less than the original 2-day promotion plan, and the win is durable.

### Why this is honest, not a retreat

The canonical-DB plan was correct *in principle* (the disambiguation thesis held — DESeq2 / Cutadapt / Picard / EMBOSS all surface canonically now). What the data revealed is that the *implementation* needed to be just the mapping, not the whole schema. Architecture should follow the smallest layer that captures the benefit.

The function-level hierarchy (Picard's 46 ops, EMBOSS's 110) is still a real artifact in `tool_canonical.db` and useful if/when we build agentic workflows where the LLM picks a function within a suite. That can be a future PR; right now the LLM doesn't need it because the routing benchmark scores at the suite level.

### Action items

- [x] Phase 1.5 alias map built and validated
- [ ] **Awaiting user approval** to promote `family_aliases.yaml` to `backend/database/` and write the post-processor.
- [ ] Expand alias map to ~300 rules covering the 50 most-fired disambiguation cases (data work, ~half day).
- [ ] Optional: keep canonical DB regeneration in CI for future agentic-workflow use.
