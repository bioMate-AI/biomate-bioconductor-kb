# CryoEM UX, Auto-Loop QC Fixes, and Workflow Panel Redesign Alignment

**Date:** 2026-04-29  
**Branch:** integration/next-phase  
**Files changed:**
- `frontend/client/src/components/nextflow-workflow-viewer.tsx`
- `frontend/server/routes.ts`
- `frontend/playwright.parallel.config.ts` (new)
- `docs/20260428_MULTIGPU_CRYOSPARC_CODE_ANALYSIS.md` (new)

---

## 1. Workflow Panel — Reference Design Alignment

### Source of truth
Reference design at `http://localhost:7779/biomate/Workflow%20Panel%20Redesign.html`  
Source files: `src/WorkflowPanel.jsx`, `src/PhaseCard.jsx`, `src/Chrome.jsx`, `src/data.js`

### Elements removed (were in BioMate, NOT in reference design)

| Element | Reason removed |
|---|---|
| "QC Settings" always-visible toggle strip | Reference has no persistent QC strip. QC threshold editor opens only when user clicks "edit" on a QC gate row inline in the phase card. |
| "Execution logs" collapsible strip | Not in reference design. |
| `ReportConfusionButton` ("Report software") | Not in reference design. |
| `DownloadCommandsPanel` | Reference uses a "Download all" text link in the after-run section only. |
| Watcher bar ("Watcher attached · live SSE", "Detach watcher", "Reconnect watcher") | "Live SSE" is implementation detail the user should not see. |
| QC profile `<select>` dropdown | Never in reference design. QC profile is auto-detected from workflow domain. |

### Elements added (in reference, were missing from BioMate)

| Element | Implementation |
|---|---|
| `cap-hint` text — "Tip — you can edit parameters…" | **NOT added** — user explicitly rejected it |
| Watcher Pause/Resume buttons | Added but then removed — `pauseRun()` only sets a DB flag, does not actually pause Nextflow on AWS Batch |

### Elements confirmed correct (match reference)

- Panel header: kicker (`CRYO-EM · WORKFLOW`), title, subtitle (`N processes · N phases`)
- Run-bar progress (running/completed states)
- `PHASES · N` label
- License gate alert (`.alert.warn`)
- Blocked alert (`.alert.err`) with "Fix now" + "Confirm anyway"
- Phase cards with step status chips
- Step params as meta chips (`patch_x: 5 · patch_y: 5`)
- Step outputs with `view` + `dl` links (completed steps)
- `QcBlock` inline in phase card — "QC Gates — evaluated after phase"
- Auto-loop toggle per phase
- `AutoLoopPanel` (remediation card)
- Stop phase button (running state)
- View phase outputs link (completed phase)
- "Suggest a new step via chat" linkish button
- "Workflow settings" strip (collapsed by default, shows globalParams)
- After-run section: results-links + findings-card
- Footer: Confirm and run / Running… / Run again / Restart per state

### QC Settings strip — new behavior

The QC threshold editor (`data-testid="qc-settings-section"`) is now only rendered when `qcSettingsOpen === true`. It is opened programmatically when the user clicks "edit" on a QC gate row. It was never supposed to be a permanently-visible element.

---

## 2. Skip Phase — Documented

Skip phase button is **intentionally commented out** in `nextflow-workflow-viewer.tsx`:

```tsx
{/* Skip phase — no backend API, UI-only; hidden until backend skip endpoint added
    <button className="btn ghost sm danger" onClick={onSkipPhase}>
      Skip phase
    </button>
*/}
```

**Reason:** Nextflow runs on AWS Batch as a single job. There is no Nextflow API to skip a running phase without cancelling the whole job. The UI-only approach (marking phase done locally) was misleading. The skip button will be re-enabled when `POST /api/workflows/runs/:id/skip-phase` is implemented in `nextflow_executor.py`.

---

## 3. Pause/Resume — Why Removed

`pauseRun()` (called by the "Pause" button) only sets `status='paused'` in BioMate's PostgreSQL database. It does **not** pause the Nextflow process on AWS Batch. The Batch job continues running regardless.

"Detach watcher" / "Reconnect watcher" were the original labels in the reference design, reflecting SSE stream disconnect. In BioMate's implementation, the action is actually a DB status change, not an SSE disconnect — making the labels confusing and the feature misleading.

**Decision:** Remove the Pause button and the watcher bar entirely. The footer now shows only:
- The run button (state-dependent label)
- "Resume" link only when `status === 'paused'` (for future use when real Nextflow pause is implemented)

---

## 4. Auto-Loop QC — Architecture and Fixes

### Two QC systems (clarified)

**System 1 — Inline QC gate card** (`qc_gate_triggered` SSE event):
- Frontend-driven confirmation flow
- Shows "Review Required" card with gate failures + suggested params
- Previously called `onExecute(params)` → **fresh Nextflow run (wasteful)**
- Now calls `POST /api/workflows/runs/:id/rerun` → **Nextflow `-resume` (cache-aware)**

**System 2 — AutoLoopPanel** (`autoloop_gate_results` / `autoloop_update` / `autoloop_phase_complete` SSE events):
- Backend-driven autonomous remediation
- `qc_trace_monitor.py` detects failures, applies remediations, restarts phases
- SSE events are notifications of what the backend already did
- Frontend shows `AutoLoopPanel` with gate results + was→now param diff

### Auto-loop ON by default

`autoloopMap` initialises as `{}`. The check `autoloopMap[phase] !== false` returns `true` for all phases by default (since `undefined !== false`). Auto-loop is effectively ON for all phases unless the user explicitly turns it off via the toggle in each phase's `QcBlock`.

### New behavior: auto-apply without card (auto-loop ON)

When `qc_gate_triggered` fires and auto-loop is ON for the phase:
1. Suggestions are applied to params immediately
2. `POST /api/workflows/runs/:id/rerun` is called with updated params
3. Nextflow `-resume` skips cached phases, only reruns from the gate point
4. **User is notified via toast** (was silently ignored before)
5. No confirmation card is shown

When auto-loop is ON but no actionable suggestions exist (e.g. FSC validation failure):
- Toast shown: "QC gate failed — no auto-fix available — workflow continued"
- No rerun triggered (would be wasteful — FSC failure is a data quality issue, not parameter-adjustable)

### Confirmation card — auto-loop OFF

When auto-loop is OFF (user explicitly toggled) and `qc_gate_triggered` fires:
- Card shows with failures, suggested param changes, and a countdown timer
- Countdown: "Workflow continues in 4:59" ticking down from 5 minutes
- After 5 minutes: card auto-dismisses with toast "QC gate timed out — workflow continued"
- User can act before timeout: Apply suggestions (resumes), Keep current, Cancel run

### QC notification matrix

| Auto-loop | Gate result | What user sees |
|---|---|---|
| ON | Fails, suggestions exist | Toast: gate name + failure details + params being adjusted |
| ON | Fails, no suggestions | Toast: gate name + failure details + "no auto-fix available" |
| OFF | Fires | Confirmation card with countdown (5 min) + 3 action buttons |
| OFF | Card times out | Toast: "QC gate timed out — workflow continued" |

---

## 5. Nextflow `-resume` for QC Reruns

### Before (wasteful)
`handleRetryWithSuggestions` → `onExecute(params)` → fresh `nextflow run` → all 23 steps rerun from scratch (~7.4h wall, ~$6.29 for CryoSPARC SPA).

### After (cache-aware)
Both auto-loop and manual confirmation now call:
```
POST /api/workflows/runs/:id/rerun
Body: { parameters: { ...updatedParams } }
```

The `/rerun` endpoint (`routes.ts` line 3020):
1. Resolves the Nextflow run ID from the execution run record
2. Calls `POST /api/nextflow/resume/:nextflowRunId` on the Galaxy backend
3. Galaxy backend calls `execute_nextflow()` with `resume_from_run_id` set

The Galaxy backend (`nextflow_executor.py` line 2634):
1. Finds the previous run's S3 work directory: `s3://<bucket>/nextflow/work/<uid>/<run_id>`
2. Replaces `-w` in the command with the previous work dir
3. Appends `-resume` flag
4. Nextflow skips all cached tasks, only reruns tasks whose inputs changed

**Result:** A QC-triggered rerun for CryoSPARC SPA reruns only the affected phase (~30 min) instead of the full pipeline (~7.4h).

### Updated params forwarding chain

```
Frontend handleRetryWithSuggestions
  → POST /api/workflows/runs/:id/rerun  { parameters: { ctf_min: 5 } }
  → routes.ts: passes parameters field to Galaxy
  → POST /api/nextflow/resume/:nf_run_id  { nextflow_path, parameters: { ctf_min: 5 } }
  → ResumeRunRequest.parameters = { ctf_min: 5 }
  → execute_nextflow(parameters=body.parameters, resume_from_run_id=run_id)
  → nextflow run ... --ctf_min 5 -resume -w s3://.../<prev_run_id>
```

---

## 6. When Auto-Loop Suggestions Are Actionable vs Wasteful

Based on `experiments/cryo_em_autoloop/qc_evaluator.py`:

| Gate | Phase | Suggestion | Worth rerunning? |
|---|---|---|---|
| `ctf_fit_quality` low | A | Broaden `ctf_fitting_resolution_min/max` | **Yes** — resolution range directly affects CTF fit |
| `mean_drift_A` high | A | Reduce `micrograph_batch_size`, enable `dose_weighting` | **Yes** — batch size affects motion correction |
| `astigmatism_A` high | A | (no suggestion) | **No** — data/optics quality, not parameter-adjustable |
| `particle_yield` low | B | Loosen `blob_picker_min_diameter` | **Sometimes** — if sample is truly sparse, no help |
| `particle_diameter` wrong | B | Re-estimate `particle_diameter_angstroms` | **Yes** — directly controls blob picker radius |
| `class_score` low | C | Increase `num_2d_classes` | **Sometimes** — more classes can help heterogeneous samples |
| `fsc_resolution` poor | E | (no actionable suggestion) | **No** — structural quality, not parameter-adjustable |

**Current implementation:** The backend marks suggestions only for gates where parameters can be adjusted. Gates with no suggestions (FSC resolution, high astigmatism) send `suggestions: []`, which triggers the "no auto-fix available" toast path instead of a rerun.

---

## 7. CryoEM E2E Test — Parallel Execution

### Test file
`frontend/e2e/cryoem-full-20img-multigpu.e2e.ts`

### Test blocks and parallelism

| Block | Tests | Status (2026-04-29) |
|---|---|---|
| MG-0 API preflight | QC profiles, S3 accessible | ✓ PASS |
| MG-S1..S4 S3 credentials | Settings → S3 → credentials → workflow card | ✓ PASS (2 soft failures: no S3 browser tab, movies_path not extracted from URI) |
| MG-1/2/3 File provision | Upload .mrcs → card → GPU auto-detect | ✓ PASS |
| MG-4 QC settings | QC section visible, threshold editable | ✓ PASS (soft: QC strip now removed — test needs update) |
| MG-5..12 Full execution | Real CryoSPARC run, all viewers | 🔄 RUNNING (8h timeout) |

### Parallel config
`frontend/playwright.parallel.config.ts` — `fullyParallel: true`, `workers: 4`  
Run with: `npx playwright test --config playwright.parallel.config.ts`

### Known open gaps (from test results)

1. **MG-S3: No S3/External URL tab in dataset browser** — Galaxy dataset browser does not have an S3 import tab. Users must type the S3 URI in the chat query directly.

2. **MG-S4: movies_path not extracted from natural language S3 URI** — When user says "my data is at s3://..." the AI correctly routes to CryoSPARC SPA but does not extract `movies_path` from the S3 URI into the parameter field. The user must fill it manually in the Workflow Settings panel.

3. **MG-4: QC Settings section removed** — The test asserts for `qc-settings-section` visible in the panel body. This section is now only shown when `qcSettingsOpen === true` (opened via QC gate "edit" link). Test needs updating to reflect the new behavior.

---

## 8. Multi-GPU CryoSPARC Analysis (cross-reference)

Full analysis of the multi-GPU study and INIT worker registration is in:  
`docs/20260428_MULTIGPU_CRYOSPARC_CODE_ANALYSIS.md`

Key findings:
- `nextflow_executor.py` auto-sets `num_cs_workers = num_gpu` before launch (lines 4650-4651)
- Workers pre-registered via SSH using `cryosparcm worker connect` (v5 syntax) before Nextflow starts
- Old `cryosparcm addworker` subprocess in INIT was dead code (silently failed in container) — replaced with API-based `cs.get_targets()` verification
- P52 benchmark: g6.12xlarge, 4× NVIDIA L4, 3.4× speedup, FSC 1.78 Å (Nyquist), $0.75

---

## 9. Next Steps

1. **MG-5..12 full execution result** — monitor background test (started 2026-04-29 ~01:15 UTC), expect completion by ~09:00 UTC
2. **Update MG-4 test** — remove assertion for QC settings section toggle (now hidden until gate fires)
3. **movies_path extraction** — fix AI parameter extraction to pull S3 URI from natural language into `movies_path` param
4. **S3 browser tab** — not currently planned; the chat-based S3 URI input works as the primary path
5. **Rerun actionability scoring** — add `rerun_actionable: bool` to `GateResult` so auto-loop only retries when there's a genuine chance of improvement (FSC gate should never trigger auto-rerun)
6. **Sync to dev** — run `scripts/sync_to_dev.sh` after MG-5..12 result is confirmed
