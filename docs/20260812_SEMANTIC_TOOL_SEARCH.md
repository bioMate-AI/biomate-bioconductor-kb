# Semantic tool retrieval in the live tool search — delivered

**Date:** 2026-08-11 → 08-12 · Branch `integration/next-phase` · Verified live on dev.

## What shipped

BioMate's live tool search now runs **FTS ∪ dense semantic retrieval + `scientific_context`
scoring**, instead of plain lexical FTS. Tools finally match the semantic quality that
workflow search already had. Verified in the live chat path (not just a probe):

```
Enhanced search: query='batch effect removal single-cell RNA-seq integration'
FTS5 search returned 0 initial candidates
Semantic search added 45 tools FTS missed (total candidates: 45)
```

For that query **plain FTS returned 0 tools** — the chat found nothing — and semantic
recovered **45** relevant ones. That recall gap (FTS→0 on reasonable queries) was the whole
point; it's closed in production.

## The architecture (and the 3 overlapping search engines)

- **`EnhancedToolSearch.search_with_context`** (`enhanced_tool_search.py`) — the live tool
  path now: FTS candidates ∪ semantic candidates (`VectorToolSearch`), then `scientific_context`
  scoring. Guarded → plain-FTS fallback so it can never break.
- **`VectorToolSearch`** (`vector_search.py`) — dense index (bge-small). Loads a **shipped
  `.npz` artifact** (short-text embeddings: name/desc/category/help/tags/edam — NOT
  `scientific_context`, which is large and already drives scoring). A `shipped` marker key
  makes it trust the artifact (no staleness rebuild). Embed-server-backed with in-process ST
  fallback.
- **`UnifiedWorkflowSearch`** — separate, for workflow generation (untouched except an earlier
  incremental-embedding fix).

## The key fixes (in order they mattered)

1. **Endpoint mixup (the real blocker).** `GET /api/tool_search` (what the Node chat calls via
   `galaxyAPIProxy.searchTools`) used `search_index.search` = **plain FTS**. The semantic union
   AND `scientific_context` scoring were both in `search_with_context`, wired only to the
   **unused** `POST /api/tool_search/enhanced`. Fix (commit `80acde4f2`): route the GET endpoint
   through `search_with_context`.
2. **Build the 12k index off the dev CPU.** On dev it took ~30 min and the frequent Galaxy
   restarts (parallel-session churn) killed it every time. Fix: build the `.npz` **offline on a
   fast EC2** (c5.2xlarge, fastembed bge-small **in a venv** — AL2023's rpm `requests` blocks a
   bare `pip install`), upload to `s3://biomate-models-399683337364/v6_eval_runs/`, and have
   `sync_to_dev.sh` `docker cp` it into `/app/database/`. Box self-terminates; ~$0.10.
3. **Eager per-worker warm.** `warm_tool_index()` runs from the same `post_fork` startup thread
   as the workflow warmup, so every worker loads the shipped index at boot
   (`[ToolSearchWarmup] available=True tools=12288` on all 4 workers) — semantic from the first
   request, no lazy first-hit gap.

## Honesty / lessons

- I **over-claimed** early that the live tool search already used `scientific_context`. It did
  not — it was plain FTS. Verify the actual served endpoint before reasoning about behaviour.
- Chased the per-worker warmup for a long time when the true blocker was the endpoint routing.
  A read-only probe proved the retrieval worked while live queries didn't — that gap pointed
  straight at the endpoint, which I should have checked first.
- The environment (parallel sessions thrashing the shared repo + dev sync, slow dev CPU) caused
  most of the wall-clock, not the code. See [[reference_biomate_search_infra]] and
  [[feedback_check_connector_work]].

## Commits (this thread)
`80acde4f2` (GET route → enhanced), `26be2b3c8` (eager warm), `13b334ad0` (shipped-artifact
trust + robust warmer + S3-pull sync), plus the offline-build sync step and short-text recipe.

## Follow-ups (optional)
- The shipped `.npz` is built against the Aug-2 canonical DB (12,288 tools); dev has 12,297 —
  the ~9 newer tools fall back to FTS. Rebuild the artifact when the tool set changes materially.
- Consider retiring the unused `POST /api/tool_search/enhanced` or pointing it at the same code.

## Update (08-12): migrated to DB-native embeddings — npz retired

Per feedback ("why rebuild, why not incremental — can't the DB do this?"), moved tool
embeddings OUT of the separate `.npz` artifact and INTO the DB as a **`tools.embedding`
BLOB column** (mirrors `cryo_em_chunks.embedding_blob`). Now:
- `VectorToolSearch` loads doc vectors from the column (`[VectorSearch] loaded 12288
  embeddings from tools.embedding column`); npz is a transitional fallback.
- `upsert_tool_embedding(tool_id, text)` = incremental per-tool store (enrichment hook).
- Vectors propagate with the DB via the normal sync — no fast-box/S3/rebuild.
- Fixed `sync_to_dev.sh` DB size guard: was byte-based (silently skipped a VACUUMed or
  otherwise-smaller-but-full DB), now content-aware (>100MB = full DB, always push).
- Verified live: DB shipped (`db=true`), dev column has 12,288 vectors, all 4 workers
  load from it, "Semantic search added 45 tools FTS missed".
Remaining: the 9 newest tools (12,297 vs 12,288) have no vector until enriched; wire
`upsert_tool_embedding` into the actual enrichment job (not in the reachable code here).
