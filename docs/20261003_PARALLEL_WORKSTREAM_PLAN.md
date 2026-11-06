# Parallel workstream plan (post codex/cursor handoff)

**Date:** 2026-10-03
**Owner:** single agent (codex + cursor retired; this session now drives all threads)
**Baseline verified healthy:** frontend `tsc` exit 0; fabrication guard PASS; no conflict markers in deployable code; executor parses; mock dashboard removed; MCMICRO claim corrected.

## Operating rules for all parallel work
1. **No cloud/Batch compute** is dispatched by any thread without explicit per-run approval (scientific-validation runs are gated per `docs/20261003_SCIENTIFIC_VALIDATION_AND_TEAMWORK_FOLLOWUP.md`). Threads do only buildable/code work + local checks.
2. **No `sync_to_dev.sh`** from a worker thread. Each thread **commits** its logical changes (commit-immediately). Deploys are serialized by the owner after an audit-gate review (the sync lock + 307MB DB push can't run concurrently).
3. Follow CLAUDE.md: no fabrication (RNG→output), honest demo labels, pre-sync checks before any eventual deploy, docs to `docs/`, never the Artifact tool, never `git add -A` after a conflicted state.
4. Each thread writes/updates a dated doc in `docs/` with what it changed + how it was verified.

## Thread A — UX: wire live run-progress (TOP priority per UX directive)
- **Gap (verified):** backend `/api/workflows/{id}/realtime/status` exists (+ Node proxy `routes.ts:4426`), aggregating step/QC/autofix/log/resource state, but **no frontend calls it**; the run panel shows per-step status only, no aggregate progress/logs/autofix; top progress bar was removed. See `docs/20260310_EXECUTION_TRACING_UX_GAPS.md` (Gaps 1–4).
- **Scope:** `frontend/client/src/components/nextflow-workflow-viewer.tsx` (+ a small polling hook if needed). Poll `/realtime/status` while a run is active; surface overall progress, current phase/step, elapsed time, and (collapsible) recent log lines + autofix state. Respect existing `data-status` test hooks. **Do NOT touch `frontend/server/routes.ts`** (proxy already exists).
- **Validate:** `tsc` + vitest; a Batch run to see live progress is deferred to owner (compute-gated).

## Thread B — Team workspace Phase 1: immutable project activity ledger
- **Per** `docs/20261003_TEAM_WORKSPACE_IMPLEMENTATION_PLAN.md` Phase 1 (foundation for invitations/shared-chat/notifications).
- **Scope:** new migration `frontend/migrations/00XX_project_activity.sql` (append-only `project_activity` events: membership change, file upload/delete, run launch/terminal, plan create — with actor, project, type, payload, ts); emit events from the existing project/run mutation points in `frontend/server/project-routes.ts` (+ run lifecycle); a read endpoint `GET /api/projects/:id/activity` (owner-or-member). **Owns `project-routes.ts` edits** (Thread A will not touch server routes). Add a server test.
- **Validate:** vitest (server) + the existing 52-test team suite still green; no dev run.

## Thread C — Pathology: narrow RUO H&E/IHC WSI preprocessing + nuclei segmentation
- **Per** `docs/20261003_PATHOLOGY_WSI_CAPABILITY_AUDIT.md` "Recommended first deliverable."
- **Scope:** ONE new, honestly-scoped Nextflow workflow under `backend/biomni_workflows/nextflow_nfcore/subworkflows/pathology/wsi_he_nuclei_segmentation/` — accept one WSI format + OME-TIFF (OpenSlide), deterministic tissue tiling with coordinates + basic image QC, one pinned segmentation model (Cellpose or StarDist — license-reviewed, real container), emit tile masks + stitched overlay + cell table + QC summary + model/version manifest + a "research-use-only / pathologist review required" report. **No fabrication; honest-fail if deps/inputs absent.** Pick a license-clean quay/biocontainer; set the process `container` directive (not just DB). Register the DB row `executable=0` until validated (owner runs validation later).
- **Validate:** `.nf` DAG preview / python ast parse; container existence check (read-only, no run). Real Batch validation on a licensed annotated slide is owner-gated.

## Thread D — Scientific validation: CLOSE the known failures (code only, no runs)
- **Per** `docs/20261003_SCIENTIFIC_VALIDATION_AND_TEAMWORK_FOLLOWUP.md` §1 execution order step 1 ("close known failures before launching more compute").
- **Scope — fix the code causes, do NOT dispatch runs:**
  - Metabolomics: the recorded **API-drift failure** in the MetaboAnalystR/xcms path (`docs/20260923_DOMAIN_VALIDATION_RESULTS.md` records the real failure) — find + fix the drifted API call.
  - Spatial: the **documented missing-container dependency** — identify the missing dep + wire the correct container (directive + DB), honest-fail guard.
  - ChIP-seq: launches **did not reach peak calling** — diagnose why the pipeline stops before MACS2/peak step; fix the gating/stage.
- **Validate:** read the real failure evidence first (CLAUDE.md "read the full error"); fix at root cause; local ast/compile/DAG checks only. Leave each as "fix applied, awaiting owner-approved validation run."

## Serialization / integration (owner)
After threads report: audit-gate each diff (no fabrication, no markers, tsc/vitest green, ast OK), then deploy in order **D → B → A → (C DB row only)** via a single `sync_to_dev.sh` batch, then request approval for the compute-gated validation + progress + pathology runs.
