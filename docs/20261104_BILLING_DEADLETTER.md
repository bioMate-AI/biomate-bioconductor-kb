# Billing cost-event dead-letter (C1 / C2 / M1)

Date: 2026-11-04
Scope: money path. **Needs review + a live test before it can be trusted — see "What must be live-tested" at the end. No live verification has been performed.**

## Problem

Cost/usage events were silently dropped on a transient Redis error, with no
dead-letter. During a Redis (ElastiCache) outage this under-counted usage and
under-enforced quota, and — because Lago is disabled by default under flat-tier
billing (`lago_enabled()` → off) — there was **no backing ledger** to recover the
lost events.

Audited exception sites:

- **C1** `realtime_cost_service.record_batch_job_cost` (~103-127): a whole Batch
  job's compute cost was `log.warning(...)`-and-forgotten on a Redis blip.
- **C2** `realtime_cost_service.record_llm_cost` (~90-101): same pattern, AND
  double-swallowed by `billing_router.internal_llm_cost` (~505-517), which then
  returned HTTP 200 as if the cost had been recorded.
- **C1-adjacent** `realtime_cost_service.record_s3_put` (~159): same pattern.
- **M1** `billing_internal.record_llm_cost` (~176-178): returned
  `{status: error}` with **HTTP 200** and only `str(exc)`; the durable
  file-cost-log write was inside the broad swallow.

## Fix (correctness-first, no new double-charge risk)

On a **Redis write failure** the event is no longer dropped. It is appended to a
**durable, append-only JSON-lines dead-letter file**. The dead-letter write is
best-effort but **LOUD**: if it also fails, we log at `ERROR` (total loss is
visible) and the endpoint returns **5xx** so the caller knows the event was lost.

We intentionally did **not** implement the reconciliation consumer (replaying the
dead-letter into Redis/Lago). This pass delivers a well-specified, durable
dead-letter plus this doc. The reconciliation plan is specified below.

Lago is left exactly as-is: the `if not lago_enabled(): return` no-ops are
intentional under flat-tier billing and were not touched.

## Dead-letter file

- **Location:** `$BIOMATE_COST_LOG_DIR/billing_deadletter.jsonl`
  (same durable directory as the existing file cost-log `llm_costs.jsonl`;
  default `/tmp/biomate-cost-logs`). Reuses `cost_log._WRITE_LOCK` for
  thread-safety and the same append-only JSONL convention.
- **Writer:** `galaxy.ai.cost_log.record_deadletter(event_type, payload, reason, txn_id=None) -> bool`
  - Returns `True` if durably persisted, `False` on total loss. Never raises.
  - Writes `fh.write + flush + os.fsync` (a failed `fsync` on an already-written
    line is downgraded to a WARNING and still counts as persisted — it must not
    produce a false 5xx that could trigger a retry double-write).

### JSONL schema (one object per line)

| field        | type   | meaning                                                          |
|--------------|--------|------------------------------------------------------------------|
| `txn_id`     | string | stable idempotency id, `dl_` + 32 hex (see below)                |
| `ts`         | string | ISO-8601 UTC capture time                                        |
| `ts_ns`      | int    | `time.time_ns()` at capture (part of the idempotency hash input) |
| `event_type` | string | `llm_cost` \| `batch_job_cost` \| `s3_put`                       |
| `reason`     | string | `repr()` of the Redis exception (truncated to 1000 chars)        |
| `payload`    | object | the full event payload (see per-type fields below)              |
| `replayed`   | bool   | always `false` on write; a future reconciler flips it            |

Per-type `payload` fields:

- `llm_cost`: `user_id, input_usd, output_usd, input_tokens, output_tokens, month`
- `batch_job_cost`: `user_id, job_id, vcpu_usd, gpu_usd, mem_usd, duration_seconds, month`
- `s3_put`: `user_id, size_bytes, storage_usd, request_usd, object_key, month`

`month` is captured at write time (`YYYY-MM`) so a later replay credits the correct
billing period rather than the replay-time month.

### Idempotency / transaction id

`cost_log._deterministic_txn_id(event_type, payload, ts_ns)` =
`"dl_" + sha256(json.dumps({event_type, payload, ts_ns}, sort_keys=True))[:32]`.

- It is computed **once** at dead-letter write and **stored in the line**, so
  replaying the same line always yields the same id — a reconciler can dedupe
  (e.g. use it as the Lago `transaction_id`, or as a member of a processed-set).
- The existing Lago client uses a **random** `uuid4` transaction id (not stable),
  so it cannot be reused for replay dedupe; hence the deterministic derivation.
- `ts_ns` is included so two otherwise-identical events do not collapse to one id.

## Endpoint status-code semantics

`record_llm_cost` / `record_batch_job_cost` / `record_s3_put` in
`realtime_cost_service` now **return a durability string**:
`"redis"` (primary write ok) · `"deadletter"` (Redis failed, durably queued) ·
`"lost"` (Redis **and** dead-letter both failed). Return value is additive;
existing callers that ignore it are unaffected.

| Endpoint | Redis ok | Redis failed → dead-letter ok | both failed |
|----------|----------|-------------------------------|-------------|
| `billing_router POST /internal/billing/llm_cost` | 200 `{ok, durability:"redis"}` | 200 `{ok, durability:"deadletter", queued:true}` | **503** |
| `billing_router POST /internal/billing/job_completed` | 200 `{ok, durability:"redis"}` | 200 `{..., durability:"deadletter", queued:true}` | **503** |
| `billing_router POST /internal/billing/s3_put` | 200 `{ok, durability:"redis"}` | 200 `{..., durability:"deadletter", queued:true}` | **503** |
| `billing_internal POST /internal/billing/llm_cost` | 200 `{status:"recorded", realtime_durability, file_log_ok}` | 200 `{..., durability:"deadletter", queued:true}` | **503** |

`billing_internal` additionally has the **file cost-log** (`llm_costs.jsonl`) as a
primary durable audit sink. Its rule: the event is durable if **the file log
succeeded OR the realtime ledger landed in Redis/dead-letter**. It returns 503
only when the event is durable **nowhere** (file log failed AND realtime == lost).
`cost_log.record()` now returns a bool so this can be decided; Lago forwarding was
moved out of the durability path so a Lago hiccup can no longer make the audit
write look failed.

The old `billing_internal` behavior — catch-all → `return {status:"error"}` with
**HTTP 200** — is removed; a genuinely unexpected exception now surfaces as 500.

## Reconciliation plan (NOT implemented in this pass)

A separate, idempotent consumer (cron or on Redis-recovery) should:

1. Read `billing_deadletter.jsonl` line by line.
2. Skip lines where `replayed == true` or whose `txn_id` is already in a durable
   processed-set (dedupe — safe to run repeatedly / after a crash).
3. Re-apply each `payload` to Redis via the matching `record_*` method for the
   stored `month`; if Lago is re-enabled, emit with `txn_id` as the Lago
   transaction id so Lago dedupes too.
4. On success, mark the line `replayed` (rewrite-compact or append a tombstone)
   and add `txn_id` to the processed-set.
5. Never delete the file in place without an atomic compaction; keep a rotated
   copy for audit.

Because every record carries a stable `txn_id` and the captured `month`, replay
is safe to run more than once without double-counting.

## Files changed

- `backend/lib/galaxy/ai/cost_log.py` — `record()` returns `bool`; Lago
  forwarding moved out of the durability path; added `_DEADLETTER_FILE`,
  `_deterministic_txn_id`, `record_deadletter`.
- `backend/lib/galaxy/ai/billing/core/realtime_cost_service.py` — durability
  constants; `_deadletter` helper; `record_llm_cost` / `record_batch_job_cost` /
  `record_s3_put` dead-letter on Redis failure and return a durability string.
- `backend/lib/galaxy/webapps/galaxy/api/billing_internal.py` — removed the
  HTTP-200-on-error swallow; durable-sink decision; 503 on total loss; `queued`
  flag on dead-letter.
- `backend/lib/galaxy/ai/billing/api/billing_router.py` — `internal_llm_cost`,
  `internal_job_completed`, `internal_s3_put` surface durability, 503 on total
  loss, `queued` flag on dead-letter.

## Gate results

- `python3.9 -m py_compile` on all four changed files: **PASS**.
- Focused billing unit tests (`test_billing_regression.py`, `test_billing.py`):
  **could not run** in this worktree — collecting the test package triggers
  `galaxy.ai` package init which imports sklearn/scipy, and this environment has a
  scipy/sklearn binary incompatibility (`messagestream size changed`) that fails
  collection independently of this change. Must be run in the CI/dev image.
- Standalone behavior check (no heavy deps) exercised: deterministic txn id
  stability, dead-letter JSONL write + schema, all three `record_*` returning
  `deadletter` under a failing Redis (and `batch_job_cost` still popping the
  running-job entry), all three event types landing in the file, and the `lost`
  path when the dead-letter write also fails. All passed.

## What must be reviewed / live-tested before merge

This is the money path. **No live verification was done.** Before trusting:

1. **Induce a real Redis failure** (point `REDIS_URL` at a closed port, or block
   ElastiCache) and confirm: (a) the event lands in
   `$BIOMATE_COST_LOG_DIR/billing_deadletter.jsonl` with the right schema, (b) the
   endpoint returns 200 with `queued:true` / `durability:"deadletter"`.
2. **Induce total loss** (Redis down AND `BIOMATE_COST_LOG_DIR` non-writable) and
   confirm the endpoint returns **503** and an `ERROR` log line is emitted.
3. Confirm callers of `/internal/billing/*` (the Node frontend, the Batch billing
   Lambda, the S3 Lambda) **tolerate a 503** sensibly — ideally retry with
   backoff. **Review the retry behavior for double-charge risk**: there is no
   end-to-end idempotency on the normal (Redis-ok) path today (pre-existing), so a
   client that retries a 503 after the dead-letter actually persisted could enqueue
   a duplicate. The `fsync`-before-success ordering minimizes but does not
   eliminate this; a true fix is end-to-end idempotency keys, out of scope here.
4. Verify `BIOMATE_COST_LOG_DIR` on dev points at a **persistent** volume, not an
   ephemeral container path, or the dead-letter is lost on container recycle.
5. Build and implement the reconciliation consumer (above) before relying on the
   dead-letter for billing accuracy — until then, dead-lettered events are durable
   but **not yet re-applied** to the ledger.

---

## Reconciliation consumer — IMPLEMENTED (2026-11-04)

`backend/lib/galaxy/ai/billing/core/reconcile.py` now implements the plan above.

- Entry: `reconcile_deadletter(service=None, dry_run=False)` or CLI
  `python -m galaxy.ai.billing.core.reconcile [--dry-run]`.
- **Idempotency (no double-count):** before replaying an event it atomically claims
  a durable Redis marker `billing:recon:done:<txn_id>` via `SET ... NX EX 90d`. Only
  the claimer replays; a re-run or crash-retry sees the marker and skips. The
  deterministic `txn_id` makes the marker stable across runs. Trade-off: a crash in
  the tiny window between claim and the Redis increment UNDER-counts that one event
  (prefers under-count to over-charging).
- **Month-targeted:** replays via `record_*(..., month=<captured month>)` — the three
  `record_*` methods gained an optional `month` kwarg (default `None` → current
  month; only the reconciler passes it). Credits the ORIGINAL billing period.
- **Redis down** (the reconciler should only run when Redis is up): the marker claim
  raises → the run aborts cleanly, keeps all lines, applies nothing, retry later.
- **Compaction:** after a pass the dead-letter is rewritten keeping only
  unreconciled lines, after an atomic timestamped `.bak` backup.

**Verified (local, fake redis + fake service — no remote writes):** month-targeted
replay, NX-marker idempotency (re-run applies nothing), redis-down abort, compaction
+ backup, dry-run no-op. See the session's local test.

**Still owed before trusting in production (money path):**
1. An end-to-end replay against a REAL Redis (throwaway user) — the local test fakes
   `record_*`; the real month-targeting path (1-line change, compiles) is unexercised
   against live Redis. Blocked here only because writing modified source into the dev
   container / writing dev Redis is restricted; run it on the dev/CI image.
2. **Wire a trigger** — this module does NOT schedule itself. Add a cron (e.g. every
   5 min) or an on-Redis-recovery hook that runs the CLI. Pick a cadence; it is safe
   to run concurrently-serialised (it takes the cost-log write lock) and repeatedly.
3. Ensure `BIOMATE_COST_LOG_DIR` is a persistent volume (same prerequisite as the
   dead-letter writer) so the file survives restarts for the reconciler to drain.

### Trigger wiring — IN PLACE, disabled by default (2026-11-04)

`reconcile.start_reconcile_scheduler()` is a flag-gated background loop, wired into
`get_cost_service()` so it arms itself the first time the billing service is used —
but **only when enabled**. Disabled by default (no thread, no behaviour change).

**To turn it on** (one env var on the Galaxy container, then restart it):
```
BILLING_RECONCILE_ENABLED=1            # off by default; "1"/"true"/"yes"/"on" enables
BILLING_RECONCILE_INTERVAL_SEC=300     # optional, default 300s, min 60s
```
The scheduler then runs `reconcile_deadletter()` every interval on a daemon thread
(errors in one pass never kill the loop; it is idempotent via the Redis NX markers).

**Alternative (cron / no in-app thread):** run the CLI on a schedule instead —
`python -m galaxy.ai.billing.core.reconcile` (add `--dry-run` to preview). Leave
`BILLING_RECONCILE_ENABLED` unset so the in-app loop stays off; the CLI and the
scheduler share the same idempotent core, so don't run both.

**Prerequisite either way:** `BIOMATE_COST_LOG_DIR` must be a persistent volume, or
the dead-letter file (and thus anything to reconcile) is lost on a container restart.
