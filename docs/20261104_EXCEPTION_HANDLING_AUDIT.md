# BioMate exception-handling audit (2026-11-04)

Full read-only sweep of exception/error handling across the four product-code layers, run as four parallel reviewers. Focus (from CLAUDE.md): **(1)** resolve root causes — retry/catch-continue that masks a real failure is forbidden; **(2)** a handler that returns empty/0/clean on a *failure* is worse than a hard error because it produces a fake result that looks like a bug elsewhere ("429 → ok, 0 results"); **(3)** billing/cost events must not be silently dropped; **(4)** read the full error (don't truncate to `HTTP 500`).

Scope: `backend/lib/galaxy/{webapps/galaxy/api,chain,ai}` (Python), `frontend/server` (Node/TS), `frontend/client/src` (React/TS). Scripts and `evaluation/` harnesses were out of scope (lower product risk) — a follow-up can cover them.

Legend for the "unknown ≠ empty" theme that dominates the findings: a read that *failed* must surface a distinct error/unknown state, not the same empty value a genuinely-empty read returns.

---

## Severity tally (confirmed, product code only)

| Layer | Critical | High | Medium | Low |
|---|---|---|---|---|
| Backend AI / billing / search | 2 | 5 | 4 | 4 |
| Backend execution / chain | 0 | 4 | 3 | 4 |
| Node / TS server | 0 | 2 | 4 | 2 |
| React client | 0 | 2 | 3 | 2 |
| **Total** | **2** | **13** | **14** | **12** |

---

## CRITICAL

### C1 — Batch job compute cost dropped on a Redis blip, no dead-letter
`backend/lib/galaxy/ai/billing/core/realtime_cost_service.py:103-127` (`record_batch_job_cost`)
`except Exception as e: log.warning("Redis unavailable — batch job cost not recorded")`. A completed GPU/CPU Batch job's vCPU/GPU/mem cost is logged-and-forgotten on any transient Redis error (`socket_timeout=5s`). The monthly `:total` never increments → `check_and_reserve` later reads an under-counted total and keeps admitting jobs. A multi-hour GPU run can vanish from billing. **Fix:** on failure write a dead-letter (durable file/DB queue) and reconcile; never return as if recorded. (Mitigation today: flat-tier billing lowers live impact — see B's note.)

### C2 — LLM token cost double-swallowed; with Lago off, lost entirely + HTTP 200
`realtime_cost_service.py:90-101` (`record_llm_cost`) and `billing/api/billing_router.py:505-517` (`/internal/billing/llm_cost`). The service swallows a Redis error, and the API handler wraps the same call in its own `except: log.warning` then returns **HTTP 200**. Lago is disabled by default (`lago_enabled()` → no-op), so when Redis is down the usage event has **no backing ledger at all** and Node gets success. Under-counts usage → quota under-enforced during an outage. **Fix:** durable append-only ledger write that must succeed or the endpoint returns 5xx; same dead-letter as C1.

---

## HIGH

### Backend execution — the completion/QC-recording path treats "couldn't read S3" as "clean + empty"
- **H1 `webapps/galaxy/api/nextflow_executor.py:4144-4146`** — `_evaluate_qc_from_s3(...)` outer `except Exception: log.warning; return []`. Returns the list of QC gate *failures*; `[]` = "all gates clear." Any error (boto import, S3 download, JSON parse) → a completed ADMET/CryoEM safety run is recorded as a **clean safety pass**. This is the single most dangerous finding: a real hERG/DILI/AMES failure can be reported clean. **Fix:** a gate that cannot be evaluated must record a distinct `unknown`/`degraded` verdict (or hard-error), never `passed`. This is the recorded/retrospective verdict (orphan-finalizer path), not necessarily the live in-trace halt — but per rule #2 it must not read clean.
- **H2 `nextflow_executor.py:~4000-4009`** — same function, inner metric read swallow → `if not metrics: return []`. A transient S3 read error on just the metrics file reproduces H1's fake-clean even when the outer catch never fires.
- **H3 `nextflow_executor.py:4455-4458`** — `_list_s3_output_files` `except: return []`. A transient S3 LIST error → a completed run reports **zero outputs**, and the empty list is fed into `_evaluate_qc_from_s3` (line 5110), so one hiccup both hides outputs and yields fake-clean QC. Masked again at line 8155 on the status endpoint.
- **H4 `nextflow_executor.py:4509-4511`** — `_list_s3_work_output_files` `except: return []`. The last-resort cross-region output recovery masks its own failure → outputs doubly lost.

### Backend AI / search — error-masking empty returns (the documented "429 → 0 results" class)
- **H5 `ai/search/federated_query.py:333-347`** — `_fetch_kegg` uses `urllib.urlopen` directly with `except Exception: return {results:[]}` and **bypasses the module's own `_note_failure` guardrail** that every other fetcher uses. KEGG 429/timeout → the fan-out labels the source "succeeded, 0 pathways." Exact re-introduction of the Semantic-Scholar incident for KEGG.
- **H6 `ai/search/vector_search.py:560-581`** — `search()` wraps the whole body in `except Exception: return []`. Embed server down / dtype mismatch / DB error → vector tool search returns `[]`, indistinguishable from "no tools match."
- **H7 `ai/search/enhanced_tool_search.py:135-140`** — Step-1 FTS5 error → `return []`. Corrupt/locked index looks like "nothing matched."
- **H8 `ai/ai_assistant.py:1190-1202`** — `search_literature` returns `[]` on exception. Provider HTTP error/rate-limit → fake "no citations found."

### Node server — read endpoints mask Galaxy/DB/key failure as empty
- **H9 `server/routes.ts:3460,3474,3494`** — `GET /api/galaxy/histories` does `.catch(() => [])` on both the Galaxy call and the DB call, outer catch `res.json({ histories: [] })`. Galaxy down / rejected per-user key / DB unreachable → **HTTP 200 `{histories:[]}`** = "you have no runs," indistinguishable from an empty account.
- **H10 `server/routes.ts:3505,3566`** — `GET /api/galaxy/histories/:id/datasets` → `{ datasets: [] }` on failure. Opening a history with real data during an outage shows nothing (looks like data loss).

### React client — SSE dies silently, UI stuck
- **H11 `client/src/components/nextflow-workflow-viewer.tsx:2597`** — `es.onerror = () => { if (!stopped) es.close(); }`. Closing the EventSource on the FIRST error also defeats its built-in auto-reconnect; this stream carries `step_state`/`workflow_state`/`autoloop_*`/`qc_gate_*`. A gunicorn recycle or client↔EC2 blip mid-run → phase cards freeze, auto-loop stops, "Running…" never resolves. The sibling `workflow-artifact.tsx:495` does this correctly (exp-backoff reconnect ×5 with surfaced status); the viewer's comment claims it mirrors that but doesn't. **Fix:** port the reconnect pattern.
- **H12 `client/src/hooks/useUnifiedExecution.ts:348-351` & `:668-673`** — when SSE is chosen, `startPolling` is never armed (only in the `else`). A non-transient SSE error → EventSource retries forever with zero events and no poll fallback → `currentRun` stuck `running`, footer stuck "Running…". **Fix:** arm a polling fallback alongside SSE.

---

## MEDIUM

- **M1 `billing_internal.py:176-178`** — `record_llm_cost` returns `{status:error}` with HTTP 200 and only `str(exc)` (traceback lost); the durable file-cost-log write is inside the swallow, so the audit record can be lost silently.
- **M2 `nextflow_executor.py:5803-5806`** — `_fail_run()` persists terminal "failed" to the cross-worker store inside `except Exception: pass` with **no log**. If Redis is degraded the failed status lives only in worker-local `_runs`; after a recycle the run looks "running" forever — the exact stuck-run class the RunStateStore refactor exists to prevent, and it's invisible.
- **M3 `orphan_finalizer.py` step 3b** — `_post_frontend_status` failure caught at `log.debug`. This push un-sticks the UI (writes terminal status to Postgres); a failure that leaves the UI on "running" is logged only at DEBUG.
- **M4 `ai/ai_assistant.py:700-710`** — `_is_multi_task` swallows the classifier LLM failure and defaults to single-task; a genuine multi-task request is silently run as single-task.
- **M5 `billing_router.py:208-219`** — `/api/billing/usage` returns all-zeros on Redis error (sets `redis_status:"unavailable"`, but `quota_pct:0.0` renders as "plenty left" unless the consumer checks that field).
- **M6 `ai/billing/core/lago_client.py:38-62`** — `_resolve_lago_api_key()` runs at **module import** and can `RuntimeError` on the Secrets-Manager path even though Lago is off by default; cascades to `quota_enforcer` import. Latent module-load crash (the pre-sync step-3 class). Env-dependent.
- **M7 `code-runner.ts:381-382`** — sidecar non-ok returns `[sidecar error: HTTP ${status}]` and **discards `resp.text()`** — the truncated-error class; user running code gets no diagnostic.
- **M8 `galaxy-assistant.ts:8197`** — `_lookupWorkflowByName` returns `null` on `!resp.ok`/throw; callers treat null as "no such workflow," so a transient Galaxy 500 silently drops an explicit workflow-name override and proceeds with the wrong workflow.
- **M9 `storage.ts:413,599`** — `createExecutionRun`/`updateExecutionRun` DB writes `.catch(warn)` then return the in-memory object as if durably saved; after a worker recycle the run is lost (MemStorage-first is intentional, but the write failure should be flagged on the returned object).
- **M10 React `useUnifiedExecution.ts:355,426,487` + `useWorkflowExecution.ts:111,123,158,184`** — unguarded `JSON.parse(event.data)` in SSE listeners; one truncated frame throws and that state transition is lost silently (other SSE sites wrap parse in try/catch + continue).
- **M11 React single error boundary** — `main.tsx:9-51` `AppErrorBoundary` wraps `<App/>` well, but it's the only one; a render throw in the chat/workflow panel blanks the whole app. Recommend a panel-scoped boundary.
- **M12 React `settings-dialog.tsx:340`** — optimistic S3-credential clear before the await, DELETE failure swallowed → UI says removed while it exists server-side (credential desync).

## LOW (grouped)

- Re-raises dropping the cause (no `from exc`): `nextflow_executor.py:5911`, `chain/transforms.py` S3 path, `ai/llm_router.py:543`.
- Bare `except:` (catches `KeyboardInterrupt`/`SystemExit`) on localized JSON-field parses: `ai_assistant.py:1708,1717,5298,5644`; `enhanced_tool_search.py:383,393,474,576`; `unified_workflow_search.py:1691,1696,1701`. Behavior acceptable; should be `except (ValueError, TypeError, json.JSONDecodeError)`.
- JSONL audit/event parse loops `except: pass` dropping malformed lines with no counter: `nextflow_executor.py:8527,8650,9091,9170`, `ai_assistant.py:~2952`.
- `galaxy-state-poller.ts:129` fire-and-forget `pollAll()` with no `.catch` (unhandledRejection risk on a long-lived poller).
- Proxy response-stream error handlers missing: `routes.ts:18078` (`upRes.pipe(res)`), ~18206 (IT HTML buffering).
- React `workflow-artifact.tsx:668-672` QC-retry failure only `console.error` (no toast); `nextflow-workflow-viewer.tsx:452` download panel `.then(r=>r.json())` no ok-check (honest-empty).

---

## The 10 worst, ranked

1. **H1** `nextflow_executor.py:4146` — QC gate evaluation crash recorded as a clean safety pass. *(safety)*
2. **C2** `realtime_cost_service.py:100` + `billing_router.py:505` — LLM cost lost entirely (Lago off) + HTTP 200.
3. **C1** `realtime_cost_service.py:126` — Batch compute cost dropped on Redis blip, no dead-letter.
4. **H3** `nextflow_executor.py:4457` — S3 list error → zero outputs + feeds fake-clean QC.
5. **H11** `nextflow-workflow-viewer.tsx:2597` — SSE closes on first error, no reconnect → frozen "Running…".
6. **H5** `federated_query.py:346` — KEGG bypasses `_note_failure` → "ok, 0 results."
7. **H9** `routes.ts:3460/3494` — `/histories` masks Galaxy/DB/key failure as empty list.
8. **H6/H8** `vector_search.py:579` / `ai_assistant.py:1202` — search/literature return `[]` on error.
9. **M2** `nextflow_executor.py:5804` — `_fail_run` silently fails to persist terminal status (stuck-run reintroduced).
10. **H12** `useUnifiedExecution.ts:668` — SSE chosen but no polling fallback → run stuck `running`.

---

## Fix plan (what I'm doing vs. deferring)

**Applied this session** (clear, localized, verifiable by compile/unit — see follow-up commits):
- H5 KEGG → route through `_note_failure` so a KEGG error is a recorded failure, not "0 results."
- M10 SSE `JSON.parse` guards in the two hooks (match the existing try/catch+continue pattern).
- M7 `code-runner.ts` — include `await resp.text()` in the sidecar error so the full error survives.
- **H1/H2 (completion path)** — `_evaluate_qc_from_s3` now distinguishes a metrics **read error** (S3 cp non-zero/throw on a matched `toxicity_report.json`/`qc_metrics.json`) from "no safety metrics present." On a read error, and in the outer `except`, it logs **ERROR** ("QC NOT EVALUATED … NOT a pass") and returns a `_qc_unevaluable()` **advisory** sentinel (`status:"unknown"`, `advisory:true` → non-blocking per the viewer's `advisory !== true` check) instead of the empty "all-clear" list. So the **completion** verdict (`qc_gates` → status payload + `routes.ts` audit log) is recorded as degraded, not clean. Scoped & safe: it does **not** write/alter the `qc_events.json` sidecar, so the after-run QC **table** rendering is untouched.
- **H3/H4** — `_list_s3_output_files` / `_list_s3_work_output_files` still return `[]` (every caller iterates a list) but now set a per-thread signal `s3_list_last_error()` (reset per call, set on the except path, log elevated to ERROR). The completion path and the `/qc-events` on-demand path read it right after listing and pass `s3_list_degraded` into `_evaluate_qc_from_s3`, which — no metrics AND listing degraded — returns the `_qc_unevaluable` sentinel instead of `[]`. Workdir-fallback success clears the signal. Other list callers unchanged.
- **M2/M3/M9** run-state persistence visibility — the silent writes that keep a terminal status alive across a worker recycle now log at ERROR: `_fail_run` store write (`except: pass`→`log.error`), `orphan_finalizer` frontend-status push (`log.debug`→`log.error`), `storage.ts` create/update DB write (`console.warn`→`console.error`, explicit DURABILITY message).
- **H6/H8** search error visibility — `vector_search.search()` loud+signalled (`last_vector_search_error()`) on error/encode-fail/not-init (real no-match path clear); `search_literature` provider-error `log.warning`→`log.error`. H7 FTS error already logs at ERROR; the signal pattern is the seam its aggregator can adopt (5+ callers — not rewired blind).

**Still deferred for H1–H4 (needs a live QC-gate run to verify the QC display surface):**
- The `/api/.../qc-events` **on-demand** retrospective path (`_read_qc_events_sidecar`) still shows the empty "all passed" fallback on a read/list error, because no sidecar is written (the `qc_gates` completion record IS now degraded). The remaining step is to write a **degraded sidecar** (flat `events` row with the unevaluable status + a `methods_text`) so the after-run `QcAuditTab` shows "QC could not be evaluated" — that feeds the user-visible table and must be verified against a live QC-gate run.

**Deferred with a concrete recommended patch (NOT changed blind — these alter safety/billing/SSE/dashboard semantics and need a live run to verify):**
- C1/C2/M1 billing dead-letter + fail-loud endpoint: durable ledger that must succeed or 5xx; reconcile queue. Touches the money path — needs careful review.
- H9/H10 `/histories` + `/datasets`: return an `error` field (and non-2xx) on upstream failure, with a UI banner, instead of `{[]}`. Needs the dashboard to handle the new shape.
- H11/H12 SSE reconnect + polling fallback: port `workflow-artifact.tsx`'s exp-backoff reconnect into the viewer and arm `startPolling` alongside SSE. Demo-critical; verify with a live run.
- M2/M3/M9 run-state persistence surfacing: log the store-write failure (not silent) and flag DB-persist failure on the returned run object.
- M11 panel-scoped React error boundary.

See the ranked list above for order. The deferred items are deferred for *verification safety*, not because the fix is unclear — each has its patch sketched here.
