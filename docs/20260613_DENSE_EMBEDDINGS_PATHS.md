# Dense embeddings — file paths, lifecycle, and S3 policy

For the team (2026-06-13). Where BioMate's BGE dense-retrieval
embeddings live in code, on disk, in containers, and in S3 — plus
what regenerates them and what does not.

## TL;DR

| Question | Answer |
|---|---|
| Where in S3? | **Nowhere as a tracked artifact.** Only the source `.db` (271 MB) is in S3. The embeddings are a derivable view of the DB. |
| Where on disk locally? | `backend/database/galaxy_ai_workflow_embeddings.npz` (workflows, ~5.5 MB) and `backend/galaxy_ai_tools_embeddings.npz` (tools, ~11 MB) |
| What builds them? | `_ensure_workflow_embeddings()` in `backend/lib/galaxy/ai/unified_workflow_search.py` — lazy on first use **only when the `.npz` file is absent**, CPU-only (BGE via SentenceTransformer). Staleness (DB-newer-than-npz, row-count drift, in-place edits) is **NOT** detected — see §6. |
| What consumes them? | `unified_workflow_search.py` (workflow ranking) + `vector_search.py` (tool ranking) — additive bonus on top of FTS + keyword + named-anchor scoring |
| How do they get to dev EC2? | They DON'T travel through `scripts/sync_to_dev.sh`. They live in the `dev_db_bundle` tarball or are rebuilt by the container on first search. |
| If stale, who rebuilds? | **Auto-detected on load as of 2026-06-14.** Both workflows (`unified_workflow_search.py`) and tools (`vector_search.py`) compare a SHA-256 content signature of live DB rows against one stamped into the `.npz`. Mismatch → rebuild during the next `_ensure_*()` call. Manual procedure in §7 still applies for getting the rebuilt `.npz` from workstation to dev container. |

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
workflows added, descriptions edited), dev gets the updated `.db` but
**not** the updated `.npz`. **The container does NOT detect the
mismatch.** `_ensure_workflow_embeddings()` only checks `.npz.exists()`
— it never compares mtimes, row counts, or content hashes against
the `.db`. So dev silently keeps using the stale `.npz` until a human
explicitly rebuilds + pushes. See §6 (Known bug) and §7 (Manual
freshness procedure).

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

## 6. Staleness detection — auto-rebuild on drift

**Patched 2026-06-14** (commit on `bioc/v2-qc-audit-panel`). Both
sides — `unified_workflow_search.py` and `vector_search.py` — now
detect a stale `.npz` against the live `.db` and auto-rebuild on
load. The original gap is documented below for context.

### Original gap (pre-patch)

`backend/lib/galaxy/ai/unified_workflow_search.py:1296+`:

```python
if _WORKFLOW_EMBED_NPZ.exists():
    self._load_workflow_embeddings()   # ← just loads whatever is there
else:
    self._build_workflow_embeddings()  # ← only fires when file is absent
```

No mtime check. No `COUNT(*) FROM workflows == len(_WF_EMBED_IDS)`
check. No content-hash signature in the `.npz` metadata. **If the
`.db` updates with new or changed workflows, the running process
silently keeps using the stale embeddings.**

Symptoms: new workflows are still routable via FTS/keyword fallback
but never get the dense-similarity bonus, so they lose tie-breaks they
should win.

### Recommended fix (cheapest correct version)

Inside `_ensure_workflow_embeddings()`, after `_load_workflow_embeddings()`:

```python
cursor.execute("SELECT COUNT(*) FROM workflows")
db_count = cursor.fetchone()[0]
if db_count != len(_WF_EMBED_IDS):
    log.info(
        "[WorkflowEmbed] DB has %d workflows, .npz has %d — rebuilding",
        db_count, len(_WF_EMBED_IDS),
    )
    self._build_workflow_embeddings()
```

Stricter variants (catch in-place description edits too): stamp the
`.npz` at build time with a SHA-256 of concatenated
`(id, name, description, annotation)` tuples; verify on load. ~1 ms
overhead per process start.

Until the fix lands, follow §7 manually after every meaningful `.db`
change.

### What the patch actually does

Both `_ensure_workflow_embeddings()` (workflows) and `initialize()`
(tools) now run `_workflow_embeddings_stale()` / `_embeddings_stale()`
right after `_load_*()`. The check is a two-tier compare:

1. **Row count** — `SELECT COUNT(*) FROM workflows` (or `tools`)
   compared to the loaded `_WF_EMBED_IDS` / `self.tool_ids`. Catches
   workflows added/removed since the last build. ~1 ms.
2. **Content signature** — SHA-256 over the same
   `(id, name, description, …, annotation)` tuples the build encodes.
   Stamped into the `.npz` at build time as `workflow_signature` /
   `tools_signature`. ~5-10 ms (hash pass over a few thousand
   strings). Catches in-place description edits, domain
   reclassification, tag changes — anything that would affect the
   encoded text.

Pre-existing `.npz` files have no signature metadata — the check
falls back to row-count parity only. The first opportunity to land a
rebuild also lands the signature, so subsequent loads on the same
container get the full check for free.

Verified round-trip on both sides (2026-06-14):

| Step | Workflows | Tools |
|---|---|---|
| Fresh build → stamped signature | 73 s, 4,005 vectors, sig `18ce3e5b…` | 390 s, 12,283 vectors, sig `92c3e8fb…` |
| Warm reload (no drift) | 0.0 s | 0.2 s |
| Drift detection (description edit) | 73 s rebuild | 346 s rebuild |
| Final rebuild after revert | 72 s, same `18ce3e5b…` | 369 s, same `92c3e8fb…` |

Signatures are deterministic — identical content always produces the
same hash, so two machines comparing `.npz` files can confirm
freshness without re-running the whole encode.

---

## 7. Manual freshness procedure (used 2026-06-13)

When the `.db` has been modified (new workflows, description edits,
domain reclassification, etc.) **AND** you need dev to reflect those
changes immediately:

### Step 1 — Rebuild locally (~67 s CPU)

```bash
cd /home/yzhang/biomate
rm backend/database/galaxy_ai_workflow_embeddings.npz
PYTHONPATH="$PWD/backend/lib:$PWD/backend" python3 -c "
from pathlib import Path
from galaxy.ai.unified_workflow_search import UnifiedWorkflowSearch
ok = UnifiedWorkflowSearch(
    db_path=Path('backend/database/galaxy_ai_tools.db')
)._ensure_workflow_embeddings()
print('rebuilt' if ok else 'FAILED')
"
```

### Step 2 — Verify alignment

```bash
python3 <<'PY'
import sqlite3, numpy as np, os
db = sqlite3.connect("backend/database/galaxy_ai_tools.db")
db_count = db.execute("SELECT COUNT(*) FROM workflows").fetchone()[0]
data = np.load("backend/database/galaxy_ai_workflow_embeddings.npz", allow_pickle=True)
ids_npz = set(int(x) for x in data["workflow_ids"])
ids_db  = set(r[0] for r in db.execute("SELECT id FROM workflows").fetchall())
print(f"DB={db_count}  .npz={len(ids_npz)}  missing={len(ids_db - ids_npz)}  extra={len(ids_npz - ids_db)}")
PY
```

Both counts equal, `missing=0`, `extra=0`. If not, the rebuild failed
silently — check logs.

### Step 3 — Push to dev container

```bash
cd /home/yzhang/biomate
source <(grep -E "^(EC2_HOST|EC2_USER|KEY_FILE|INSTANCE_ID|AZ)=" scripts/sync_to_dev.sh)
aws ec2-instance-connect send-ssh-public-key --instance-id "$INSTANCE_ID" \
  --availability-zone "$AZ" --instance-os-user "$EC2_USER" \
  --ssh-public-key "file://${KEY_FILE}.pub" --region us-west-2 \
  --output text --query 'Success' >/dev/null

scp -i "$KEY_FILE" backend/database/galaxy_ai_workflow_embeddings.npz \
  "${EC2_USER}@${EC2_HOST}:/tmp/galaxy_ai_workflow_embeddings_sync.npz"

ssh -i "$KEY_FILE" "${EC2_USER}@${EC2_HOST}" \
  "sudo docker cp /tmp/galaxy_ai_workflow_embeddings_sync.npz \
     biomate-galaxy-dev:/app/database/galaxy_ai_workflow_embeddings.npz && \
   sudo docker exec -u root biomate-galaxy-dev \
     chown galaxy:galaxy /app/database/galaxy_ai_workflow_embeddings.npz && \
   rm /tmp/galaxy_ai_workflow_embeddings_sync.npz"
```

### Step 4 — Ensure the running Galaxy process actually reloads

`unified_workflow_search.py` uses **module-level singletons**
(`_WF_EMBED_MATRIX`, `_WF_EMBED_IDS`, `_WF_EMBED_READY`). Workers
already running hold the OLD matrix in RAM and will not pick up a
disk swap until the process restarts. The container runs Galaxy via
supervisord + galaxyctl, not gunicorn directly:

```bash
# Force a restart of the Galaxy service inside the container
sudo docker exec biomate-galaxy-dev bash -c \
  'supervisorctl -c /app/database/gravity/supervisor/supervisord.conf restart all' \
  2>&1 | tail -5

# Or, heavy-handed but always works:
sudo docker restart biomate-galaxy-dev

# Verify still up:
curl -sS -o /dev/null -w "%{http_code}\n" https://dev-public.biomate.ai/
curl -sS -o /dev/null -w "%{http_code}\n" https://dev-public.biomate.ai/galaxy/api/version
```

### What was done in this session (2026-06-13)

| Step | Result |
|---|---|
| Local DB rows vs prior `.npz` IDs | 4005 ↔ 4005, IDs match, **but DB mtime was 25 h newer** — content edits not reflected |
| Rebuilt locally (~67 s) | ✅ 4005/4005, `.npz` now newer than `.db` |
| Workstation backups kept | `.npz.bak`, `.npz.bak.20260613` |
| SCP to dev → docker cp into container | ✅ md5 `aa00df91e2de9f77c107c0d1b14267bf`, owner `galaxy:galaxy` |
| Found: container had **NO** `.npz` before this push | (lazy rebuild would have been the only source) |
| Galaxy reload | service still HTTP 200; full reload deferred to next sync / restart |

---

## 8. Open questions / TODOs

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
