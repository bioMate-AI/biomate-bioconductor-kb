# ANSI Escape Code Fix — Terminal Output Rendering

**Date**: 2026-04-20  
**Branch**: integration/next-phase

## Problem

Workflow execution log panels in BioMate displayed raw ANSI escape sequences
instead of clean text.  Examples seen in Demo 1 (docking results) and Demo 4
(PK/PD dose prediction) screenshots:

```
[2A[K[33m200[39m[2A[KN-DIMETHYL-3-PHENYL
N15: 100%|████████| 1/1 [00:03<00:00,  3.22s/it][2K[1A[2K
```

This made the execution logs unreadable for users watching demos or reviewing
workflow results.

## Root Cause

Log lines are read directly from Nextflow/tool log files and emitted to the
frontend as-is.  CLI tools (Nextflow progress bars, AutoDock Vina, PBPK
scripts, tqdm progress indicators) emit ANSI control sequences for terminal
color and cursor movement.  These sequences are harmless in a real TTY but
appear as garbage characters when rendered in an HTML `<pre>` element.

## Fix

### Backend — `nextflow_executor.py`

Added `_ANSI_ESCAPE_RE` / `_strip_ansi()` utility function and applied it at
all three `log_tail` construction sites:

- `log_tail_fallback` (fallback status endpoint, line ~2648)
- `log_tail` (primary status endpoint, line ~2819)
- `log_lines` (pipeline validation endpoint, line ~4656)

This ensures clean data is emitted in the API response JSON.

### Frontend — `src/lib/utils.ts`

Added exported `stripAnsi(str: string): string` using the same regex pattern.
Provides a second layer of defence for any ANSI codes that reach the client
through other code paths.

### Frontend — `nextflow-workflow-viewer.tsx`

- Main execution log panel (line ~2577): `{log}` → `{stripAnsi(log)}`
- Validation log panel (line ~2033): `{validateLog.join('\n')}` →
  `{validateLog.map(stripAnsi).join('\n')}`

### Frontend — `step-output-preview.tsx`

- `InlineTextViewer`: strips ANSI from fetched file text before splitting
  into lines and rendering in `<pre>`.
- `structure` viewer text fallback: strips ANSI from PDB/mmCIF text.

### Frontend — `job-log-viewer.tsx`

- `parseLogEntry`: strips ANSI from the raw log message during parsing,
  so filtered/structured views are also clean.

## Files Changed

| File | Change |
|------|--------|
| `backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py` | `_strip_ansi()` helper + 3 call sites |
| `frontend/client/src/lib/utils.ts` | `stripAnsi()` export |
| `frontend/client/src/components/nextflow-workflow-viewer.tsx` | Import + 2 render sites |
| `frontend/client/src/components/step-output-preview.tsx` | Import + `InlineTextViewer` + structure fallback |
| `frontend/client/src/components/job-log-viewer.tsx` | Import + `parseLogEntry` |

## Verification

Frontend build: `npm run build` — ✓ clean (5.86s, no new warnings)  
Backend reload: `kill -HUP <gunicorn-master>` — ✓ workers reloaded, API responding
