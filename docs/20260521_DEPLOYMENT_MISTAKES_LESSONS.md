# Deployment Mistakes — Session 2026-05-21

**Purpose:** record concrete deployment mistakes from this session so future-Claude reads this BEFORE deploying anything. Each mistake includes: what I did wrong, what the symptom was, why it took so long to detect, the root cause, the permanent fix.

---

## Mistake 1: Wrong import path (works locally, silently fails on dev)

### What happened
I wrote production-path imports as `from backend.lib.galaxy.ai.retrievers.wired_recommender import …` — which works locally where PYTHONPATH includes the repo root, but **fails on the dev container** where PYTHONPATH is `/app/lib` (so the same module is `galaxy.ai.retrievers.wired_recommender`).

### Symptom
Locally: all 195 tests pass.
On dev: the wired class wasn't being used; raw FTS results came back unprioritized. But this was invisible — the try/except fallback silently caught the ImportError and used the base class.

### Why it took so long to detect
Two compounding factors:
1. The try/except fallback caught the ImportError silently, so no error surfaced anywhere.
2. The local tests passed because local PYTHONPATH was different from dev's. There was no test exercising the **container-equivalent** import path.

### Root cause
**Two different import roots in the codebase that I treated as one.** BioMate runs from PYTHONPATH=`/app/lib` in the container; my local tests ran with PYTHONPATH=`.`. The same module has two different dotted-path names depending on which root.

### Permanent fix
- Always use `galaxy.*` imports (the container-truth path), never `backend.lib.galaxy.*`.
- The silent try/except fallback for the wired import should LOG AT WARN level so the mismatch surfaces in `gunicorn.log`. Updated this session.

---

## Mistake 2: Imported from sandbox/, which isn't synced to dev

### What happened
`procedure_widener.py`, `knowledge_recall.py`, and `wired_workflow_search.py` did `from sandbox.intent_retrieval_v3.adapters.entity import …` and `from sandbox.workflow_search_v2.library.workflow_intent import …`. These work locally because `sandbox/` is in the repo root. They fail on dev because `sync_to_dev.sh` only syncs `backend/lib/**/*.py` — it never copies `sandbox/`.

### Symptom
The wired classes were "imported successfully" but their behavioral upgrade was silently skipped — once again caught by try/except.

### Why it took so long to detect
1. Same silent-fallback pattern.
2. I only validated the imports via local tests where sandbox/ exists.
3. I didn't verify the data-loading pathway on dev itself — only verified the class identity, which is misleading.

### Root cause
**Different deployment surface between sandbox/ and backend/.** I treated `sandbox/` as if it were synced. It isn't. Anything imported from sandbox/* will silently fail in production.

### Permanent fix
- Promoted the four files into `backend/lib/galaxy/ai/retrievers/` (production-path) — done this session.
- Promoted the two YAMLs into `backend/config/` — done this session.
- Updated `.gitignore` to track new YAMLs — done this session.
- **Rule for future-self:** anything imported by a production-path module MUST live in `backend/lib/` or `backend/config/`. Never import from `sandbox/`, `experiments/`, or `evaluation/` from production paths.

---

## Mistake 3: sync_to_dev.sh blindly overwrites dev's universe.sqlite

### What happened
1. Earlier, the user (and/or I) applied alembic migration `204367c6a604` on the dev container, bringing the dev DB up to date with the deployed code.
2. I then ran `sync_to_dev.sh` again (to push the webapp endpoint wiring patch).
3. The sync script uploads my **local** `backend/database/universe.sqlite` (which is still at the older version `3af58c192752`) via S3 to dev.
4. The dev container's `universe.sqlite` was overwritten with the older one.
5. On next gunicorn restart, the migration error returned: "DB v3af58c192752 but code expects v204367c6a604."

### Symptom
Container is unhealthy, gunicorn workers crash in an exit-1 restart loop, `/api/version` returns HTTP 000. Same exact error as the original migration failure — but appeared AFTER it had been "fixed."

### Why it took so long to detect
I didn't realize sync_to_dev.sh syncs the DB by default. I assumed it only synced .py files. Looking at the script earlier showed it does:

```bash
upload: backend/database/galaxy_ai_tools.db to s3://...
upload: backend/database/universe.sqlite to s3://...
```

The DB sync is part of the layered sync.

### Root cause
**My local DB is older than the dev DB after the migration. Any sync from me will downgrade dev.** This is structural — I either need to:
1. Keep my local DB up to date (apply the same migrations locally), OR
2. Stop syncing the DB at all (the sync script needs a `--skip-databases` flag, or I need to short-circuit that layer), OR
3. Use a different DB sync direction (dev → local, not local → dev).

### Permanent fix (this session)
- Apply the migration to my LOCAL `backend/database/universe.sqlite` so future syncs from me are no-ops or upgrades, not downgrades.
- Document a guard in `sync_to_dev.sh`: refuse to upload `universe.sqlite` if local alembic version is BEHIND the dev/S3 version. (Not implementing this guard right now — that's a separate change requiring AWS S3 metadata lookup or pre-sync probe.)

---

## Cross-cutting failure mode: silent try/except fallback

All three mistakes were AMPLIFIED by `try: import X; except: fallback = base`. The fallback worked locally so my tests passed; it failed silently on dev so I couldn't see the problem until I explicitly checked class names + behavior.

**Rule for future-self:** When the only purpose of a try/except is to handle an environment-specific import, log at WARN level inside the except so the failure surfaces in production logs. Don't just silently degrade.

Updated this session for `agent.py` and `ai_assistant.py` — the except blocks now `log.warning(...)`.

---

## Detection pattern that should have caught all 3

Before claiming "wired in production," I should have run **this exact verification on dev**:

```bash
docker exec biomate-galaxy-dev python3 -c "
import sys; sys.path.insert(0, '/app/lib')
from galaxy.ai.workflow_ops.autofix.agent import ToolParameterRecommender
from galaxy.ai.ai_assistant import UnifiedWorkflowSearch
assert ToolParameterRecommender.__name__ == 'WiredToolParameterRecommender'
assert UnifiedWorkflowSearch.__name__ == 'WiredWorkflowSearch'
# Also verify a real call exercises the wired logic, not the base:
r = ToolParameterRecommender(db_path='/app/database/galaxy_ai_tools.db')
import os; os.environ['BIOMATE_FAMILY_PRIORITIZE'] = '1'
out = r.search_tools('samtools', limit=10)
assert out[0].name == 'Samtools sort', f'wired path not active: got {out[0].name}'
print('OK')
"
```

If this passes, the wiring is real. If any assertion fails, the wiring is broken regardless of what the local tests say. **This must be the gate** before declaring "in production."

---

## Process changes for future sessions

1. **Production-path imports only.** Never `from backend.lib.*` or `from sandbox.*` inside a file that lives in `backend/lib/`. Use `from galaxy.*`.
2. **Promote sandbox → backend before relying on it.** Any sandbox file imported by a production-path file must be moved to `backend/lib/` (and `.gitignore` updated for YAMLs).
3. **Silent fallback = log.warning.** Every `except: x = base` must log the reason so the degradation is visible in production logs.
4. **Verify on dev, not just locally.** Class identity check + one functional smoke test on the actual dev container, BEFORE declaring "in production."
5. **DB sync awareness.** Before any sync, check whether `backend/database/universe.sqlite` would downgrade dev. If yes, migrate locally first.

If I keep relying on local-only verification, I will keep shipping things that are silently broken in production.
