# Audit — Output access channels, project/chat model, Galaxy semantics, run comparison, experimental harness

**Date:** 2026-06-19
**Audience:** product + engineering — answers the user's 9-question audit on what BioMate's output / project / experiment model actually is today (vs Galaxy, vs what users expect)
**All claims grounded in code; nothing invented.**

## 1. Output access channels — 7 paths, **2 carry real concerns**

| # | Channel | Code path | Status | Concerns |
|---|---|---|---|---|
| 1 | Outputs tab in After-run report | `/api/runs/:id/output_files` → `AfterRunReport.tsx OutputsTab` | ✅ shipped | none |
| 2 | Inline file preview by extension | `step-output-preview.tsx` dispatches image/html/table/sequence/vcf/structure/text/density/annotation | ✅ shipped | none |
| 3 | Per-file presigned-S3 download | `routes.ts:3116/3131/3377` writes `s3_uri` + presigned URL into the response | ✅ shipped | none |
| 4 | Interactive Launcher (.rds→RStudio, .h5ad→CellxGene, .ipynb→Jupyter) | `viewers/interactive-tool-launcher.tsx` | ✅ shipped | none |
| **5** | **S3 direct** | `s3://biomate-nextflow-work/<user_id>/<run_id>/output/` | ✅ writeable | **bypasses BioMate's audit trail, access control, and lifecycle** — see concern A |
| 6 | Bulk "download all" zip | `routes.ts:7460` `/tmp/biomate_runtime_outputs/<invocationId>/` | ✅ shipped | none |
| **7** | **Comprehensive Markdown report** | `AfterRunReport.tsx:160` "Download report" button → `buildFullReportMarkdown` line 1243 | ⚠️ partial | **missing 6 of 7 things the design promises** — see concern B |

### Concern A — Channel 5 (S3 direct) bypasses BioMate

The path `s3://biomate-nextflow-work/<user_id>/<run_id>/output/` is hard-coded under a single bucket prefix. Implications:

- **No user-chosen output folder.** Users cannot route outputs to their own S3 bucket, their Galaxy history, or a project folder. The workflow-settings tab does NOT expose an output-folder picker (only `nextflowStatus.outdir` is read at `nextflow-workflow-viewer.tsx:2159`).
- **Power users with IAM access can `aws s3 cp` and pull bytes — bypassing the Outputs tab's download-counter, the billing-side per-file usage log, and the After-run report's chain-of-custody record.** Today this is a feature (transparency) and a hole (no audit) at the same time.
- **No lifecycle policy visible in the bucket config.** Outputs accumulate forever unless someone runs a cron to expire them.

**What this means for the Liu pilot:** patient-genomics data in Phase 2 needs IRB-grade access logging. The current S3-direct hole is a problem when real PHI flows. Either lock the bucket (no IAM grant to users) or layer all access through a counted `/api/runs/:id/output/<filename>` endpoint that signs the URL on each request.

### Concern B — Channel 7 (Download report) is incomplete

`buildFullReportMarkdown` at `AfterRunReport.tsx:1243` emits 8 sections (Header / Findings / Outputs / Methods / Parameters / Software / Citations / QC Audit). What's **missing** vs the design's promise (per BIO tutorial qcBody, IND §2.6.1 narrative work, "21 CFR Part 11" framing):

| Missing | Why it matters |
|---|---|
| **No download URLs / S3 paths in Outputs section** | User must re-open BioMate to actually fetch files; report is a pointer-less catalog |
| **No file sizes or hashes** | Not reproducibility-grade — can't verify file integrity after offline copy |
| **No data-citation block for input datasets** ("input from UDN cohort X, sample sheet at S3 path Y") | Audit trail incomplete; no input-side reproducibility |
| **No chain-of-custody / signature trail** despite the QC tab's "21 CFR Part 11 friendly" promise | Regulatory-grade framing not delivered |
| **Markdown only — no PDF/DOCX export** | Researchers (Liu/Zhi/Zhao) paste into Word manuscripts; raw markdown loses figures + tables |
| **Methods is verbatim Methods-tab text**, not a polished "publication-ready paragraph" | BIO tutorial says *"paragraph-form Methods you can paste into a manuscript"* — gap |
| **Footer says "(v2 preview)"** | Visible to users; report looks unfinished |

Effort to close all 7 gaps: **~2 days frontend** + **~half day backend** (add input-dataset metadata + hash field to /api/runs/:id response) + **~1 day** for pandoc-based DOCX export endpoint.

---

## 2. Output folder choice in workflow settings tab — **NOT exposed today**

User question: *"there is a output folder, how does it work? where can the user choose?"*

**Honest answer:** the workflow-settings tab does NOT have a user-facing output-folder picker. The viewer reads `nextflowStatus.outdir` (line 2159 of `nextflow-workflow-viewer.tsx`) which is auto-computed by the backend as `s3://biomate-nextflow-work/<user_id>/<run_id>/output/`. The user has zero control over where outputs land.

If you saw an "output folder" UI element, it's probably the read-only `outdir` display in the run-status section — not an input. Worth verifying with a screenshot if the design promised a picker.

**Recommended fix (if output-folder choice is wanted):**
- Add an `outputLocation` field to the workflow-settings panel with options: `Default (BioMate-managed)` / `My S3 bucket (paste URI)` / `My Galaxy history` / `My project folder` (last requires Concern C/D below).
- Backend wires the choice into Nextflow's `publishDir` directive at dispatch.

---

## 3. Project vs chat — **project entity does not exist in DB schema**

User question: *"What will be the difference between in a chat and in a project? Do we have a file management directory for project? What's the difference between project and chat?"*

**Honest answer:** BioMate has **chat sessions only.** No `projects` or `workspaces` table exists in `frontend/shared/schema.ts` (verified by grep — empty result). The endpoints that exist are `/api/sessions` (CRUD on chat sessions, lines 12270–12353 of routes.ts). A "Workspaces" button appears in the sidebar (seen in BC e2e snapshot earlier) but it doesn't back to a project entity — it likely navigates to a placeholder route.

| Entity | DB table | API endpoints | Owns datasets? | Owns runs? |
|---|---|---|---|---|
| **Chat session** | `chat_sessions` | `/api/sessions/*` | Yes — `chat_sessions.galaxyHistoryId` (one Galaxy History per session) | Yes — via session_id FK on execution_runs |
| **Project** | ❌ does not exist | ❌ none | — | — |
| **Workspace** | ❌ does not exist | ❌ none | — | — |

So today:
- A user's "project" IS a chat session (1:1 mapping)
- Datasets uploaded in one chat are visible **only** in that chat's Galaxy History
- Datasets uploaded in chat A are **invisible** to chat B (even for the same user)
- No way to organize multiple chats under a parent "project" with shared file storage

**Implication for the Liu pilot:** if a researcher analyses 12 rare-disease cases, today they have 12 separate chats with 12 separate Galaxy Histories. There's no parent "Liu_RareDisease_Q3_2026" project that aggregates them. This is a real gap vs how Galaxy users actually work.

### Recommendation if project model is wanted (effort: ~1 week)

1. Add `projects` table: `id, name, owner_user_id, created_at, description`
2. Add `project_id` FK (nullable) to `chat_sessions` and `execution_runs`
3. `/api/projects` CRUD
4. UI: "Project" picker at session creation; sidebar groups sessions by project
5. Project-scoped file browser: `/api/projects/:id/files` aggregates Galaxy histories of all child sessions

---

## 4. Galaxy dataset management vs BioMate

Galaxy's native model:
- **History** = a container for datasets + their provenance. Each user has many histories.
- **Dataset** = a file with type, lineage, metadata. Belongs to one history.
- **Invocation** = one run of a workflow. Produces datasets into the active history.
- **Tool** = a single step. Tools chain inside a workflow.

BioMate uses Galaxy's history-per-session model: `chat_sessions.galaxyHistoryId` (verified at `schema.ts:709`). Each chat session has exactly one Galaxy History. Datasets uploaded in the chat land in that history. Workflow invocation outputs land in the same history.

What BioMate **inherits** from Galaxy:
- ✅ Per-dataset provenance (which tool/version produced this dataset, with what inputs and params)
- ✅ Galaxy History UI is implicitly accessible if user has a Galaxy account (port 8081)
- ✅ Standard dataset typing + lineage

What BioMate **does NOT surface** from Galaxy:
- ❌ Galaxy's "Compare histories" view
- ❌ Galaxy's tag/annotation system for datasets
- ❌ Galaxy's "import dataset from public library" UI
- ❌ Galaxy's data-quota visibility

---

## 5. Per-run trace — **yes, partially**

User question: *"how does galaxy handle each run of the workflow? can user trace each and every run?"*

| Trace feature | BioMate today |
|---|---|
| List all runs for a session | ✅ `routes.ts:720` `list_runs` endpoint |
| List all runs across sessions for a user | ⚠️ via `/dashboard` page (one-level listing, no filtering) |
| Per-run page with status, parameters, outputs, logs | ✅ After-run report (7 tabs) |
| Re-open a completed run from history | ✅ via sidebar chat-history clicks |
| Per-step status within a run | ✅ phase cards in workflow panel |
| Per-step logs | ⚠️ partial — accessible via Galaxy's job stderr/stdout, not surfaced in BioMate UI |
| Run-time provenance graph (Galaxy's "show workflow" view) | ❌ not in BioMate UI |
| Audit trail of WHO ran WHAT WHEN | ⚠️ logged in execution_runs table, not exposed in UI |

---

## 6. Single-step rerun with changed parameters — **yes, with Nextflow-resume semantics**

User question: *"if the user changed the parameter of a single step, and rerun, what will happen, will the entire workflow continue to run from that step or just that run?"*

**Real endpoint exists:** `POST /api/workflows/runs/:id/rerun-from-step` at `routes.ts:10472`. Takes `{ step_name, param_overrides }`. Builds a Nextflow command with `-resume -w <prev_work_dir>` (line 10495).

**Nextflow's `-resume` semantics:**
- Upstream steps whose inputs haven't changed → **cached, NOT re-run**
- The step whose parameter changed → re-run
- All downstream steps that depend on it → **re-run (cascade)**

So if you change a param of step 3 in a 5-step chain → steps 1+2 cached, steps 3+4+5 re-run.

**What BioMate adds on top of Nextflow:**
- Frontend "Rerun from step" button per phase card (need to confirm — `data-testid="rerun-from-step-btn"` would be the place)
- New `run_id` issued for the rerun → so `list_runs` shows both as separate entries
- `prev_run_id` linkage in the rerun response for traceability

---

## 7. Single-step running ("just that one step, alone") — **partially**

User question: *"Can biomate do literally single step wise running?"*

**Answer: not quite.** What exists today:
- `start_from_step` parameter on chain submit endpoint (`routes.ts:9896`) — lets you start from step N. But you can't say "run ONLY step N, skip everything else."
- Internally: `_run_chain(start_from_step=N)` runs N, N+1, N+2, … to the end (`workflow_chain.py:372`).
- There's NO `end_at_step` parameter currently exposed; could be added in ~1 hour to backend + ~half day frontend.

**Use case where this matters for Liu pilot:** if a user only wants to re-run OUTRIDER (step D) on already-aligned BAMs (step C done previously) and skip the case-report aggregation (step E), today they can't — `start_from_step=3` would still run steps 3 + 4. Need an `end_at_step` to stop at 3.

**Galaxy comparison:** Galaxy lets you run individual tools standalone (any tool in the toolshed, any time) — that's the simplest single-step model. BioMate's chain composer doesn't surface individual tools as runnable; you have to dispatch via a workflow definition.

---

## 8. Compare runs — **scaffolded but not fully shipped**

User question: *"How the experimental results of multiple runs are compared in galaxy? Can we do that?"*

**Galaxy:** has a "Compare Histories" feature — visual diff of datasets, parameters, and outputs across two histories. Not deeply analytical; mostly a side-by-side viewer.

**BioMate:**
- ✅ `frontend/client/src/v2/ChatCards.tsx:211` `ComparisonCard` — UI scaffolding for run A vs run B with Δ column
- ✅ Referenced in `v2/ResearchApp.tsx:667` and `:819` (so it does render somewhere in the v2 layout)
- ✅ `frontend/client/src/hooks/useUnifiedExecution.ts:210` has `"Failed to compare runs"` error → suggests a `/api/runs/compare` endpoint exists (need to verify)
- ✅ `frontend/client/src/components/pilot-experiment-panel.tsx` — **full A/B comparison panel for the experimental harness** (see §9 below)

So: comparison **exists in v2 layout + pilot-experiment-panel but is not the main UI flow**. Most users today don't discover it.

---

## 9. Experimental harness — **two layers, both real**

User question: *"I remember we have an experimental harness prepared for biomate, how does it fit in biomate?"*

There are TWO things called "harness" in the codebase:

### Layer A — User-facing A/B comparison panel
**`frontend/client/src/components/pilot-experiment-panel.tsx`** (Track 2C, per file header).

Features (per the file's docstring):
1. User specifies hypothesis + control/experimental parameter sets
2. BioMate fires both runs in parallel
3. Side-by-side comparison + automated narrative when done
4. History of past experiments in left sidebar panel

Data model: `ExperimentListItem` (hypothesis, workflowId, control/experimental labels, control_run_id, experimental_run_id, hasResults) and `ExperimentResult` (status, comparison.runtimeDelta + memoryDelta + qualityDelta + parameterDifferences + preferredRun).

**This is what fits the user's "experimental harness" memory.** It's the BioMate equivalent of Galaxy's compare-histories, but more structured (hypothesis-driven, parameter-aware, auto-narrative).

Status: panel exists, types defined, needs verification of (i) backend `/api/experiments` CRUD, (ii) how the panel is currently surfaced in the UI (sidebar item or tab in workflow viewer?), (iii) whether it's currently wired into any e2e demo.

### Layer B — QC autoloop test harness (NOT user-facing)
**`backend/experiments/`** dir contains:
- `admet_autoloop/`
- `cryo_em_autoloop/` + `cryo_em_autoloop_ux/`
- `cyp_ddi_autoloop/`
- `docking_autoloop/`
- `nca_pk_autoloop/`
- `pbpk_autoloop/`
- `autoloop_bridge.py`
- `verified_queries/`

These are **engineering test harnesses for the QC auto-loop feature** (the "QC gate halt → propose param fix → rerun" loop demonstrated in the cryo-EM auto-loop UX). Each domain folder has its own gates, remediation strategies, and pytest suite. Not user-facing — they're internal-eval infrastructure.

### Layer C — Routing / capability benchmarks (also not user-facing)
**`evaluation/`** dir contains `runners/` for `routing_v6`, `biomni_eval1_v28`, `bixbench_v18`, etc. These are scoring benchmarks for product capability (per `CLAUDE.md` §"Benchmark-Driven Development"). They don't run from chat; they run from CI/scripts.

### How the 3 layers fit together
| Layer | Purpose | Audience | Surface |
|---|---|---|---|
| **A — Pilot Experiment Panel** | A/B-test workflows with different params | Researchers (Liu/Zhi/Zhao) | UI tab in workflow viewer |
| **B — backend/experiments/ autoloops** | Test QC-loop remediation logic | BioMate engineers | pytest |
| **C — evaluation/ routing benchmarks** | Score the AI router's quality | BioMate engineers | python scripts |

For Liu pilot specifically: **Layer A is the relevant one.** If RQ1 (output concordance) needs A/B between BioMate's nf-core/drop run and Liu's reference run, the Pilot Experiment Panel is the right vehicle — assuming it's actually wired in and works. **TBD audit** — needs a separate session to verify.

---

## Summary of real concerns + recommended actions

| Concern | Severity | Recommended action |
|---|---|---|
| Output folder is not user-choosable | medium | Add `outputLocation` field to workflow settings (default / user-S3 / galaxy-history) — ~1 day |
| Channel 5 (S3 direct) bypasses audit trail | high (for Liu Phase 2 PHI) | Layer all output access through counted `/api/runs/:id/output/<filename>` — ~1 day |
| Download report missing 6 of 7 design promises | medium | Spec'd in §1 Concern B — ~3 days total |
| **Projects do not exist** in DB schema | medium-high (for repeated use) | Add `projects` table + sidebar grouping — ~1 week. Could be deferred; Liu pilot Phase 1 works fine with chat-only model. |
| No single-step (end_at_step) execution | low | Add `end_at_step` param to chain submit — ~half day |
| Pilot Experiment Panel exists but discoverability/wiring unclear | medium | Separate audit session: confirm /api/experiments backend exists; surface in workflow viewer as a tab |
| Galaxy compare-histories not surfaced | low | If A/B panel works well, this becomes redundant |
| Per-step logs not in UI | low | Surface Galaxy stderr/stdout in phase-card expand — ~half day |

## Open audit items (for a follow-up session)

1. Confirm `/api/experiments` backend endpoints exist + match the `ExperimentListItem` / `ExperimentResult` types
2. Confirm where Pilot Experiment Panel renders (sidebar item? workflow viewer tab? hidden behind a flag?)
3. Confirm whether the "Workspaces" sidebar button (seen in BC e2e snapshot) is wired or placeholder
4. Audit S3 bucket lifecycle policy for `biomate-nextflow-work` (object expiration, access logging, server-side encryption)
5. Confirm whether `nextflow_executor.execute_nextflow` has a way to accept a user-supplied `outdir` from the request body (it does accept compute_config; possibly outdir too)

## Background reading

- `frontend/client/src/v2/AfterRunReport.tsx:160` — Download report button + `buildFullReportMarkdown:1243`
- `frontend/client/src/components/nextflow-workflow-viewer.tsx:2159` — outdir display (no picker)
- `frontend/client/src/components/pilot-experiment-panel.tsx` — A/B comparison panel
- `frontend/server/routes.ts:10472` — rerun-from-step endpoint
- `frontend/server/routes.ts:9896` — `start_from_step` chain dispatch
- `frontend/shared/schema.ts` — entity model (chat_sessions but no projects)
- `backend/experiments/` — engineering test harness layer
- `evaluation/runners/` — benchmark layer
- `docs/20260616_DEV_vs_CLAUDE_DESIGN_TRUTH_TABLE.md` — broader design-vs-dev audit
