# Cost Persistence Implementation and Verification

## Implemented in this cycle

1) Persist incoming telemetry events
- File: `frontend/server/routes.ts`
- Change:
  - `/api/telemetry/events` now asynchronously persists events via `telemetryService.create(...)`
  - still returns `204` immediately (non-blocking behavior preserved)

2) Add cost event persistence on `/api/chat`
- File: `frontend/server/routes.ts`
- Change:
  - After assistant response generation, server now records `cost.chat.estimated` telemetry event
  - includes:
    - `userId`
    - `sessionId`
    - `runId`
    - `invocationId`
    - `provider`
    - `model`
    - `inputTokensEstimated`
    - `outputTokensEstimated`
    - `estimatedCostUsd`
    - `estimationMethod`
  - estimation uses `TokenCounter` heuristic (clearly marked as estimated)

3) Add telemetry summary API for auditing
- File: `frontend/server/routes.ts`
- New endpoint:
  - `GET /api/telemetry/summary`
  - returns aggregate telemetry summary (`total`, `byEventName`, `byDay`) from `telemetryService.getSummary()`

## Verification evidence

1) Chat endpoint probe (to trigger cost event)
- Command:
  - `curl -H "Content-Type: application/json" -H "X-Forwarded-Proto: https" -d '{"message":"Hello, please reply briefly."}' http://localhost:5310/api/chat`
- Result:
  - HTTP 200 with assistant response payload

2) Telemetry summary check
- Command:
  - `curl -H "X-Forwarded-Proto: https" http://localhost:5310/api/telemetry/summary`
- Result:
  - `byEventName.cost.chat.estimated = 1` observed after the chat probe
  - confirms persistence path is active

## Notes

- This adds **process-cost recording** for chat interactions, but it is still **estimated** (heuristic token counting) on the Node path.
- For true realized-cost parity with billing backend, next step is to unify this with provider-native usage + billing service writes per run/session.
