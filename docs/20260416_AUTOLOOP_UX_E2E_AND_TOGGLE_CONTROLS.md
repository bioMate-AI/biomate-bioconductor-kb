# CryoEM Auto-Loop UX — E2E Test Suite & Toggle Controls

**Date:** 2026-04-16  
**Scope:** `backend/experiments/cryo_em_autoloop_ux/`  
**Zero BioMate production files modified.**

---

## What Was Built

### 1. Auto-loop toggle controls in `UXAwareAutoLoop`

`ux_loop.py` now accepts two new constructor parameters:

| Parameter | Type | Default | Effect |
|---|---|---|---|
| `auto_loop_enabled` | `bool` | `True` | Global on/off — when `False`, every phase runs exactly once (no retry) |
| `enabled_phases` | `set[str] \| None` | all five | Per-phase set — phases not in this set run once even if global is on |

Implementation: `_phase_retry_allowed(phase)` returns `False` when global is off OR phase is not in `enabled_phases`. `_run_phase` sets `max_attempts = 1` when retry is disallowed.

### 2. Forum knowledge base — `forum_knowledge.py`

35 `ForumEntry` instances sourced from discuss.cryosparc.com, covering five QC gates:

| Gate | Entries | Highest confidence |
|---|---|---|
| `motion_drift` | 8 | `confirmed` (developer) |
| `ctf_fit_quality` | 7 | `confirmed` (developer confirms 0.3 native threshold) |
| `junk_fraction` | 8 | `reported_worked` |
| `orientation_anisotropy` | 7 | `reported_worked` |
| `abinitio_class_score` | 5 | `suggested` only (known gap — documented in tests) |

Key finding documented in tests: CryoSPARC's native CTF threshold is **0.3** (developer-confirmed), while BioMate's `qc_evaluator` uses **0.70** — a known discrepancy.

### 3. Standalone demo server — `server.py`

Pure Python `ThreadingHTTPServer` at port 7788. Zero BioMate dependencies in the HTTP layer. Serves a BioMate-style dark-theme UI:

- Top nav + sidebar matching BioMate visual language
- Left panel: phase timeline (5 rows with animated state icons: idle / running / retrying / passed / escalated)
- QC & Auto-Loop Settings collapsible (open by default):
  - Global toggle (styled switch, `#global-toggle`)
  - Per-phase chips A–E (`data-phase` attribute, `on`/`off`/`disabled-global` classes)
  - Scenario, QC profile, max-retries inputs
  - Confirm & Run button
- Right panel: live SSE event stream (`.t-<type>` class per event, `.ev-cit` spans for citations)
- Summary badges after run (`#summary-row`)

**API endpoints:**
- `POST /api/run` — starts run in daemon thread, returns `{"run_id": "xxxxxxxx"}`
- `GET /api/events/:run_id` — SSE stream (`text/event-stream`); replays stored events for late connections

### 4. E2E Playwright test suite — `tests/test_e2e_ui.py`

13 tests (AL-1 through AL-13) running against `http://localhost:7788`:

| ID | What it tests |
|---|---|
| AL-1 | Toggle label + phase chips visible on page load |
| AL-2 | Global toggle defaults to ON |
| AL-3 | Toggle OFF → `disabled-global` class on all phase chips |
| AL-4 | Per-phase chips togglable ON↔OFF individually |
| AL-5 | Chips re-enable when global turned back ON |
| AL-6 | All ON + `retry_then_pass` → `autoloop_phase_start` rows for all 5 phases |
| AL-7 | Global OFF → zero `autoloop_update` rows |
| AL-8 | phase_A chip OFF → no `autoloop_update` row for phase_A |
| AL-9 | `autoloop_update` rows contain phase name and retry number |
| AL-10 | `autoloop_update` rows have `.ev-cit` span with citation keyword |
| AL-11 | Run completes → `#summary-row` shows phase badges |
| AL-12 | Escalation scenario → no JS console errors |
| AL-13 | `POST /api/run` returns run_id; `GET /api/events/:id` returns `text/event-stream` |

---

## Bugs Found and Fixed During Audit

### Bug 1 — Single-threaded HTTP server blocks under Playwright

**Root cause:** `HTTPServer` (single-threaded) couldn't handle Chromium's concurrent connections (page load + SSE + prefetch).  
**Fix:** Replaced with `ThreadingHTTPServer(ThreadingMixIn, HTTPServer)` with `daemon_threads = True`.

### Bug 2 — QC panel collapsed by default, blocking all interactions

**Root cause:** `<div class="qc-body" id="qc-body" style="display:none">` — settings panel hidden on load.  
**Fix:** Removed `style="display:none"`; added `open` class to the trigger button. Panel now starts expanded.

### Bug 3 — ISO timestamp string multiplied by 1000 → NaN → `Invalid time value` exception

**Root cause:** `ProgressReporter` emits `ts` as ISO string (`"2026-04-17T04:36:03+00:00"`). Server HTML JS did `new Date(evt.ts * 1000)`. String × 1000 = NaN. `new Date(NaN).toISOString()` throws. Exception killed `appendEventRow` before `list.appendChild(row)` — all 22 event rows were silently dropped except `run_complete` (which has no `ts` field).  
**Observed symptom:** Event list showed only 1 row (the final `run_complete`) after any run.  
**Fix:**
```js
const d = typeof tsRaw === 'number' ? new Date(tsRaw * 1000) : new Date(tsRaw);
ts = isNaN(d.getTime()) ? '––' : d.toISOString().slice(11, 23);
```

### Bug 4 — `onGlobalToggle()` used wrapper opacity instead of `disabled-global` class

**Root cause:** `onGlobalToggle()` set `wrap.style.opacity` and `wrap.style.pointerEvents` on the wrapper div instead of toggling `disabled-global` class on individual chips.  
**Fix:** Replaced with `c.classList.toggle('disabled-global', !on)` per chip.

---

## Test Counts (final)

```
tests/test_e2e_ui.py       13 tests   (Playwright E2E — standalone server)
tests/test_truth_based.py  36 tests   (forum knowledge + toggle logic)
tests/test_ux_demo.py      26 tests   (SSE events, scenarios, reporters)
─────────────────────────────────────
Total                      75 tests   75 PASSED
```

---

## How to Run

```bash
# Start standalone server (required for E2E tests)
cd /home/yzhang/biomate/backend/experiments
python cryo_em_autoloop_ux/server.py &

# Run all tests
python -m pytest cryo_em_autoloop_ux/tests/ -v

# Open browser UI
http://localhost:7788
```

---

## Files Modified This Session (experiment module only)

| File | Change |
|---|---|
| `cryo_em_autoloop_ux/ux_loop.py` | Added `auto_loop_enabled`, `enabled_phases`, `_phase_retry_allowed()` |
| `cryo_em_autoloop_ux/forum_knowledge.py` | Created: 35 ForumEntry instances across 5 gates |
| `cryo_em_autoloop_ux/__init__.py` | Added exports: `FORUM_ENTRIES`, `ENTRIES_BY_GATE`, `ForumEntry` |
| `cryo_em_autoloop_ux/demo.py` | `run_scenario()` now accepts `auto_loop_enabled`, `enabled_phases`, `reporter` |
| `cryo_em_autoloop_ux/server.py` | Created: ThreadingHTTPServer, BioMate-style UI, `/api/run` + `/api/events` endpoints; 4 bugs fixed |
| `cryo_em_autoloop_ux/tests/test_truth_based.py` | Created: 36 truth-based tests for forum knowledge + toggle controls |
| `cryo_em_autoloop_ux/tests/test_e2e_ui.py` | Created: 13 Playwright E2E tests |
