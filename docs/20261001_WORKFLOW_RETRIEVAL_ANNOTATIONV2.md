# Workflow Retrieval: index the enriched `annotation_v2` column

**Date:** 2026-10-01
**Area:** `backend/lib/galaxy/ai/unified_workflow_search.py` (UnifiedWorkflowSearch — the authoritative retriever)
**Change class:** additive — index an existing rich field into the existing FTS5 + dense paths. No search engine rebuild.

## Problem (latent findability gap)

The authoritative workflow retriever indexed only
`name / description / annotation / tags / domain / tools_used`.
The workflows table also carries an **enriched** annotation column,
`annotation_v2` (~1300 chars avg vs ~180 for `annotation`), containing
`key_parameters`, `alternatives`, `when_to_use`, and keyword vocabulary —
but it was in **neither** the FTS5 index **nor** the dense embedding text.
Well-annotated workflows were therefore under-retrieved: a user describing
intent with parameter/keyword language that lives only in `annotation_v2`
could not find the matching workflow.

### Verified data state (local `backend/database/galaxy_ai_tools.db`)

- 4,209 workflows total.
- `annotation_v2` populated (>10 chars) for **3,231** rows.
- Proteomics: **161 / 186** have `annotation_v2`.
- Avg length: `annotation` 178 chars vs `annotation_v2` **1,298** chars.
- **1,716** workflows have rich `annotation_v2` (>400 chars) but thin
  `annotation` (<120) — the exact under-retrieved population.
- `scientific_context`: **column does not exist** in this schema. Memory
  flagged it as a past gap; it is not present here, so only `annotation_v2`
  was added. (Verified via `PRAGMA table_info(workflows)` — no such column;
  a `SELECT ... scientific_context` errors.)

## Changes

### 1. FTS5 index + triggers (`annotation_v2` added)

- `_create_fts_index()` — FTS5 virtual table schema now includes
  `annotation_v2`; the populate `INSERT ... SELECT` selects it too.
- **Migration** `backend/scripts/migrate_fts_add_annotation_v2.py` — the FTS
  table is external-content (`content='workflows'`) and already exists in the
  live DB, so `_create_fts_index` (which only fires when the table is absent)
  would not upgrade it. The migration drops + recreates `workflows_fts` with
  `annotation_v2`, repopulates all rows, and rebuilds the sync triggers.
  Idempotent (no-op if `annotation_v2` is already in the FTS schema).
- **Trigger correctness fix:** the pre-existing `workflows_au` (UPDATE) trigger
  used `DELETE FROM workflows_fts WHERE rowid=...`, which **corrupts** an FTS5
  external-content index (it desyncs the internal shadow tables). The migration
  replaces it with the correct FTS5 `'delete'` command form and adds a proper
  `workflows_ad` (DELETE) trigger. Verified: `integrity-check` passes after
  insert/update/delete round-trips.
- The production FTS queries use `workflows_fts MATCH ?` with **no column
  restriction**, so adding the column makes it searchable with no query-code
  change. BM25 keeps name/exact-match signal dominant.

### 2. Dense embedding text (`annotation_v2` appended, truncated)

- `_build_workflow_embeddings()` — SELECT now pulls `annotation_v2`; the
  encoded text appends `annotation_v2[:500]` (mirroring how `annotation[:300]`
  is appended). Truncated to 500 so the ~1300-char field carries the
  distinctive intent/parameter vocabulary **without swamping** the
  name/description signal.
- `_compute_workflow_db_signature()` — the staleness hash now includes
  `annotation_v2`, so the dense `.npz` is detected stale and **regenerates on
  the deploy / first load** after this change. (The full-DB embedding rebuild
  is ~60s and is a deploy-time operation, per the existing design; not run
  locally — no `.npz` exists in the local stub DB.)

## Measurement (real retriever, no fabricated numbers)

Held-out query set: **30 queries across 17 domains**, auto-derived from
distinctive multi-word phrases that appear in `annotation_v2` but **not** in
name/description/annotation (so a hit is only possible if `annotation_v2` is
indexed — these are realistic intent/parameter phrases a user could type).
Script: scratchpad `build_queryset.py`. Measurement replicates the exact
production FTS path: real `_build_fts_query()` tokenizer + `workflows_fts MATCH`
+ subworkflow filename exclusions + `ORDER BY bm25(workflows_fts)`.
(Dense layer measured separately is out of scope here — the local env's
scipy/sklearn is broken so sentence-transformers can't load; this isolates the
FTS schema change, which is the cheap high-impact part.)

| Metric | BEFORE | AFTER | Δ |
|---|---|---|---|
| recall@1 | 0.000 | **0.400** | +0.400 |
| recall@3 | 0.000 | **0.600** | +0.600 |
| recall@5 | 0.000 | **0.833** | +0.833 |
| recall@10 | 0.000 | **0.900** | +0.900 |
| any-retrieved (@20) | 0.033 | **0.900** | +0.867 |

Honest read: BEFORE is ~0 **by construction** — these queries target
`annotation_v2`-only vocabulary, which was unindexed, so they returned nothing.
This measures the *newly-reachable* surface, not a general-corpus uplift. The
takeaway is that a large, previously-dark slice of the catalog's descriptive
content (1,716 rich-v2 workflows) became retrievable. For queries already
served by name/description, ranking is unchanged (BM25 still favors
name/exact-match; v2 only adds recall for intent/parameter language). 3/30
queries still miss at @10 (e.g. a generic "ExpressionSet expression matrix"
phrase shared by many systems-biology workflows) — expected for low-specificity
phrases.

## Deploy notes

- Backend-Python-only change → **no tsc**; `py_compile` of the changed `.py`
  passes.
- Dev DB is the authoritative enriched copy (local is a stub). After sync, run
  the migration against the dev DB once to upgrade its FTS schema:
  `python3 backend/scripts/migrate_fts_add_annotation_v2.py <dev galaxy_ai_tools.db>`
  then verify `.schema workflows_fts` shows `annotation_v2`.
- The dense `.npz` regenerates automatically on first load post-deploy (stale
  signature). No manual rebuild needed, but it costs ~60s on that first load.

## Files

- `backend/lib/galaxy/ai/unified_workflow_search.py` — FTS schema + populate,
  embedding text, staleness signature.
- `backend/scripts/migrate_fts_add_annotation_v2.py` — DB migration (new).
