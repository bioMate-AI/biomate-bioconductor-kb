# Intent-Driven DB Search + Deploy Root-Cause Investigation

**Date:** 2026-07-19
**Branch:** `integration/next-phase`
**Commits:** `8bc20cc1d` (ChEMBL similarity in `query_database` tool), `1bfe241fe` (PDB similarity + `operation` plumbing), `a90ecdefa` (forward `operation` through the REST proxy — the fix that made it work end-to-end)

---

## 1. What was built

Closed the **API tier** for full-scale database search: users can now run
similarity search against hosted public APIs (ChEMBL, RCSB PDB) with **zero
index hosting**, complementing the self-hosted Foldseek / FPSim2 / MMseqs2
workflows (which remain the premium tier for private / high-volume / air-gapped
use).

### Feature: intent-driven `operation` on `query_database`

The `query_database` tool now takes an explicit **`operation`** — `lookup`
(default), `similarity`, or `text` — chosen by the LLM **from the user's
intent**, not inferred from the shape of the query string.

| database | `operation=similarity` behavior |
|---|---|
| `chembl` | Tanimoto similarity search across **all of ChEMBL** for a SMILES (`/similarity/{smiles}/{threshold}`) |
| `pdb` | sequence-homolog search across the **entire PDB** for a protein sequence (RCSB Search API `sequence` service) |

`lookup` = fetch by ID/accession/name; `text` = keyword search.

### Threaded through all four layers
1. **LLM tool schema** (`frontend/server/routes.ts`) — added the `operation`
   enum + description; also added `chembl` to the `database` enum (it was
   missing entirely — the LLM previously could not select ChEMBL).
2. **Node executor** (`routes.ts`) — forwards `operation` to `/api/databases/query`.
3. **FastAPI model** (`backend/lib/galaxy/webapps/galaxy/api/ai_assistant.py`) —
   `DatabaseQueryRequest.operation`, passed to `ai.query_database(...)`.
4. **Handlers** (`backend/lib/galaxy/ai/ai_assistant.py`) —
   `query_database(db, query, operation)` dispatches; `_query_chembl` and
   `_query_pdb` select the mode purely on `operation`.

### Catalog (`galaxy_ai_tools.db`, gitignored — deploys via sync DB layer)
- Updated **ChEMBL REST** `live_api` tool to advertise Tanimoto search.
- Added new **RCSB PDB Search API** `live_api` tool (sequence + 3D-structure
  similarity). The `live_api` tier is now 10 hosted APIs.

---

## 2. Design correction: intent, not string-sniffing

The **first** implementation added regex detectors (`_looks_like_smiles`,
`_looks_like_protein_seq`) that inferred the search mode from the query string.
This was rejected — **intent determines the route**. The detectors were removed
entirely; the LLM (which already parses intent) now sets `operation`
explicitly. The decisive test proves it:

> The **same** ubiquitin sequence routes to full-text under `operation=text`
> and to sequence-homolog search under `operation=similarity`. The route
> follows intent, not the payload's shape.

Local verification (15/15 checks): live RCSB sequence search returned ~2,000
ubiquitin homologs; live ChEMBL Tanimoto returned aspirin; lookup/text
regressions intact; zero references to the removed detectors.

---

## 3. Deploy root-cause investigation (the hard part)

**Symptom:** committed + locally-verified code did not take effect on
`dev-public.biomate.ai` across **four** syncs. `operation=similarity` and
`operation=text` returned byte-identical old name-search results.

### Root cause A — incremental backend gate skips "overtaken" commits
`sync_to_dev.sh` computes `CHANGED = git diff <last-synced-marker>...HEAD` and
only runs the backend layer if `CHANGED` contains `^backend/lib/`
(`do_backend=true`, line ~1208). The marker (`.last_dev_sync_commit`) had
already advanced **past** my backend commits (my commit was an *ancestor* of
the marker), so every subsequent incremental sync saw **0 backend/lib files**
and **skipped the backend layer entirely**. Verified:

```
marker 5422fcf3c has 1bfe241fe as ANCESTOR
git diff marker...HEAD  ->  backend/lib files: 0  ->  do_backend=false
```

**Immediate remedy:** rewind `.last_dev_sync_commit` to a commit *before* the
change (`a536c0a60`, parent of the earliest of the two commits) so the diff
re-includes `backend/lib`. `deploy_backend_python` itself uses a fixed
pre-April base for its file list, so once it runs it copies the correct
files. After this, the sync **did** `cp` my files into the container
(`cp: /app/lib/galaxy/ai/ai_assistant.py`, `.../api/ai_assistant.py`).

### Root cause B (THE ACTUAL BLOCKER) — Node REST proxy dropped `operation`
After root cause A was fixed, Galaxy had the new code on disk **and was serving
it** — proven by hitting Galaxy directly inside the container
(`docker exec biomate-galaxy-dev curl localhost:8080/api/databases/query
-d '{...operation:similarity...}'`), which returned
`search=tanimoto_similarity` (ASPIRIN 100, CARBASPIRIN 88.9) and
`sequence_similarity` (2,000 PDB hits).

But the **public** endpoint still returned old results, because there are **two**
`/api/databases/query` code paths in `frontend/server/routes.ts`:
- line ~1014 — the LLM tool executor (fixed: forwards `operation`)
- **line ~8135 — a separate REST route** (used by MCP `query_database` + direct
  clients) that destructured `{database, query, entity_type, sources}` and
  **dropped `operation`** before proxying to Galaxy.

Every curl and MCP call hit route #8135, so Galaxy always received the default
`lookup`. **This — not a stale arbiter — is why every public test showed old
behavior.** Fix: add `operation` to the destructure + forwarded body
(commit `a90ecdefa`).

### Misdiagnosis worth recording
Before finding the proxy bug, the stale public behavior was attributed to
`--preload` + a concurrent session recycling workers off a stale arbiter. That
was **wrong** — the in-container direct test proved Galaxy served new code the
whole time. Lesson: when a proxied endpoint looks stale, **test the origin
directly (in-container) before blaming the runtime/reload.** The `--preload`
mechanics below are still true and root cause A/C are still real; they just
weren't why the public curl failed.

### Root cause C — `restart_galaxy` is gated on `do_backend`
Galaxy's gunicorn runs with `--preload`, so only a full **arbiter restart**
(`galaxyctl restart gunicorn`, which `restart_galaxy` does) loads new `.py`
files — a `SIGHUP` does not. But `restart_galaxy` only fires when the diff
detects `backend/lib` changes, so a sync that misses backend changes (root
cause A) also never restarts gunicorn, risking silently-stale backend code.

---

## 4. Fixes applied

1. **Root cause A:** rewound `.last_dev_sync_commit` to before the change so the
   incremental diff re-included `backend/lib` → backend layer ran →
   `deploy_backend_python` copied the files → `restart_galaxy` re-preloaded them.
2. **Verified Galaxy live** by hitting the origin directly in-container
   (bypassing the proxy): `search=tanimoto_similarity` + `sequence_similarity`.
3. **Root cause B (the actual blocker):** `frontend/server/routes.ts:8135` now
   forwards `operation` to Galaxy (commit `a90ecdefa`). Deploying via a frontend
   rebuild.

**Verification (live, dev): ✅ COMPLETE — LIVE END-TO-END on the public endpoint**
- Galaxy origin (in-container): `tanimoto_similarity` (ASPIRIN 100) +
  `sequence_similarity` (2,000 hits).
- Public `dev-public.biomate.ai/api/databases/query` after the proxy fix:
  - chembl `operation=similarity` → `search=tanimoto_similarity`, ASPIRIN DL-LYSINE (100)
  - pdb `operation=similarity` → `search=sequence_similarity`, **2,000 hits**
  - pdb `operation=text` (SAME sequence) → `search=None` — **intent, not the
    payload shape, determines the route.**

---

## 5. Recommended permanent fixes to `sync_to_dev.sh`

These are the durable fixes so this class of "sync OK but code not live" stops
recurring (do NOT workaround — fix at source):

1. **Decouple `restart_galaxy` from `do_backend`.** Always do a clean arbiter
   restart at the end of any sync that changed **any** code layer
   (frontend/backend/workflows), or make the restart unconditional and cheap.
   Rationale: root cause C — a missed backend-diff must not mean stale code.

2. **Make the backend layer robust to an overtaken marker.** Root cause A: if
   the marker is at/after a not-yet-deployed commit, the diff is empty. Options:
   verify deployed content (grep the in-container file for a sentinel) and
   re-copy if missing, or key deployment off actual container file hashes rather
   than the local git marker.

3. **Serialize + settle for `--preload`.** Root cause B: after `galaxyctl
   restart gunicorn`, the sync should hold the lock until the arbiter is fully
   up AND assert no external recycle is pending; concurrent syncs from multiple
   sessions must queue (the lock aborts today — consider a bounded wait so a
   second session finishes cleanly rather than racing worker recycles).

4. **Post-sync behavioral smoke assertion.** The health gate checks liveness,
   not that the *new* code is serving. Add a cheap assertion that a
   just-changed endpoint returns new-shape output (e.g. `operation=similarity`
   returns `search=tanimoto_similarity`) so a stale-arbiter deploy fails the
   gate instead of reporting healthy.

---

## 6. Files touched

| File | Change |
|---|---|
| `frontend/server/routes.ts` | `operation` enum + `chembl` in DB enum; forward `operation` |
| `backend/lib/galaxy/webapps/galaxy/api/ai_assistant.py` | `DatabaseQueryRequest.operation`; pass to `query_database` |
| `backend/lib/galaxy/ai/ai_assistant.py` | `operation`-driven `query_database` / `_query_chembl` / `_query_pdb`; removed sniffing detectors |
| `backend/database/galaxy_ai_tools.db` | ChEMBL REST desc + RCSB PDB Search API `live_api` entry (gitignored) |

## 7. LLM-flow smoke test — ✅ PASSED (real chat turn on dev)

`POST /api/open-claw/stream` with *"Search ChEMBL for compounds structurally
similar to this molecule. SMILES: CC(=O)Oc1ccccc1C(=O)O"*. The model chose,
unprompted:
```json
{"database":"chembl","operation":"similarity","query":"CC(=O)Oc1ccccc1C(=O)O"}
```
→ tool returned `tanimoto_similarity` (ASPIRIN 100, CARBASPIRIN 88.9,
DIPLOSALSALATE 85.7); the model rendered a results table and correctly named
the molecule Aspirin. **The intent→`operation` mapping works end-to-end through
the real LLM.**

## 8. Status of the §5 hardening fixes
- **§5 #4 behavioral assertion — ✅ DONE (both layers).**
  - `scripts/post_sync_check.sh` **S6** (commit `85aa46258`, hardened in
    `7883bcfac`): standalone deterministic operation-routing canary.
  - `scripts/sync_to_dev.sh` `smoke_test_db_search()` (commit `7883bcfac`):
    wired into the **post-sync health gate** — after the workflow smoke test it
    hits `/api/databases/query` through the **frontend proxy** (`localhost:3000`
    → Galaxy) and asserts `operation=similarity` routes correctly and `text`
    does not. A well-formed-but-wrong response now **auto-rolls-back** the
    deploy; a transient error/empty/cold-start reply is inconclusive (no false
    rollback). **This is the exact gate that would have caught the proxy-drop
    bug at deploy time.**
  - Verified in isolation (no speculative deploy): passes on the good deploy,
    inconclusive on an unreachable host, fails only on a well-formed
    operation-dropped response. Note: `scripts/` is not a synced code layer, so
    the new gate takes effect on the *next* `sync_to_dev.sh` run automatically.
- **§5 #1–#3 remain** (decouple `restart_galaxy` from `do_backend`; verify
  in-container content vs. the git marker; serialize concurrent syncs). These
  edit the **deploy mechanism's control flow** — do them as a carefully-reviewed
  change, since a bug there breaks deploys for every session.
