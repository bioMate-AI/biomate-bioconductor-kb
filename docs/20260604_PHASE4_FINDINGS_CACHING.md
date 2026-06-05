# Phase 4 — findings_analysis caching via async job system (2026-06-04)

Shipped + validated end-to-end on dev.

## What changed

| Commit | What |
|---|---|
| `21100fbf2` | `feat(jobs): Phase 4 — findings_analysis caching + cancellable polling` |

Files:
- `frontend/server/jobs/handlers/findings-analysis.ts` — new handler
- `frontend/server/routes.ts` — register import
- `frontend/client/src/v2/AfterRunReport.tsx` — `useFetchFindings` drops bespoke poll, uses job system

## Design

The legacy endpoint `GET /api/workflows/runs/:id/findings` returns:
- `{ status: 'ready', summary, key_results, caveats, next_steps, ... }` if a sidecar exists
- `{ status: 'pending' }` if it kicked off an async Claude analysis

Frontend used to poll every 5s for up to 60s — bespoke logic, no cancel,
gives up silently if Claude takes >60s.

The handler **server-side polls** the legacy endpoint every 3s until
`status: ready` (5-min cap), then writes the JSON payload as the
artifact. Frontend's `useFetchFindings` now POSTs once to `/api/jobs`
and polls the job state instead.

What this buys:
- **Server-driven polling** — one tab → one server-poll; N tabs → one
  server-poll (instead of N × bespoke client polls).
- **Race-free dedup** — verified by firing 3 concurrent POSTs and
  observing exactly 1 row in `download_jobs` for the dedup_key.
- **24h cache** — re-open within the window returns identical bytes
  in <250ms instead of re-triggering the legacy analysis.
- **Visible cancel** — wired through `ctx.checkCancelled` (DELETE
  `/api/jobs/:id` stops the server polling loop).
- **No arbitrary 60s give-up** — handler caps at 5 min and surfaces a
  proper error if Claude really takes longer.

## End-to-end validation on dev

Synthetic `execution_run` rows pointing at the same real cryo-EM S3
prefix used in Phase 2 / Gap B. Cleaned up after.

### Latency

| Path | Time |
|---|---|
| Cold (handler enqueued → legacy poll → ready) | ~10s |
| Warm (cache hit via dedup) | **236ms** |

### Content fidelity

The handler is a transparent wrapper — its artifact is byte-for-byte
identical to what the legacy endpoint returns when called directly:

```
$ diff /tmp/findings_job.json /tmp/findings_warm.json
(no output — identical)
```

All 7 expected keys present (`status, summary, key_results, caveats,
next_steps, reportUrl, runId`). Summary text references real S3 source
data (27,627 particles, 150 Å diameter, 20 micrographs).

### Race-free dedup

3 concurrent POSTs for the same `(kind, runId)`:

```
$ SELECT id FROM download_jobs WHERE dedup_key='findings_analysis:<runId>';
db45f763-556d-46ba-94f9-42244279b4b8
(1 row)
```

Despite 3 simultaneous inserts, the `dedup_key` unique index plus the
`SELECT ... WHERE state IN (queued, running, ready)` lookup in the
router collapsed them to a single job. No racing inserts won.

## Pre-existing bug surfaced (not Phase 4 — file separately)

The legacy endpoint's `key_results`, `caveats`, and `next_steps` arrays
are **always empty** in the response, even when Claude clearly produced
structured output. The `summary` field instead contains a stringified
JSON blob:

```
{
  "summary": "{\n  \"summary\": \"The CryoSPARC SPA test workflow successfully processed 20 movies...\",\n  \"key_results\": [...],\n  \"caveats\": [...],\n  \"next_steps\": [...]\n}",
  "key_results": [],
  "caveats": [],
  "next_steps": []
}
```

The endpoint passes Claude's JSON-string response into `summary` instead
of parsing it and splitting into the structured fields. The frontend
FindingsCard reads `key_results` directly — so the bulleted key-results
panel is **silently always empty** for AWS Batch runs without a
pre-existing `findings_data.json` sidecar.

Phase 4 mirrors this faithfully (its job is parity, not fixing legacy).
Filing the parsing bug as a separate ticket in `docs/20260604_LEGACY_FINDINGS_PARSING_BUG.md`.

## Async-job-queue subsystem — completion state

After this session, all 4 originally-planned phases plus Gap B fix are
shipped:

| Phase | Status | Coverage |
|---|---|---|
| 0 | shipped 2026-06-03 | tracking table + executor + router + JobButton + useJob hook |
| 1 | shipped 2026-06-03 | `download_all_zip` handler |
| 1 Gap B fix | shipped 2026-06-04 | pipeline-native source resolution |
| 2 | shipped 2026-06-04 | `methods_report` cache (50× warm speedup) |
| 3 | DEFERRED | `reproducibility_bundle` — not useful enough yet |
| 4 | shipped 2026-06-04 | `findings_analysis` cache + race-free dedup |

The job system has 3 live `kind`s and a stable contract. Adding a 5th
(`docx_export` from the design doc, or anything else) is now a ~150 LOC
handler.

## Open follow-ups

- **Legacy findings parsing bug** — file + fix. See above.
- **Branding scrub Phase 1.6** — mid-investigation when Phase 4 took
  priority. Server field rename + URL path rename for the remaining
  `nextflow`-suffixed user-facing surfaces.
- **Phase 2.1** — wire the AfterRunReport's docx download to the
  `methods_report` handler with `format: 'docx'` (handler already
  supports it).
