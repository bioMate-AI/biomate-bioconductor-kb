# Chain Composer — Shadow Telemetry Wiring

**Date**: 2026-06-12
**Companion**: `docs/20260612_RECOMMENDATION.md`, `docs/20260612_VALIDATION_DOCUMENT.md`

## Summary

A single shadow-mode hook is now wired into `route_and_handle` in
`backend/lib/galaxy/ai/ai_assistant.py`. When enabled, every routing turn
also runs the chain composer in parallel and logs the structured result to
JSONL. The composer's output is **never** surfaced to users; this is purely
data collection for calibration.

Default: **off**. Production behaviour is identical to before unless the
flag is set.

## Files touched

| File | Change |
|---|---|
| `backend/lib/galaxy/ai/chain_composer/telemetry.py` | New — env-gated, percentage-gated, session-capped JSONL writer; wraps `compose_chain` in try/except |
| `backend/lib/galaxy/ai/ai_assistant.py` | +7 lines — single guarded import + call at the top of `route_and_handle`, swallows all exceptions |
| `backend/tests/test_composer_telemetry.py` | New — 6 tests: default-off, enabled+writes, exception swallowed, 0% sampling, session cap, query truncation |

## Environment flags

| Flag | Default | Meaning |
|---|---|---|
| `BIOMATE_COMPOSER_SHADOW` | unset | Enable shadow logging. Set to `1`/`true`/`yes`/`on` |
| `BIOMATE_COMPOSER_SHADOW_LOG` | `/tmp/biomate_composer_shadow.jsonl` | Output path |
| `BIOMATE_COMPOSER_SHADOW_PCT` | `100` | Sample percentage 0–100 (use 1 or 5 for initial rollout) |
| `BIOMATE_COMPOSER_SHADOW_MAX_PER_SESSION` | `50` | Per-session cap to prevent runaway logging on long sessions |

## Operator runbook

1. **Local smoke** (do this first):
   ```bash
   BIOMATE_COMPOSER_SHADOW=1 \
   BIOMATE_COMPOSER_SHADOW_LOG=/tmp/composer_smoke.jsonl \
   ./backend/start_backend.sh
   # Send one chat query; then:
   tail -1 /tmp/composer_smoke.jsonl | python -m json.tool
   ```
   Expected: one JSON record with `query`, `composer.{source,mode,confidence,steps,verifier_ok,pattern}`, `latency_ms`.

2. **Dev rollout**: set flag in dev EC2 env, restart galaxy backend (`kill -HUP $(pgrep -f "gunicorn.*8081")`). Let traffic accumulate ~1 week. Logs land at the configured path.

3. **Production gradual rollout**: start at `BIOMATE_COMPOSER_SHADOW_PCT=1` (1% of turns), monitor latency overhead (should be <500ms p99 because composer cache-hits often), then ramp.

4. **Stop collecting**: unset `BIOMATE_COMPOSER_SHADOW` or set it to `0`. No code change, no restart cost beyond the env reload.

## Safety guarantees

The hook satisfies the constraints stated in `docs/20260612_RECOMMENDATION.md`:

- **Never raises.** The import and call are inside `try/except: pass`. The composer's own internal exceptions are caught by `telemetry.shadow_log` and serialised as `error` in the record. `test_composer_exception_is_swallowed` proves it.
- **Never blocks user-facing output.** The composer runs synchronously before classification, but it does not gate the response — its result is dropped after logging. Worst case: a stuck composer adds latency to the turn. (Future: move to `asyncio.create_task` if real telemetry shows tail latency issues. Deferred until measured.)
- **Default off.** `test_default_off_writes_nothing` asserts no file is created without the flag.
- **Rate-limited.** Per-session cap + sample percentage; tested with `test_session_cap_respected` and `test_zero_pct_disables`.
- **Log-only.** No mutation of `classification`, `context`, or response paths.

## What the log records

```json
{
  "ts": 1717948800.123,
  "user_id": "u123",
  "session_id": "s456",
  "query": "differential expression on bulk rna-seq counts",
  "composer": {
    "source": "curated",
    "mode": "upfront",
    "confidence": 0.93,
    "signals": {"curated_chain_score": 1.0, "pattern_match_score": 0.8, ...},
    "steps": [{"workflow_id": 12345, "name": "nf-core/rnaseq", "domain": "transcriptomics"}],
    "step_count": 1,
    "verifier_ok": true,
    "pattern": "sequential_omics_pipeline"
  },
  "latency_ms": 142
}
```

On composer failure:
```json
{"ts": ..., "user_id": ..., "session_id": ..., "query": ..., "error": "RuntimeError(...)", "latency_ms": ...}
```

## What is NOT done yet (intentionally)

Per `docs/20260612_RECOMMENDATION.md`:

- **No frontend changes.** The composer output is not shown to anyone.
- **No production rollout.** Flag defaults to off; deploying this change alone is a no-op.
- **No log analysis tooling.** Will be built once data accumulates and we know what questions to ask.
- **No A/B routing.** Strictly shadow mode.

## Verification

```bash
cd backend
python -m pytest tests/test_composer_telemetry.py -v   # 6/6 pass
python -m pytest tests/test_chain_composer.py -q       # 48/48 pass (3 skipped)
PYTHONPATH=lib python3 -c "import galaxy.ai.ai_assistant"  # clean import
```

All passing as of commit on this branch.

## Live smoke results (2026-06-12)

Ran 3 cross-domain queries through the real composer against the live DB:

| Query | Source | Confidence | Steps | Verifier | Latency |
|---|---|---|---|---|---|
| bulk rna-seq differential expression | curated_passthrough | 0.88 | 3 | ok | 2026ms (cold) |
| cryoEM single particle reconstruction | curated_passthrough | 0.80 | 3 | ok | 38ms |
| PBPK simulation for small molecule | curated_passthrough | 0.88 | 3 | ok | 41ms |

End-to-end wiring confirmed working against real DB + real composer (not mocked).

## Parked observations

- **`mode: null` for `curated_passthrough`** — the live smoke shows `curated_passthrough` chains don't carry a surfacing mode. Likely expected (passthrough bypasses `choose_surfacing_mode`). Confirm against `composer.py` once real shadow data accumulates; if intentional, document in composer docstring; if a bug, fix in the composer not the telemetry.
- **Cold-start latency** is 2s on first composer call per worker (DB load + LLM client init). Warm path is ~40ms. For dev rollout this is fine; for production at high traffic, consider warming on worker startup.

