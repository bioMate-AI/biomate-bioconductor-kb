# Cost Recording Audit - Full Process

## Scope checked

- Strict release CI gate matrix run (isolated outputs, no critical skips)
- Full feedback matrix run path
- Chat/assistant path used by current E2E process
- Billing and telemetry surfaces in frontend and backend

## CI gate status

- Command run:
  - `BIOMATE_URL=http://localhost:5310 FEEDBACK_MATRIX_MODE=release E2E_ISOLATED_OUTPUTS=true STRICT_NO_SKIP_CRITICAL=true bash scripts/run-feedback-e2e-matrix.sh`
- Result:
  - PASS
- Gate artifact:
  - `frontend/e2e/matrix-runs/feedback-matrix-run-20260303_223520.txt`

## Is cost recorded across the entire process?

Short answer: **not end-to-end for the current tested flow**.

### What is recorded now

1. **E2E matrix runtime metadata**
   - Per-test durations and statuses are recorded in matrix metadata.
   - Example fields: `duration_seconds`, `total_duration_seconds`.
   - No monetary fields in matrix metadata.

2. **Billing backend capability exists**
   - Python billing router provides:
     - `/api/billing/usage`
     - `/api/billing/usage/history`
     - `/api/billing/quota`
     - internal `llm_cost`, `job_completed`, `s3_put`, etc.
   - Frontend proxy for `/api/billing/*` is wired.

3. **LLM usage appears in server logs (TS assistant)**
   - `completion.usage` is logged in `frontend/server/galaxy-assistant.ts`.

### Current gaps found

1. **Current `/api/chat` path does not persist monetary cost**
   - In the active Node/TS assistant path, usage is logged, but no persisted cost ledger write was found.
   - No `cost_usd` write in `frontend/server/routes.ts` chat flow.

2. **Telemetry endpoint is currently non-persistent**
   - `/api/telemetry/events` immediately returns 204 and does not persist payloads.
   - So no process-cost accumulation via telemetry.

3. **Billing endpoints require auth and are not part of anonymous E2E flow**
   - `/api/billing/usage` check without authorization returns validation error for missing Authorization header.
   - Current matrix tests run via chat flow without authenticated billing token context.

4. **`estimated_cost_usd` exists as schema field but is not an actual end-to-end meter**
   - Present in schema for estimation; not equivalent to full-process realized cost recording.

## Conclusion

- **Execution/runtime progress is recorded.**
- **Cost across the full process (LLM + workflow compute/storage) is not reliably recorded end-to-end in the currently exercised flow.**

## Recommended next implementation step

1. Persist cost events from `/api/chat`:
   - extract token usage from Anthropic responses
   - compute USD by model pricing
   - write per-message/per-run cost event to storage
2. Attach run/session identifiers to cost events:
   - `sessionId`, `runId`, `invocationId`, `model`, `input_tokens`, `output_tokens`, `cost_usd`
3. Make telemetry ingestion persistent (or send to billing service directly).
4. Add an E2E assertion:
   - after workflow completes, verify a cost record exists for that run/session.
