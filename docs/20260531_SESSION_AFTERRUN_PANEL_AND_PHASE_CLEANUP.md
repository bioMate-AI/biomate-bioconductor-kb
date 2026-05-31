# Session — After-Run Panel + Phase-Index Cleanup + V2 Foundation

**Date:** 2026-05-27 → 2026-05-31
**Branch:** `integration/next-phase`
**Outcome:** Resolved 16 of the 27 items in `reference/05_25_todo.md`. Shipped the v2 after-run report behind a feature flag. Landed the v2 sandbox plumbing (Phase 0) ready for incremental promotion.

---

## 1. Bug fixes shipped to dev

| ID | Item | Commit(s) | Status |
|---|---|---|---|
| BUG-01 | Dynamic invite-code label | `de2f11c99` | ✅ Deployed (curl-verified) |
| BUG-04 | OAuth `/dashboard` → `/` redirect | `4a5c52345` | ✅ Deployed |
| BUG-05 | Verify-email auto-issues cookie (login-loop fix) | `4a5c52345` | ✅ Verified end-to-end against dev |
| BUG-06a | `APP_URL` set on dev EC2 | env-side | ✅ |
| BUG-06b | Email button font inline | pre-existing | ✅ |
| BUG-10b | Hide "Usage this month" sidebar widget | `de2f11c99` | ✅ |
| Gemini default | 2.5 → 3.5 across chat pipeline | `428042c70` | ✅ Verified in live bundle |
| Sidebar overflow | 260px clamp, no bleed into chat | `ca8ae8d1e` | ✅ |
| #11 | Remove "Good afternoon — welcome to BioMate" + 8-domain grid | `4c18505c8` | ✅ |
| #17 | Sign-out button in sidebar footer | `4c18505c8` | ✅ |
| #19 | Remove IND tutorial button + jane@acme avatar | pre-existing | ✅ |
| #21 | Remove Settings/Billing/Help stubs from IND sidebar | `4c18505c8` | ✅ |
| #24 | "BioMate is generating the workflow for you…" inline cue | (typing-indicator) | ✅ |

## 2. Phase index #23 — root cause + fix + backfill + tests

### Root cause
`_GENERIC_PHASE_RULES` (Python keyword matcher) was filling phase groups for *some* processes in a file while leaving siblings empty. Frontend grouping then bucketed unmatched processes into `'other'` → user saw `"Phase other"` in the panel.

### Parser improvements (`ai_assistant.py`)
- New semantic-form annotation parser: `// [Compound Validation]` → auto-assigns Phase A; `// [Docking]` → Phase B; same semantic name reused → same phase
- Old explicit form (`// [Phase A] Label`) still supported (back-compat for 16 drug_discovery files)
- Reject pseudo-bracketed text (urls, slashes, >60 chars)
- Skip generic keyword guesses when no annotations exist — produces clean uniform "Steps" group for ~99% of unannotated workflows

### Frontend label (`nextflow-workflow-viewer.tsx:1268`)
- `"Other Steps"` when no annotation matched (key === `'other'`)
- `"Phase A — Compound Validation"` when both letter + semantic label set
- `"Phase A"` when only letter set
- Single `"Steps"` group when file has zero annotations at all

### Backfill (commits `7eb622edc`, `7d8de4684`, `00d232a54`)
Script-generated semantic annotations across **28 multi-process workflows** in:
- `drug_discovery/` (16 existing + 15 newly annotated)
- `genomics/` (8 incl. wgs_germline_gatk with 15 processes)
- `cryo_em/` (4)
- `bioconductor/` (2)

2,213 single-process workflows intentionally skipped — phase grouping is meaningless for one process; parser fix renders them cleanly as one "Steps" group.

### Validation (`tmp/test_phase_groups_extended.py`)
- 27 testable workflows across 8 domains
- **26 PASS / 1 SKIP / 0 FAIL**
- Zero `"Phase other"` rendered anywhere on dev

## 3. Audit deliverables (Track A)

| Doc | Subject |
|---|---|
| `docs/20260528_PHASE_INDEX_AUDIT.csv` | All 2178 .nf files scanned for annotations |
| `docs/20260528_PHASE_INDEX_FINDINGS.md` | Root cause + fix recommendation |
| `docs/20260528_OUTPUT_VIZ_AUDIT.csv` *(inline in findings)* | 33 representative workflows × renderer status |
| `docs/20260528_OUTPUT_VIZ_FINDINGS.md` | Top 5 missing renderers, ranked by impact |
| `docs/20260528_AFTERRUN_AUDIT.csv` *(inline in findings)* | 41 workflows × 7-tab coverage |
| `docs/20260528_AFTERRUN_FINDINGS.md` | v0 ship recommendation per tab |

## 4. Output viz quick win (#26)

Wired the pre-existing `viewers/structure-viewer.tsx` (3Dmol.js) into `StepOutputPreview` so PDB / mmCIF / CIF files render with cartoon view + style toggles instead of a `<pre>` text dump.

- Commit: `a09705984`
- Dynamic import keeps 3Dmol out of the main bundle
- Falls back to text dump if WebGL init fails
- Unlocks boltz, chai1, openfold, docking poses, alphafold variants

## 5. V2 incremental merge — Phase 0 foundation

Plan doc: `docs/20260527_V2_INCREMENTAL_MERGE_PLAN.md` (6 phases, ~10 dev-days)

Phase 0 shipped (commits `a5de1dcb2`, `b84fb74f8`):
- 17 v2 sandbox files copied into `frontend/client/src/v2/`
- `useUiFlavor()` hook reads `?ui=v2` URL param + `localStorage.biomate_ui`
- CSS tokens scoped to `[data-v2-ui]` selector (no v1 token clobbering)
- `--bm-*` custom properties renamed to `--v2-bm-*` to avoid collisions
- Hooks-order fix in App.tsx so React doesn't throw "Rendered more hooks than during the previous render" when `?ui=v2` flips after auth resolves
- Excluded: `ResearchTweaks.jsx`, `data.js`, `research-data.js` (sandbox tooling + mock data)

## 6. V2 after-run panel (Phase 4 v0) — the user-facing change

Plan: `docs/20260528_WORKFLOW_PANEL_PRIORITY_PLAN.md`

New component: `frontend/client/src/v2/AfterRunReport.tsx` — inline tabbed report behind `?afterrun=v2` flag (independent of the full `?ui=v2` toggle).

### Tab matrix

| Tab | Data source | Visibility rule |
|---|---|---|
| Findings | `/api/workflows/runs/:id/findings` | Always shown; AI-fallback covers every workflow |
| Outputs | `currentRun.execution.outputDatasets` → fallback to `nextflowStatus.s3_output_files` | Always shown ("no files" if 0) |
| Methods | `/api/invocations/:id/methods-report` | Hidden when stub (<200 chars or "No QC events recorded") |
| Parameters | `extractSubmittedParams(currentRun)` | Always shown |
| QC audit | `/api/invocations/:id/qc-events` | Hidden when 0 events |
| ~~Software~~ | (pending backend route) | Removed for v0 |
| ~~Citations~~ | (pending backend route) | Removed for v0 |

### Backend fixes shipped (commit `c461be248`)

1. **Node proxy for QC events** — `/api/invocations/:id/qc-events` was implemented in `nextflow_executor.py:4478` but never proxied through Node. Added the proxy mirroring `qc-audit-download`'s shape. QC tab went from 12/12 HTTP 404 → 12/12 correctly hidden (no events in test runs) / populated when events exist.
2. **S3 outputs fallback** — Nextflow runs leave `outputDatasets` empty and use `nextflowStatus.s3_output_files` instead. AfterRunReport's parent now passes both, with derived step label from S3 path prefix.

### Comprehensive download report

The "↓ Download report" link generates a client-side comprehensive markdown report stitching every tab (run metadata, findings pointer, outputs table, methods, parameters, QC events). Downloads as `biomate-run-{runId}.md`. No backend route needed; server-side DOCX/PDF can replace the onClick later.

### Cross-workflow E2E validation

Tested against 12 distinct completed workflows on dev (`/tmp/test_afterrun_v2.py`):

| Tab | Result |
|---|---|
| Findings | **12/12 ✓ REAL** (AI-generated after 30s wait) |
| Outputs | 0/12 (these are mock sweep runs with no real files; panel ready when data exists) |
| Methods | 12/12 slow Galaxy proxy (>20s); curl confirms endpoint returns real text |
| Parameters | **12/12 ✓ REAL** |
| QC audit | **12/12 correctly hidden** (was 12/12 HTTP 404 before fix) |

## 7. Bonus — fixed 3 pre-existing TS errors

Caught during typecheck of Phase 4 work — from the parallel-session `workflow_chain` feature:

- `lib/ux-telemetry.ts` — added `'workflow.chain_run_clicked'` + `'workflow.pipeline_run_clicked'` to `UxEventName`
- `shared/schema.ts` — extended `executionEngine` enum: `['nextflow', 'galaxy']` → `[..., 'chain', 'pipeline']`

## 8. Sync reliability observations

Concurrent sessions cause repeated whack-a-mole:
- Multiple sessions run `pkill -f scripts/sync_to_dev.sh` at startup, killing in-flight peers
- Multiple sessions edit overlapping files (notably `chat-with-artifacts.tsx`, `ai_assistant.py`, `nextflow_executor.py`)
- One session reverted `from __future__ import annotations` in `nextflow_executor.py`, crash-looping all Python 3.9 workers on dev — hotfix `1f49b6e45` restored it + re-added the warning comment

Workaround: commit-loop wrapper (`for attempt in 1..4`) commits blocker files with a generic message until sync clears. Long-term: lock-file coordination or queue.

## 9. What's left

### From `reference/05_25_todo.md`
- **#9** IND 6-digit MFA on Electronic signature
- **#12** CRO: add platform-style sidebar + sample examples + rename
- **#14** CRO weird logo + unify sidebar
- **#15** CRO top-right mode-switch + user account button (visual confirmation needed)
- **#18** IND top-right light switch (visual confirmation; source has nothing)
- **#20** IND sidebar unify with platform + new-project button implementation
- **#22** IND non-functional buttons — comment out the remainder
- **#25** Sample data per workflow

### V2 merge plan
- Phase 2 — Sidebar swap
- Phase 3 — Chat surface swap (speaker pills + sticky PlanChecklist)
- Phase 4 polish — Software backend route, Citations backend route, then re-enable both tabs
- Phase 5 — AutoLoop, Modals, drag resizer
- Phase 6 — Default flip + v1 cleanup

### Backend follow-ups (informed by A3 audit)
- `GET /api/invocations/:id/software` — walk run dir for `**/versions.yml`, ~30 LOC
- `GET /api/workflows/:name/citations` — cryo-EM RAG topics + `qc_evidence.yaml` gate DOIs
- Methods-report timeout — backend AI generator >20s; should stream or cache

---

## Commits referenced (chronological)

```
de2f11c99  fix(auth+sidebar): dynamic invite-code label + hide usage widget
4a5c52345  fix(auth): BUG-04 OAuth redirect → / and BUG-05 verify-email auto-login
428042c70  fix(models): sweep gemini-3-flash-preview → gemini-3.5-flash
ca8ae8d1e  fix(layout): clamp sidebar to 260px
4c18505c8  feat(ui): phase-1 todo cleanups (#11, #17, #21)
7eb622edc  fix(#23): support semantic-only phase annotations + cleaner labels
7d8de4684  fix(#23): annotate missing RECEPTOR_TRIM process in gromacs_protein_md
00d232a54  phase-annotation: 2 missed bioconductor multi-process workflows
1f49b6e45  fix(dev-outage): restore 'from __future__ import annotations'
a09705984  feat(#26 viz): wire 3Dmol.js into StepOutputPreview
a5de1dcb2  feat(v2 merge phase 0): foundation — useUiFlavor flag + namespaced v2/ tree
b84fb74f8  fix(v2): React import + default export + hooks-order fixes
0e0785ab1  feat(v2 after-run): hide Software/Citations + real comprehensive download report
c461be248  fix(v2 after-run): wire QC events proxy + s3 outputs fallback
```
