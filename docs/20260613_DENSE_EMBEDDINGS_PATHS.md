# Dense embeddings — file paths, lifecycle, and S3 policy

For the team (2026-06-13). Where BioMate's BGE dense-retrieval
embeddings live in code, on disk, in containers, and in S3 — plus
what regenerates them and what does not.

## TL;DR

| Question | Answer |
|---|---|
| Where in S3? | **Nowhere as a tracked artifact.** Only the source `.db` (271 MB) is in S3. The embeddings are a derivable view of the DB. |
| Where on disk locally? | `backend/database/galaxy_ai_workflow_embeddings.npz` (workflows, ~5.5 MB) and `backend/galaxy_ai_tools_embeddings.npz` (tools, ~11 MB) |
| What builds them? | `_ensure_workflow_embeddings()` in `backend/lib/galaxy/ai/unified_workflow_search.py` — lazy on first use, CPU-only (BGE via SentenceTransformer) |
| What consumes them? | `unified_workflow_search.py` (workflow ranking) + `vector_search.py` (tool ranking) — additive bonus on top of FTS + keyword + named-anchor scoring |
| How do they get to dev EC2? | They DON'T travel through `scripts/sync_to_dev.sh`. They live in the `dev_db_bundle` tarball or are rebuilt by the container on first search. |
| If stale, who rebuilds? | The container itself, lazily, via `_build_workflow_embeddings()` when it can't find an `.npz` or when a missing-id is detected. |

---

## 1. Code paths

### Workflow embeddings (the big one — used by chat routing)

**File on disk**: `backend/database/galaxy_ai_workflow_embeddings.npz`
*(2,449+ workflow vectors, 384-dim BGE-small-en-v1.5)*

**Builder / loader**: `backend/lib/galaxy/ai/unified_workflow_search.py`

```
class UnifiedWorkflowSearch:
  _ensure_workflow_embeddings():               # line ~1296 — lazy init guard
    _WORKFLOW_EMBED_NPZ = self.db_path.parent / "galaxy_ai_workflow_embeddings.npz"
    if .npz exists → _load_workflow_embeddings()
    else           → _build_workflow_embeddings()  # CPU, BGE inference

  _build_workflow_embeddings():                # line ~1352 — bulk encode all rows
    reads from sqlite (self.db_path) → encodes name+description → saves .npz

  _load_workflow_embeddings():                 # line ~1344
    np.load → in-memory matrix (NWORKFLOWS × 384)

  search():                                    # consumers
    if !self._ensure_workflow_embeddings(): return classical-only
    cosine-similarity ranks → additive bonus (sim * 5.0) onto base score
```

Hard-codes CPU (`device="cpu"`) because the build machine's PyTorch
build doesn't support the local GPU (NVIDIA GB10 sm_121 issue).

### Tool embeddings (used by tool-search RAG)

**File on disk**: `backend/galaxy_ai_tools_embeddings.npz`
*(~12,000 tool vectors, same 384-dim BGE)*

**Builder / loader**: `backend/lib/galaxy/ai/vector_search.py`

```
embedding_path = db_path.replace('.db', '_embeddings.npz')   # line 106
```

Same pattern as workflows. Built once from the `.db`, cached as `.npz`,
loaded on subsequent searches.

### Reference docs in repo

| Doc | Notes |
|---|---|
| `docs/20260415_HYBRID_WORKFLOW_SEARCH_BGE_DENSE_RETRIEVAL.md` | Original design: BGE + FTS + named-anchor hybrid ranking |
| `docs/20260417_TRULY_NEW_WORKFLOWS_AND_GAP_FILLS.md` | When the .npz was stale (2,449 entries / max_id=12,860) and how to rebuild |
| `docs/20260417_ALL_BUGS_AND_FIXES.md` | Lists `database/galaxy_ai_workflow_embeddings.npz` as a required artifact |
| `backend/lib/galaxy/ai/SEARCH_OPTIMIZATION_PLAN.md:597` | Reference to the `db.replace('.db', '_embeddings.npz')` convention |

---

## 2. Disk paths — workstation, dev container, dev host

| Location | Path | Size (approx) | Notes |
|---|---|---|---|
| Workstation | `backend/database/galaxy_ai_workflow_embeddings.npz` | 5.5 MB | Committed source-of-truth for the workflow side |
| Workstation | `backend/galaxy_ai_tools_embeddings.npz` | 11 MB | Tool side (note: NOT under `backend/database/`) |
| Dev EC2 (host) | `/opt/biomate/galaxy_build/galaxy_ai_tools_embeddings.npz` | 11 MB | Baked-in build artifact for the Galaxy container image |
| Dev EC2 (host) | `/tmp/dev_db_bundle/galaxy_ai_workflow_embeddings.npz` | 5.5 MB | Staging copy from a one-off bundle (NOT live-updated by sync) |
| Galaxy container | `/app/database/galaxy_ai_workflow_embeddings.npz` | 5.5 MB | What `unified_workflow_search.py` actually reads at runtime |
| Galaxy container | `/app/database/galaxy_ai_tools_embeddings.npz` | — | Built lazily inside the container; not always present |

---

## 3. S3 policy — explicit

**There is currently no canonical S3 path for the embeddings.**
Verified by full bucket scan (2026-06-13):

| Bucket / prefix | Contains embeddings? |
|---|---|
| `s3://biomate-production-backups-399683337364/db_transfers/20260512_1346/galaxy_ai_tools.db` | source `.db` (271 MB) — yes |
| `s3://biomate-nextflow-work/dev-sync/galaxy_build_ctx.tar.gz` | container build context (184 MB) — embeddings baked in inside |
| `s3://biomate-nextflow-work/nextflow/outputs/.../predictions/*.npz` | per-run Boltz prediction artifacts — unrelated |
| Other Biomate buckets (`biomate-models`, `biomate-instruments`, …) | none |

**Why no canonical S3 location?**

- The `.db` is the source of truth; embeddings are derivable from it in
  ~minutes on CPU.
- Embeddings are small (~5.5 MB workflows + ~11 MB tools = ~16 MB
  combined) — well below the per-file threshold where S3-distribution
  would justify the operational overhead.
- The lazy rebuild path (`_ensure_workflow_embeddings()`) is the
  recovery mechanism — if a container starts without an `.npz`, it
  rebuilds on first search request (cold-start cost: ~30-90 s, one
  time).

---

## 4. Sync mechanics — what `scripts/sync_to_dev.sh` does and does not do

| Artifact | Synced to dev by `sync_to_dev.sh`? | How |
|---|---|---|
| `galaxy_ai_tools.db` (workflow source DB, 271 MB) | ✅ | direct `scp` to `/tmp/galaxy_ai_tools_sync.db` then `docker cp` into `biomate-galaxy-dev:/app/database/galaxy_ai_tools.db` (line 408–423 of sync script) |
| `universe.sqlite` (Galaxy user table) | ✅ | similar `scp` + `docker cp` path (line 445+) |
| `galaxy_ai_workflow_embeddings.npz` | ❌ **NOT synced** | The script does not touch the `.npz`. Dev relies on the bundled copy at `/tmp/dev_db_bundle/` from the initial build, OR the container's lazy rebuild. |
| `galaxy_ai_tools_embeddings.npz` | ❌ **NOT synced** | Same as workflows. |

**Implication**: if the workstation's `.db` mutates significantly (new
workflows added, embeddings regenerated locally), dev gets the updated
`.db` but **not** the updated `.npz`. The container will detect the
mismatch on next search and rebuild lazily — fine for correctness, but
slow on first request after a sync.

---

## 5. How to rebuild (workstation or dev)

### Local workstation

```bash
cd /home/yzhang/biomate

# Delete the stale .npz to force a rebuild on next chat
rm backend/database/galaxy_ai_workflow_embeddings.npz

# Restart the backend (it'll lazy-rebuild on first /api/ai_assistant/* call)
bash backend/start_backend.sh
```

Or rebuild eagerly:

```bash
cd backend
python3 -c "
from lib.galaxy.ai.unified_workflow_search import UnifiedWorkflowSearch
s = UnifiedWorkflowSearch(db_path='database/galaxy_ai_tools.db')
s._build_workflow_embeddings()
print('rebuilt:', s.db_path.parent / 'galaxy_ai_workflow_embeddings.npz')
"
```

Cost: 30–90 seconds on CPU.

### Dev EC2

The container builds lazily inside its own filesystem — usually no
human action needed. To force:

```bash
# from workstation
ssh -i "$KEY_FILE" "${EC2_USER}@${EC2_HOST}" \
  'sudo docker exec biomate-galaxy-dev rm /app/database/galaxy_ai_workflow_embeddings.npz'

# next /api/ai_assistant/* request triggers rebuild
```

---

## 6. Open questions / TODOs

1. **Should embeddings live in S3?** Pros: faster cold-start on a
   new dev box, immutable across reboots. Cons: requires a new sync
   step + freshness contract. Recommendation: skip unless cold-start
   delay becomes a recurring complaint.

2. **Should `sync_to_dev.sh` also push the `.npz`?** It would shave
   the ~minute lazy-rebuild from the first chat after a DB sync.
   Trade-off: another ~16 MB SCP each push. Recommendation: add it as
   a conditional layer (only when the `.npz` mtime is newer than the
   live one on dev — same gating logic as the `.db`).

3. **GPU build path.** Today's `device="cpu"` is a workaround for a
   sm_121 / PyTorch incompatibility. When PyTorch picks up sm_121, we
   should re-enable `cuda` for ~10× faster builds.

---

## Cross-references

- `docs/20260415_HYBRID_WORKFLOW_SEARCH_BGE_DENSE_RETRIEVAL.md` — full
  hybrid-retrieval design.
- `backend/lib/galaxy/ai/unified_workflow_search.py` — primary
  consumer.
- `scripts/sync_to_dev.sh` — current sync mechanism (does NOT
  include `.npz`).
