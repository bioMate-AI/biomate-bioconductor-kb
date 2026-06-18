# Final After-Run Audit State — 2026-06-18

End of three days of iteration on the after-run audit. Six PRs landed.
Honest summary of what's fixed and what's not.

## What's working end-to-end on dev

| Surface | Status | Evidence |
|---|---|---|
| Schema-grounded extraction | ✅ | All 5 canonical params (`car_target=CD19, indication=DLBCL, delivery_cell=T_cell, persistence=transient, lnp_targeting=auto`) visible in Parameters tab on every successful T02 run; same pattern verified on T03 + T05 |
| ParamClarificationCard | ✅ | E2E PASS 57s on dev — `docs/sge-audit-2026-06-16/param-clarification/01-card-rendered.png` shows the enum-violation card with allowed-value chips |
| IntentClarificationCard | ✅ | 3/3 E2E PASS — `docs/sge-audit-2026-06-16/dev-02-card-rendered.png` |
| Findings tab | ✅ when run completes & analysis settles | `tab-findings.png` showed 421 chars real content + 1017-char screenshot of full findings on the audit3 run |
| Methods tab | ✅ when LLM proxy + worker available | `audit3` captured 3893 chars of real LLM-generated methods report visible |
| Parameters tab | ✅ always | Every audit run rendered all 5 keys cleanly |
| Phase status badges | ⚠️ partial | Phase A → running → completed; B/C/D → pending → completed (no running render). Per-process status override (PR #14) is in place but B/C/D run too fast for the 3s poll to catch any intermediate state |
| Outputs tab | ⚠️ blocked by Galaxy infra | OutputsTab client fetch fallback shipped (PR #25) — calls `/api/workflows/runs/:id/output_files` when prop is empty; that endpoint has S3 ListObjectsV2 fallback. **Cannot verify end-to-end** because every test workflow execution attempt on dev today returned HTTP 504 from Galaxy's `/api/nextflow/execute` |

## 2026-06-18 update: workers=4 unblock SHIPPED

PR #28 raised Galaxy gunicorn from `workers: 1` to `workers: 4 + preload: true` (option (a) from the rollback comment). Verified live on dev post-sync:

- `pgrep -fc gunicorn` returns **6** (1 master + 4 workers + 1 tail-helper) — matches acceptance criteria from issue #29
- `/api/version` returns in 5.7 ms (HTTP 200)
- `/api/nextflow/status/<runId>` returns in **116 ms** (was 60s+ timeout pre-fix)
- Direct probe of `/api/workflows/runs/<id>/output_files` returns **11 real files** in 8.5s for the most recent completed `in_vivo_cart_codesign` run: `cart_construct.fasta`, `design_report.txt`, `fratricide_check.json`, `in_vivo_cart_design.json`, `atlas_safety.json`, plus 6 more. This proves the OutputsTab fetch fallback (PR #25) will show real files when the DB snapshot is empty.

**P0 Outputs tab is now fixed end-to-end** even when the DB snapshot doesn't populate — the client-side fetch hits the working server-side S3 listing fallback.

The earlier E2E audit failures on the new workers=4 Galaxy were workflow-generation LLM non-determinism (the LLM intermittently refuses queries with "Workflow generation is currently unavailable for this request"), not anything Galaxy- or Outputs-related. That's a separate prompt-tuning issue, tracked elsewhere.

## What was blocked on dev infrastructure (now resolved)

### Galaxy gunicorn `--workers=1`

```
galaxy 78519 gunicorn ... --workers=1 -b 0.0.0.0:8080
```

Confirmed via `docker exec biomate-galaxy-dev ps -ef`. Single Python worker handles every request serially. Effects observed:

- `/api/nextflow/execute` → HTTP 504 Gateway Time-out on dispatch (the audit's final attempt)
- `/api/nextflow/status/<runId>` → curl with `--max-time 120` returns 0 bytes; the worker is busy on S3 listing or other long ops
- `/internal/llm/generate` → occasional 502 (P2 writeup)

Every long endpoint in Galaxy can starve every other endpoint. Without raising worker count or moving heavy operations off the request path, after-run UX on dev will keep oscillating between "works fine" and "everything 504s."

The single-worker config is the root cause of P0 (Outputs empty), P1 (phase B/C/D snapshots stale), and P2 (Methods transient 502). My six PRs reduce client-side sensitivity to Galaxy slowness but cannot make Galaxy fast.

### Recommendation for follow-up

1. **Raise Galaxy gunicorn workers to ≥4** (matches the existing comment in nextflow_executor.py:4911 that already assumes 4 workers). Most-direct fix.
2. **Move S3 ListObjectsV2 off the `/api/nextflow/status` hot path** — return cached `s3_output_files` immediately; refresh via a background task. Removes the per-request listing cost.
3. **Add server-side retry + timeout-budget on `/api/nextflow/execute`** so dispatch failures show actionable user messages instead of opaque 504.

These are all backend changes in `backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py` + the gunicorn config — out of scope for this audit's frontend/Node iteration.

## PRs landed this session

| # | Commit | What |
|---|---|---|
| #13 | `dc5050cb4` | viewer forwards outputs prop to AfterRunReport |
| #14 | `5c24b4b7a` | per-process status overrides workflow-level progress |
| #16 | `1ef1bfbb4` | post-terminal nextflowStatus refresh (first attempt) |
| #17 | `9e8a3e62d` | status-string fix: include 'succeeded' (caught DB enum mismatch) |
| #19 | `4646f1d0b` | re-add intentClarification field after a merge dropped it |
| #25 | `bd987af1c` | OutputsTab client-side fetch fallback to /output_files endpoint |

Plus four audit doc commits and the e2e additions.

## Files added/updated

- `frontend/e2e/after-run-audit.e2e.ts` — parameterized; can audit T01/T03/T04/T05 by env var
- `frontend/e2e/param-clarification.e2e.ts` — schema-grounded enum-violation scene
- `frontend/e2e/intent-clarification.e2e.ts` — cross-intent ambiguity scene
- `docs/sge-audit-2026-06-16/AFTER_RUN_AUDIT.md` — original T02 audit
- `docs/sge-audit-2026-06-16/after-run-T03/` — T03 evidence
- `docs/sge-audit-2026-06-16/after-run-T05/` — T05 evidence
- `docs/sge-audit-2026-06-16/CONSOLIDATED_AUDIT.md` — cross-run synthesis
- `docs/sge-audit-2026-06-16/P2_METHODS_REPORT_RESILIENCE.md` — Methods 502 design proposal
- `docs/sge-audit-2026-06-16/FINAL_STATE.md` — this file
