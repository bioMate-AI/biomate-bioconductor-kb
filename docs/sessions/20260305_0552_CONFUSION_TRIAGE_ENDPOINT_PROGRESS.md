# Confusion Triage Endpoint Progress (2026-03-05 05:52)

## Objective

Add a backend-facing triage endpoint that summarizes `workflow.confusion_signal` telemetry by run lineage (`rootRunId`) so PM/ops can inspect clustered user confusion patterns without scanning raw events.

## Changes Implemented

- `frontend/server/telemetry-service.ts`
  - Added confusion triage types:
    - `TelemetryConfusionFilters`
    - `ConfusionTriageRow`
  - Added payload parsing and normalization helpers.
  - Added `aggregateConfusionEvents(...)` exported aggregator:
    - groups by `rootRunId` (fallback: `runId`, then `unknown_run`)
    - computes `totalSignals`, `signalsByType`, `runIds`, `sessionIds`
    - tracks `latestSignalAt` and `latestSeverity`
    - sorts by highest signal volume then recency
  - Added `getConfusionTriage(...)` service method with:
    - optional `from`, `to`, `limit`
    - DB filtering on `event = workflow.confusion_signal`
    - payload extraction from `telemetry_events.payload`

- `frontend/server/routes.ts`
  - Added `GET /api/telemetry/confusion-triage`
    - query params: `from`, `to`, `limit`
    - response shape:
      - `totalGroups`
      - `rows: ConfusionTriageRow[]`
    - server error handling with `TelemetryConfusionTriageError`

## Build/Validation

- Build:
  - `npm run build` (frontend) -> success

- Runtime validation (local test server on `:5407`):
  1. Posted three synthetic `workflow.confusion_signal` events via `/api/telemetry/events`:
     - two events under `rootRunId=run-root-1` (`output_dead_end`, `retry_without_progress`)
     - one event under `rootRunId=run-root-2` (`output_dead_end`)
  2. Queried `/api/telemetry/confusion-triage?limit=10`
  3. Verified grouped output:
     - group `run-root-1` with two signals + per-signal counts
     - group `run-root-2` with one signal
     - preserved `runIds`, `sessionIds`, and latest severity/time

## Notes

- `/api/telemetry/events` is intentionally fire-and-forget (returns `204` before async insert completes), so immediate read-after-write can briefly lag. A short delay confirms full persistence and correct triage grouping.
