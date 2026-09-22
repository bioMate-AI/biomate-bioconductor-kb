# Session handoff — 2026-09-22

Pause point for a fresh session. Covers what shipped, what's live on dev, open issues, and next steps.

## Live on dev now
Dev was synced (from the `feat/drugdev-reinvent4-realgen` worktree — a worktree of `/Users/kky/biomate`) at commit **`5e912642`**, health-gated, `result=healthy`. Running on dev and verified:
- **Chat-stream outage FIXED** (`routes.ts:6257` — guard `context` before assigning `datasetReferenceUnresolvedIds`). Verified live: `/api/chat/stream` streams `ready→…→final→done` on a plain message (was crashing on *every* message).
- **qPCR generalization** — accepts real user Ct tables (base-R 2^-ΔΔCt) not just the package example. Proven end-to-end: an uploaded Ct table ran to `completed` (RID `ea45b0de`).
- **Fix A (bioc no-input launch)** — `_build_bioc_entry_wrapper` binds a `.dat` placeholder for no-input single-list-slot runs instead of 422'ing. Validated: post-fix run `7c9dfd0a` reaches `running` where pre-fix runs failed at launch.

## Shipped this session (committed; PRs where noted)
- Hospital **instrument→BioMate resource inventory** (`docs/20260920_HOSPITAL_INSTRUMENT_RESOURCE_INVENTORY.md`).
- **Folder upload** (panel + chat drop, shared `lib/folder-drop.ts`) + **large-file cap 50→200 GB** with adaptive S3 chunking → **PR #226 / #228** (auto-merge armed).
- **BD decks EN + ZH** (Marp + PPTX) with real product screenshots (EN SaaS UI; ZH real on-prem `VITE_ONPREM=true` Chinese UI) + on-prem/local-LLM slide.
- **Hospital-instrument E2E** (`frontend/e2e/hospital-instruments.e2e.ts` + `...-upload.e2e.ts`) — routing/UX/upload/folder green for qPCR/flow/plate; dispatch arms added.
- **qPCR default sample data** (demo fallback) + **A4 owner-transfer UI** + **A5 FAERS generalize** + **B8 QC parsers**.
- **Systemic design doc** `docs/20260921_BIOC_SUBWORKFLOW_LAUNCH_SYSTEMIC_FIX.md` (Fix A + the re-scoped remainder).
- **Sample-data coverage** `docs/20260921_WORKFLOW_SAMPLE_DATA_COVERAGE.md`.

## Open issues / next steps (priority order)
1. **Bioc-container execution reliability (the live #1).** Bioc runs now *launch* (Fix A) but *don't reliably complete* — a run stuck `running` ~13 h (`fefa4723`). Likely the workflow's `BiocManager::install` deps-resolver re-installing/hanging even though the `bioconductor-*` container should ship the packages. **Next diagnostic:** SSM-read the Batch `.command.log` of a hung run → confirm install-vs-preinstalled. Fix: trust the container's packages (skip BiocManager fallback when `requireNamespace` succeeds) + hard time budget + orphan guard. Blast radius ~3,360 bioc subworkflows. Details in `20260921_BIOC_SUBWORKFLOW_LAUNCH_SYSTEMIC_FIX.md`.
2. **PR conflicts — resolution matters (won't affect current dev, but future syncs).** #238 (my branch), #218 (`integration/dev-test`) both CONFLICT into next-phase on the hot files carrying the load-bearing fixes: `nextflow_executor.py` (Fix A), `chat-input.tsx`, `lib/i18n.ts` (**add/add: my browser-detect vs next-phase's on-prem i18n — keep on-prem**), `app-sidebar.tsx`, `project-detail.tsx`. If merged with a wrong resolution and dev is later synced *from next-phase*, dev could REGRESS (lose Fix A / re-break chat). #217 is currently clean. **Recommend:** resolve #238 preserving Fix A + the chat-stream guard, taking on-prem `i18n.ts`.
3. **Flow-cytometry `.fcs` fixture** so its dispatch is testable (routing/panel already green).
4. Backlog: A3 GWAS→scRNA→eQTL coloc/PP4; A6 somatic chain; facility builds B1 (imaging readers) / B3 (MS raw→mzML) / B2 (pathology FMs); U1 real DeepVariant branch.

## Notes for the fresh session
- **This repo is a git WORKTREE** of `/Users/kky/biomate` (shared object store); ~10 sibling worktrees exist; the checked-out branch here churns as concurrent sessions `git checkout` in it. My commits land on whatever branch is current.
- **Sync discipline was reconciled in memory this session:** the sync decision is the user's — don't self-authorize from a task "y", don't over-refuse an explicit order; syncing from a worktree is fine when explicitly told. (`feedback_sync_from_nextphase_only` deleted; `pr_flow_not_direct_sync` + `deploy_process` updated.)
- One uncommitted file in the tree (`docs/20260912_onprem_llm/20260921_MIDTRAIN_MIXTURE_RUN_AND_EVAL.md`) belongs to a **concurrent session** — left untouched.
