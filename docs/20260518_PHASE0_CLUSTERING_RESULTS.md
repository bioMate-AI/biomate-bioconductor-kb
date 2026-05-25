# Phase 0 — Tool Catalog Clustering Results

**Date:** 2026-05-18
**Scripts:** `sandbox/retrieval_v2/scripts/cluster_tools.py`, `function_dedup.py`
**Outputs:** `sandbox/retrieval_v2/output/tool_clusters.csv`, `function_duplicates.csv`
**DB analyzed:** `backend/database/galaxy_ai_tools.db` (read-only, 12,274 rows)

## Headline numbers

| Metric | Value |
|---|---|
| Total wrapper rows | 12,274 |
| Distinct family keys (path-extracted) | **8,572** |
| Family-level compression | **1.43×** (not 10–25× as previously claimed) |
| Singletons (1-wrapper families) | 7,453 (86.9%) |
| (family, function_signature) duplicate groups | 573 |
| Wrappers inside duplicate groups | 1,199 |
| **"Removable" extra wrappers** | **626 (5.1% of catalog)** |
| If function-deduped: catalog size | 11,648 (1.05× compression) |

## What this changes about the architecture rationale

My earlier framing — "5 DESeq2 wrappers across authors confuses the LLM" — turned out to be wrong on the numbers. The data:

- DESeq2 family has 5 wrappers, but their function signatures are mostly distinct (different tool intents: `damid_deseq2_to_peaks`, `aurora_deseq2`, `aurora_deseq2_site`, `interpolate_gatc_signal`, `deseq2`). Only the last one is "DESeq2 differential expression." So the apparent duplication is mostly the LLM-disambiguation pain over visibly-similar names of substantively different tools.
- The actual top-25 duplicates list is dominated by `netisce` (13 wrappers, niche systems-biology toolkit), `bwa` (5 "Map with BWA" variants — the only widely-recognized one), and a long tail of single-author toolkits with 3-4 wrappers each.
- Only 626 wrappers (5.1%) are true function-level duplicates. The catalog isn't bloated with author-variants the way I assumed.

**So pure deduplication is not the big win.** The 5% removable savings doesn't justify a schema migration.

## What IS the win: structure, not dedup

The real bloat is *function proliferation within toolkit-suites*, not duplication across authors:

| Toolkit family | Wrappers | Distinct functions |
|---|---|---|
| emboss | 111 | 108 |
| gembassy | 98 | 98 |
| qiime | 89 | 89 |
| picard | 87 | 46 |
| bedtools | 66 | 64 |
| gatk4 | 66 | 63 |
| ball | 62 | 62 |
| java_genomics_toolkit | 48 | 48 |
| samtools | 33 | 33 |
| bcftools | 29 | 27 |

These aren't duplicates — they're genuinely distinct operations (Picard `AddCommentsToBam`, `AddOrReplaceReadGroups`, `BedToIntervalList`, etc.). Today, each appears as an independent row, so a routing prompt that mentions "SAM/BAM processing" pulls in dozens of candidate Picard wrappers, GATK4 wrappers, samtools wrappers, all jumbled together.

A 3-level hierarchy — **suite → function → wrapper** — would let the LLM make decisions at the right granularity:

1. **Suite pick:** "Use Picard for read-group manipulation." (1 of ~50 suites)
2. **Function pick within suite:** "Within Picard, I need `AddOrReplaceReadGroups`." (1 of 46)
3. **Wrapper resolution:** Deterministic mapping to a specific Galaxy/nf-core wrapper.

The LLM context for step 1 lists ~50 canonical suites with one-line descriptions instead of ~12,274 wrapper rows. That's the real 200× context-budget win, even though row-count compression is only 1.43×.

## Revised proposal

**Replace "dedup the DB" with "add a suite/function/wrapper hierarchy on top."**

Concretely, the additive schema from the original plan still works, but with revised expectations:

- `tool_suites` table: ~50–200 rows, one per canonical suite (emboss, picard, gatk4, samtools, bedtools, qiime, frogs, …) + ~5,000–6,000 single-tool families (deseq2, bwa, fastp, …). Total: **maybe 5,500–6,500 rows**, not "500–1000."
- `tool_functions` table: one row per (suite, function) pair. ~11,000 rows.
- `tool_wrapper_mapping`: 12,274 rows — every existing wrapper points up to (suite, function).

The win isn't fewer rows — it's that the LLM only ever sees the level it needs:

- Routing/disambiguation: query → `tool_suites` (5,500 candidates, FTS+BGE narrows to top-10).
- Function selection: suite → `tool_functions` for that suite (typically 1–100 entries).
- Execution: (suite, function, platform) → exact wrapper.

## Open observations from the audit

1. **Sentinel families need attention:** clusters like `s_mart` (39 wrappers, "Convert Formats" — actually a French metabolomics toolkit) and `gap_all_glycan_tools` (21 wrappers) are toolkits where the family_key isn't recognizable to a scientist. Need human-friendly display names — the LLM (and user) won't recognize `s_mart` but will recognize "S-Mart metabolomics toolkit."

2. **86.9% singletons** suggests that for most rows, the wrapper IS the tool. The hierarchy collapses to two levels for these — just `tool_family` with a single default function. That's fine; the schema accommodates it.

3. **nf-core layout is already correct.** `nfcore/abricate/run` and `nfcore/abricate/summary` are already (family=abricate, function=run|summary). When we build the canonical schema, nf-core entries are a free win — just import the existing structure.

4. **Bioconductor is a special case.** `bioconductor/a4`, `bioconductor/a4base`, `bioconductor/a4preproc` are all the *same* logical Bioconductor R package family ("a4"). For R/Bioconductor, the package IS the suite and the exported functions ARE the function-level entries. We don't currently index Bioconductor function-level details — that's a future enrichment.

5. **EDAM coverage is poor** — only 1,661/12,274 rows (13.5%) have non-empty `edam_operations`. EDAM was a candidate clustering signal in the original plan; the data says it can only contribute on top of path-based clustering, not replace it.

## What I'm NOT proposing

- **No DB schema migration based on dedup alone.** 5.1% savings doesn't justify it.
- **No row deletion.** Every wrapper stays — the hierarchy is additive metadata.
- **No production code touches.** Everything stays in `sandbox/retrieval_v2/` until the canonical schema is built, populated, and A/B-tested against the routing benchmark.

## Recommended next steps

1. **Build the canonical schema in a separate SQLite file** (`sandbox/retrieval_v2/output/tool_canonical.db`). Populate it from `galaxy_ai_tools.db` using the clustering already done + EDAM where available. ~1 day.

2. **Build `search_tool_suites(query)` retriever** that hits the new DB. ~0.5 day.

3. **A/B benchmark on routing**: run 120 routing cases through (a) current flat search and (b) new suite-first search. Measure top-1 accuracy + mean candidate count per turn. If treatment shows ≥5pp improvement OR ≥3× candidate reduction without accuracy loss, proceed to integration planning. If not, archive the work as a learning and move on. ~1 day.

4. **Only if A/B succeeds**, propose production integration with the user.

Total: ~2.5 days to ship-or-archive decision. Conservative because we now know dedup isn't the lever and we need the routing benchmark to prove that hierarchy actually helps.

## Files for review

- `sandbox/retrieval_v2/output/tool_clusters.csv` — 8,572 families with member counts, sample names, top categories. Sort by `member_count` DESC and scan the top 100 to validate the clustering by eye.
- `sandbox/retrieval_v2/output/function_duplicates.csv` — 573 (family, function) groups with ≥ 2 wrappers. Sort by `wrapper_count` DESC. Top-25 already printed in the script output.
