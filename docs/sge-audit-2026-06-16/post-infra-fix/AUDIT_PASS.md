# After-Run Audit — PASS on Dev (post workers=4 + S3 TTL cache)

Date: 2026-06-18  
Branch: `worktree-schema-grounded` (merged via PR #28, #32, #33)  
Test: `frontend/e2e/after-run-audit.e2e.ts`  
Result: **1 passed (4.7 minutes)**

## Summary

```json
{
  "finalStatus": "completed",
  "phaseCount": 4,
  "phasesTerminal": 4,
  "tabsVisible": 4,
  "tabsWithContent": 4
}
```

All four phases reached terminal state; all four visible after-run tabs (Findings, Outputs, Methods, Parameters) rendered with content. The Outputs tab — previously blocked by Galaxy's single-worker + uncached S3 ListObjectsV2 — is now populated end-to-end through the UI.

## Evidence

- `tab-outputs-POPULATED.png` — Outputs tab with file list (`PROVENANCE_STATUS.txt`, design report, interactive analysis links)
- `03-completion.png` — full panel after completion

## Stack that landed this

| PR | What |
|---|---|
| #28 | Galaxy gunicorn `workers: 4 + preload: true` (vs. workers=1 single-threaded) |
| #25 | OutputsTab client-side fetch fallback to `/api/workflows/runs/:id/output_files` |
| #32 | Docs — verified `/output_files` returns 11 real files in 8.5s |
| #33 | 10s TTL cache on `_list_s3_output_files` collapses 3 polls→1 S3 call |

## Latency (post-deploy probe)

| Call | Latency |
|---|---|
| 1 | 0.72s |
| 2 | 0.51s |
| 3 | 0.58s |

Pre-stack: 8.5s per call. Now consistently <1s. ~15× speedup.

The P0 Outputs UX gap is closed.
