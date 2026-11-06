# Main-merge plan — reunify the data-centric fork with `integration/next-phase`

**Date:** 2026-10-01
**Goal:** end the branch fragmentation so dev serves ONE canonical branch and `main` has the flagship data-centric program.

## The situation (why this is needed)

The entire data-centric / Models / Design&Generate / Instruments program was built on a fork that split from `integration/next-phase` (MAIN) on **2026-09-04 and was never merged back**. MAIN advanced **+123 commits** independently. The fork's newest, consolidated head is **`integration/consolidated-20261001`** (data panel + Models + Design&Generate + peptide-pharma refinements + instruments + navigable-lineage + launch-from-dataset), which is **1024 ahead / 123 behind** MAIN. Dev currently serves the consolidated branch via a working-tree sync; nothing is merged to MAIN, so any session syncing a different branch regresses dev (the "whack-a-mole").

## The merge: 11 conflicts, 4 of them HIGH-RISK (backend .py)

`git merge-tree origin/integration/consolidated-20261001 origin/integration/next-phase` → 11 conflicted files:

**HIGH-RISK — core backend Python (a bad resolution = Galaxy crash-loop):**
1. `backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py` — run execution / `_runs[]` / RunStateStore. Both sides heavily evolved.
2. `backend/lib/galaxy/ai/llm_client.py` — LLM provider client.
3. `backend/lib/galaxy/ai/billing/api/billing_router.py` — billing (MAIN merged PR #253 billing-galaxy-db fix).
4. `backend/lib/galaxy/jobs/qc_trace_monitor.py` — QC trace monitor.

**Frontend (lower-risk, but review):**
5. `frontend/client/src/components/app-sidebar.tsx`
6. `frontend/client/src/components/chat-input.tsx`
7. `frontend/client/src/lib/i18n.ts` (add/add — likely the i18n-full-coverage work on MAIN vs fork)
8. `frontend/client/src/pages/project-detail.tsx`
9. `frontend/server/galaxy-assistant.ts`
(+ 2 more content conflicts)

## Required execution procedure (do NOT shortcut — see [[feedback_merge_conflict_marker_trap]])

1. In a **dedicated worktree** off `integration/consolidated-20261001`, create `integration/mergemain-20261001` and `git merge origin/integration/next-phase`.
2. Resolve **one conflict at a time**, understanding BOTH sides (123 MAIN commits incl. PR #253 billing, i18n coverage, any nextflow_executor changes vs the fork's RunStateStore/data-centric work).
3. Before committing: `git diff --name-only --diff-filter=U` must be empty; `grep -rn '^<<<<<<<\|^>>>>>>>\|^=======$' backend/ frontend/` must be clean (NEVER `git add -A` after a conflicted merge — markers in .py crash-loop Galaxy).
4. **Backend gate:** `cd backend && PYTHONPATH=lib python3.9 -m compileall lib/galaxy/webapps/galaxy/api/nextflow_executor.py lib/galaxy/ai/llm_client.py lib/galaxy/ai/billing/api/billing_router.py lib/galaxy/jobs/qc_trace_monitor.py` + import-check each module (PEP 604 union on 3.9 is a known crash — [[project_dev_outage_patterns]]).
5. **Frontend gate:** `cd frontend && npx tsc --noEmit -p . && npx vitest run` (both green).
6. Deploy via `scripts/sync_to_dev.sh` (FULL, not frontend-only — the backend merged too) and let the **health-gate + smoke test** verify; it auto-rolls-back on failure.
7. Open a PR into `integration/next-phase` for review (a reviewer should see the 4 backend resolutions). Do NOT push directly to the shared `integration/next-phase` (blocked as a shared resource, and it warrants review).

## Recommendation

This is a **deliberate, reviewed integration task**, not an automated grind — the 4 backend conflicts are load-bearing and span a 123-commit divergence. Best done in a focused session (or by the owner of the MAIN-side changes), following the procedure above. The groundwork is laid: the consolidated branch is the complete, verified-on-dev superset; the conflict set is small (11) and enumerated here.

## Status of the rest (already done, 2026-10-01)
- Consolidated branch built, pushed, **deployed + verified live on dev** (data panel restored, navigable lineage, launch-from-dataset, instruments, Models, Design&Generate).
- Data-centric feature backlog remaining (post-merge): version compare/restore, access-scope enforcement, model trust labels + held-out metrics, peptide/protein generators, accept/reject AI-diff. See `docs/` audit notes.
