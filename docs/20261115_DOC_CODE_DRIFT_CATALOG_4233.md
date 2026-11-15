# 2026-11-15 — doc-code-drift catalog count green (4,233)

## Failures (pre-sync vitest)

`server/doc-code-drift.test.ts` — 3 failed / 3994 passed elsewhere:

1. `live DB holds exactly 4,223 workflows / 42 domains / 70 chains` — local DB had **4200** workflows
2. `the documented November Vina chain exists…` — `vina_virtual_screening_bench` missing
3. `no agent-facing file quotes a stale count that matches the LIVE workflow total` — `tools_manifest.py` hard-codes `4,200+ indexed workflows`, which matched the stale local total

## Root cause

This worktree’s `backend/database/galaxy_ai_tools.db` was the smaller **4,200**-row copy (same class as `biomate` main), not the intended **4,233** catalog used on panelfix/review/DEV (`docs/20261113_INPUT_KINDS_ENRICHMENT_DIAGNOSIS.md`). The drift guard correctly refused to treat that copy as truth.

## Fix

1. Restored local DB from the intended catalog (`biomate-deploy-panelfix` / `biomate-review`, md5-identical, integrity ok, includes `vina_virtual_screening_bench`).
2. Updated `frontend/server/doc-code-drift.test.ts` and `CLAUDE.md` ground truth **4,223 → 4,233**.

DB is gitignored; code/docs commit carries the equality guard only. Sync remains `BIOMATE_SYNC_DB=0` unless an explicit catalog upload is intended.
