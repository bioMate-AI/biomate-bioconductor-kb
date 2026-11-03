# Search failures were reported as "no results", and the sync marker trap (2026-11-02)

For a reader with no background. Two separate problems found while verifying dev; both are fixed or have a recipe below.

## 1. Federated search hid failures
**Symptom.** On dev, Semantic Scholar returned "ok, 0 results" for every literature query.
**Cause.** From inside the Galaxy container the keyless Semantic Scholar API answers HTTP 429 (shared rate limit). `federated_query._get` caught every exception, logged at DEBUG and returned `None`; each fetcher then returned an empty list and the fan-out counted the source as succeeded, and cached the whole answer for an hour. This applied to every source (rate limit, timeout, outage all looked like "nothing found").
**Fix** (`backend/lib/galaxy/ai/federated_query.py`, commit `ce0569fa9`):
- a failed request is recorded per fetcher thread; `_run_fetcher` turns "failure and no results" into `status: error` with the reason (`HTTP 429 from api.semanticscholar.org`), and "failure but some results" into a `warnings` entry;
- `sources_failed` lists those sources; a result containing a failed source is not cached;
- `SEMANTIC_SCHOLAR_API_KEY` is sent as `x-api-key` when set (free key: semanticscholar.org/product/api). Without it Semantic Scholar keeps failing on dev, now visibly.
**Tests.** `backend/lib/galaxy/ai/test_biorxiv_source.py` (11 tests: rate limit as error, warning case, no leakage between fetchers, fan-out lists the failed source and skips the cache, key header only when set).
**Verified on dev** (sync `ce0569fa`): a fresh query reported `FAILED: ['semantic_scholar']` with the 429 reason; OpenAlex, PubMed, bioRxiv/medRxiv, Europe PMC and Crossref returned papers; Paperclip showed `disabled` (no key).
**Related**: the chat `query_database` tool and `search_literature` both read these fields, so the model sees which sources were not searched.

## 2. The shared "last synced" marker
`scripts/sync_to_dev.sh` stores one file, `.last_dev_sync_commit` (git-ignored), and syncs only the files changed since that commit. A frontend-only run (`BIOMATE_ONLY_FRONTEND=1`, used by another session) writes the same marker, so it moves the marker past backend commits it never shipped. Twice this session a full sync then reported `backend=false` ("Diff base: <my commit> → HEAD") and silently skipped the backend, leaving dev's frontend calling backend code that was not there.
**Recipe when it happens.** Read the log line `Diff base:` and `Layers:` at the start of a sync. If backend files changed in git since the last backend sync but `backend=false`, with no other sync running (`/tmp/biomate_sync_to_dev.lock` absent), set the marker to the last commit whose sync included the backend and rerun:
`echo <that full sha> > .last_dev_sync_commit && bash scripts/sync_to_dev.sh`
Last backend-synced commit before this note: `ce0569fa`. The lasting fix is to keep separate markers per layer in the script (not done).
Other sync-script issues seen: the in-container DB copy step has a quoting error (`"{{.Names}}"` inside a double-quoted `bash -c`), harmless because the host volume `/opt/biomate/galaxy_db` is mounted at `/app/database`; the embedding rebuild timeout (660 s) is tight; the script refuses to run with uncommitted tracked source files.

## 3. Numbers to quote (from `scripts/source_registry_report.py`, 2026-11-02)
Registry 62 entries, 60 live, 2 need a key (OMIM, Paperclip). 30 are queryable (27 by fan-out or dedicated tool, 3 single-source/MCP only: BindingDB, PDBe, Pharos); 30 are Galaxy import tools (not question-answering).
Literature sources that returned papers on dev: PubMed, Europe PMC, OpenAlex, bioRxiv/medRxiv (preprints, not peer reviewed); Crossref returns metadata. Semantic Scholar is failing on dev without a key; Paperclip needs a key; the local corpus index is empty until a corpus is ingested. Do not quote "4 literature sources" without this qualification.

## 4. Still open
Semantic Scholar key on dev; per-layer sync markers; a chat session to observe the new `query_database` tool end to end; 18 database connectors listed in the UI have no integration (`20261101_DATABASE_LIST_UI_VS_BACKEND.md`); tool-set unification (`20261102_TOOL_SETS_UNIFICATION_PLAN.md`).
