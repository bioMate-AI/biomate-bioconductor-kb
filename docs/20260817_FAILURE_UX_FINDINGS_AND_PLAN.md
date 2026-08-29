# Failure-handling UX: findings & remediation plan

**Date:** 2026-08-17
**How found:** while capturing current-UI screenshots for the claude-design brief (`docs/20260817_data_ui_screenshots/`), three real defects were spotted in the failed-run and progress screens. They were caught by review of the screenshots, not by an audit — noted as a process miss (screenshots were treated as "done" without critically auditing the UI they showed).
**Evidence screenshots:** `20_run_panel.png` (failed run — leaked error + Restart-only), `30_completed_run_panel.png` (progress rendered as separate chat messages).

---

## Finding 1 — Backend internals leak into the user-facing error (SECURITY / trust) — **HIGH**

A failed run shows the **raw Nextflow log tail** verbatim in the visible error/log panel — container recycles, worker-recycle notes, work-dir S3 paths, ECR image names, and messages like "Nextflow died after ~10h". Revealing backend internals to users is forbidden.

**Root cause (code):**
- Backend intentionally routes the raw error lines into `log_tail` "to surface the real cause to the run-status API" — `backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py:893` (see also `_log_indicates_nextflow_failure`, ~`:840`, and the error-excerpt append ~`:927–931`).
- Frontend renders that raw tail directly: `frontend/client/src/components/nextflow-workflow-viewer.tsx:2294–2298` (`setLogs(rawLogTail.slice(-120))`) and `:1916` (`rawLog = logs.slice(-50).join('\n') + errorMessage`). No sanitization; shown in the user-visible panel, not an admin/debug-only view.

**Fix (root cause, no workaround):**
1. **Server-side classification + sanitized message.** In the failure path, parse the raw cause into a small, safe structure: `{ category, user_message, is_transient, suggested_action }`. Never send the raw log to the user-facing status payload.
2. **Keep the raw log internal.** Retain the full `log_tail` only in an internal/admin channel (support view / audit log), not in the field the run panel renders.
3. **Frontend shows only the sanitized message + action.** The panel renders `user_message` (e.g. "The pipeline stopped after ~10 hours — likely a wall-time/resource limit.") and the recommended action from Finding 2; the raw-log block is removed from the user view (or gated behind an internal role).

> Dependency: Finding 2's recovery logic consumes the **same** classification produced here — so build the classifier once, server-side, and feed both the sanitized message and the recovery decision from it.

---

## Finding 2 — "Restart" is the wrong (and useless) answer to a failure — **HIGH**

On a hard failure the only offered action is a from-scratch **Restart**. A pure restart re-runs the same workflow with the same inputs, params, and resources — so a **deterministic** failure just reproduces itself (another ~10 hours, another Batch spend, same death), and even a transient failure throws away all completed work.

**Correcting the record (what already exists):** auto-fix is **not** entirely absent —
- `resume_from_run_id` → Nextflow `-resume` (reuses cached work, skips completed steps): `nextflow_executor.py:1202`, `:4917`, `:5082–5102`.
- `handleRetryWithSuggestions` uses `-resume` so cached phases are skipped, not a fresh start: `nextflow-workflow-viewer.tsx:1614–1626`.
- Auto-loop applies remediation automatically via `-resume`: `nextflow-workflow-viewer.tsx:2077`.
- Orphan revival for log-stream loss while the JVM is alive: `nextflow_executor.py:967` (`_looks_like_log_stream_orphan_failure`), `:994` (`_revive_orphan_nextflow_run`).

**The real gap:** this machinery only fires for *analyzable* failures (QC gates, known patterns). A hard **infra/timeout** death falls through to a generic *"Review the error log and retry"* (`nextflow-workflow-viewer.tsx:1941`) + bare Restart. The `-resume` plumbing is right there but not wired to this failure class, and there is no transient-vs-deterministic decision.

**Fix — a real failure-recovery model:**
1. **Classify** the (sanitized) cause: **transient** (spot reclaim, network blip, orphaned head node, flaky step) vs **deterministic** (OOM, bad parameter, malformed input, hard wall-time limit, real tool error).
2. **Transient → resume from checkpoint** (`-resume`), retrying only the failed step, **escalating wall-time / memory** on the retry so a borderline timeout doesn't just re-time-out.
3. **Deterministic → do not blindly resume.** Surface the specific cause + a concrete remediation (resource bump, param fix, tool swap), apply it, **then** `-resume`. This is the "intelligence" the product claims.
4. **Demote bare Restart** to a clearly-labeled last resort ("Start over — discards cached work"); it should never be the primary action on a failure.

Missing piece = the **classifier + escalation/remediation decision**; the `-resume` execution path already exists.

---

## Finding 3 — Progress steps render as separate chat messages, not one tracker — **MEDIUM**

Each pipeline step ("Step X…", "X done", "QC blocked on …", "Workflow finished") is emitted as a **full assistant chat message**, each carrying the standard message action footer (copy / download / regenerate) and large vertical spacing. The stream of progress becomes a wall of near-empty messages with dangling buttons.

**Root cause:** step-progress events are turned into individual chat messages (rendered by the normal chat-message component, hence the per-message action footer) instead of updating a single, in-place progress component.

**Fix:** consolidate step-progress into **one streaming progress tracker** (a single live card/message that updates its step list in place) — no per-step action-button footer, compact spacing. The final "Workflow finished" transitions that one card to a terminal state; the workflow/report card remains the durable artifact.

---

## Priority & sequence

| # | Finding | Severity | Depends on |
|---|---------|----------|-----------|
| 1 | Backend error leakage → sanitize + server-side classify | HIGH (forbidden) | — |
| 2 | Failure-recovery model (classify → resume / fix-resume; demote Restart) | HIGH | #1's classifier |
| 3 | Progress steps → single streaming tracker | MEDIUM | — |

**Sequence:** #1 first (it's the forbidden one, and its classifier feeds #2) → #2 (recovery model) → #3 (progress tracker, independent, can run in parallel).

**Discipline:** all three are root-cause fixes (per project rules — no workarounds). Each is a distinct change across the executor and/or the workflow viewer; review the diff and trace the failure/SSE data flow before any expensive re-run (the pre-sync review rule). Validate on a genuinely failed run (a deterministic OOM/param failure and a transient one) — do not fake the states.
