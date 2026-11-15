# 2026-11-15 — Models panel + Optimise/DMTA UX improvements

**Decision:** Phase 0 **(A) Wire** — recorded in `docs/20261115_MODELS_TEST_AND_FIX_PLAN.md`.  
**Branch tip at restore:** `a5ace834ed` (`sync/pr398-onto-dev`; prior claim verified against `5cfdc43f84`).

---

## Restore note (why the work “vanished”)

| Finding | Detail |
|---------|--------|
| **Cause** | Uncommitted Option A UX was **`git stash`ed** as `stash@{0}: wip: Models DMTA honesty (exclude from coldstart Commit A sync)` so a cold-start Commit A sync would not carry it — then never re-applied. |
| **Not lost forever** | Stash parents: index `5cfdc43f84` + WIP tree + **untracked** `dmta-rounds.tsx`, this doc, and `MODELS_TEST_AND_FIX_PLAN.md` on `stash@{0}^3`. |
| **False “docs-only”** | A later interrupt agent rewrote this file as a verification note claiming “no Models UX on disk” while the real code sat in stash — verification was correct for the working tree, wrong as a “never implemented” verdict. |
| **This turn** | `git stash apply stash@{0}` restored tracked diffs; untracked files checked out from `stash@{0}^3`. Then **assay ingest + virtual-library seed** + multipart proxy fix were added so first propose is not stuck empty/422. |

---

## What changed (Option A)

### P0 — Trust / DMTA

| Area | Before | After |
|------|--------|-------|
| Models Molecular → Rounds | Empty “start a loop” copy, **no** controls | Honest empty + **Create / Start / Stop / Propose** via `/api/drug-discovery/{id}/retrain/*` + create campaign (`campaign_id` = project id) |
| Create campaign | N/A | Also seeds Train-split BACE assays (`ingest-assay`) + `candidate_library` → `virtual_library_smiles` from cold-start loop fixtures |
| Multipart ingest proxy | Wildcard skipped multipart body (empty upload) | Dedicated `POST /api/drug-discovery/:id/ingest-assay` (multer → Galaxy FormData), same pattern as IND attachments |
| Chat Optimise | `template_reuse` → `reinvent4_lead_design` | `isDmtaLoopQuery` → deep-link `/models?tab=molecular`; **no** invent4 card |
| Galaxy generate safety net | Generative path could invent4 “design…series” | `_is_dmta_loop_task` refuses reinvent4_lead_design |
| Dead CRO links | `/drug-discovery-cro` | Retargeted to Models Molecular Rounds |

### P1 — Panel clarity

- Purpose lines under tab titles; honest genomic/chemical empties; Chemprop GNN on Molecular; sparse Bayesian/budget hints only.

### P2 — Cold-start honesty

- `loop` bundle context: Models Rounds / campaign APIs, not invent4.

---

## Files on disk (verify before claiming done)

| Path | Role |
|------|------|
| `frontend/client/src/components/models/dmta-rounds.tsx` | Rounds create/start/stop/propose UI |
| `frontend/client/src/components/models/dmta-loop-fixtures.ts` | BACE→ingest CSV + library SMILES + seed helper |
| `frontend/client/src/components/models/models-panel.tsx` | `tabIndexFromSearch`, RoundsSection wire |
| `frontend/server/routing-authority.ts` | `isDmtaLoopQuery`, `MODELS_DMTA_HREF` |
| `frontend/server/galaxy-assistant.ts` | Optimise early-return + CRO retarget |
| `frontend/server/routes.ts` | Dedicated ingest-assay multipart proxy |
| `backend/lib/galaxy/ai/ai_assistant.py` | DMTA loop refuse reinvent4 |
| Locales en/zh `models.*` | Controls + seeded success copy |

---

## Test table (this turn)

| Check | Result | Notes |
|-------|--------|-------|
| `./node_modules/.bin/tsc --noEmit -p .` | **PASS** | `/tmp/biomate_models_tsc.log` |
| Focused vitest (8 files) | **PASS** 386/386 | models, models-i18n, training-launcher, training-logic, dmta-loop-fixtures, cold-start-dashboard, cold-start-demo-catalog, routing-authority |
| Assert Optimise ≠ reinvent4 | **PASS** (unit) | `isDmtaLoopQuery` true on Optimise seeds; false on generative; Galaxy early-return / `_is_dmta_loop_task` |
| Assert CRO URL retargeted | **PASS** (unit) | `MODELS_DMTA_HREF === '/models?tab=molecular'`; not `drug-discovery-cro` |
| Assert Rounds has controls | **PASS** (unit) | `optimise-create-campaign` / start / stop / trigger in `models.test.tsx` |
| Assert Chemprop on Molecular | **PASS** (unit) | `MOLECULAR` includes `chemprop_gnn` |
| Assert fixture seed mapping | **PASS** (unit) | Train-split only; `virtual_library_smiles` (not `smiles`) |
| `PYTHONPATH=lib python3.9 -c "import galaxy.ai.ai_assistant"` | **PASS** | |
| Files exist on disk | **PASS** | `dmta-rounds.tsx`, `dmta-loop-fixtures.ts` present |

---

## Residuals

- DEV remasure of Optimise seeds after sync (chat must not return reinvent4_lead_design card).
- Live propose/refit against Galaxy + seeded campaign (unit covers client seed path; not a Batch run).
- Literal `dataset=s3://` remasure still depends on earlier `_withS3Uri` sync.
- CRO Library page remains commented out (out of scope).
- Design-module “Optimise properties · one pass” unchanged (out of scope).

## Related

- Plan: `docs/20261115_MODELS_TEST_AND_FIX_PLAN.md`
- Cold-start audit: `docs/20261115_COLDSTART_MODELS_MODULE_AUDIT.md`
