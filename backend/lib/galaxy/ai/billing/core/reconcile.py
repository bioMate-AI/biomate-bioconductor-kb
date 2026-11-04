"""Reconciliation consumer for the billing cost-event dead-letter.

Replays `billing_deadletter.jsonl` (events whose primary Redis write failed) back
into the realtime Redis ledger once Redis is healthy again, crediting each event's
ORIGINAL billing month. Safe to run repeatedly / after a crash.

Idempotency (money path — must never DOUBLE-count):
  Before replaying an event we atomically claim a durable marker
  `billing:recon:done:<txn_id>` via Redis `SET ... NX`. Only the claimer replays;
  a second run (or a crash-retry) sees the marker and skips. The marker is the
  exactly-once guard — the file `replayed` flag is just hygiene. The deterministic
  `txn_id` (see cost_log._deterministic_txn_id) makes the marker stable across runs.
  Trade-off: a crash in the tiny window between claiming the marker and the Redis
  increment UNDER-counts that one event (prefers under-count to over-charging).

What this module does NOT do: schedule itself. Wire it to a trigger (cron, or an
on-Redis-recovery hook) at deploy time — e.g. `python -m galaxy.ai.billing.core.reconcile`.
See docs/20261104_BILLING_DEADLETTER.md.

Python 3.9-safe.
"""
from __future__ import annotations

import json
import logging
import os
import time
from pathlib import Path
from typing import Dict, List, Optional

log = logging.getLogger(__name__)

_MARKER_PREFIX = "billing:recon:done:"
_MARKER_TTL_SEC = 90 * 24 * 3600  # 90 days — long enough to cover any replay backlog

# event_type -> (RealtimeCostService method name, ordered payload arg names)
_REPLAY_SPEC = {
    "llm_cost":       ("record_llm_cost",       ["user_id", "input_usd", "output_usd", "input_tokens", "output_tokens"]),
    "batch_job_cost": ("record_batch_job_cost", ["user_id", "job_id", "vcpu_usd", "gpu_usd", "mem_usd", "duration_seconds"]),
    "s3_put":         ("record_s3_put",         ["user_id", "size_bytes", "storage_usd", "request_usd", "object_key"]),
}


def _deadletter_path() -> Path:
    from galaxy.ai import cost_log
    return cost_log._DEFAULT_DIR / cost_log._DEADLETTER_FILE


def _claim(redis_client, txn_id: str) -> Optional[bool]:
    """Atomically claim a txn for replay. True = claimed (replay it), False =
    already done (skip), None = Redis error (abort the run — retry later)."""
    try:
        ok = redis_client.set(_MARKER_PREFIX + txn_id, "1", nx=True, ex=_MARKER_TTL_SEC)
        return bool(ok)
    except Exception as exc:
        log.warning("[billing][reconcile] marker claim failed (Redis down?): %s", exc)
        return None


def reconcile_deadletter(service=None, dry_run: bool = False) -> Dict[str, int]:
    """Replay the dead-letter into Redis. Returns a summary dict. Never raises
    for a per-line error (those are counted); aborts cleanly if Redis is down."""
    path = _deadletter_path()
    summary = {"scanned": 0, "replayed": 0, "already_done": 0, "requeued": 0,
               "malformed": 0, "redis_down": 0}
    if not path.exists():
        log.info("[billing][reconcile] no dead-letter file at %s — nothing to do", path)
        return summary

    if service is None and not dry_run:
        from galaxy.ai.billing.core.realtime_cost_service import RealtimeCostService
        service = RealtimeCostService()
    redis_client = getattr(service, "_r", None) if service is not None else None

    from galaxy.ai import cost_log
    with cost_log._WRITE_LOCK:  # serialise against concurrent dead-letter appends
        raw_lines = path.read_text(encoding="utf-8").splitlines()

    kept: List[str] = []   # lines to retain (not yet durably replayed)
    aborted = False
    for raw in raw_lines:
        raw = raw.strip()
        if not raw:
            continue
        summary["scanned"] += 1
        try:
            rec = json.loads(raw)
        except Exception:
            summary["malformed"] += 1
            kept.append(raw)  # keep malformed lines for manual inspection
            continue
        if rec.get("replayed") is True:
            continue  # already reconciled in a prior run; drop on compaction
        if aborted:
            kept.append(raw)
            continue

        txn_id = rec.get("txn_id") or ""
        event_type = rec.get("event_type")
        payload = rec.get("payload") or {}
        spec = _REPLAY_SPEC.get(event_type)
        if not txn_id or spec is None:
            summary["malformed"] += 1
            kept.append(raw)
            continue

        if dry_run:
            summary["replayed"] += 1
            kept.append(raw)  # dry run never mutates
            continue

        claimed = _claim(redis_client, txn_id)
        if claimed is None:        # Redis unreachable — stop; retry whole file later
            summary["redis_down"] += 1
            aborted = True
            kept.append(raw)
            continue
        if claimed is False:       # another run already replayed this txn
            summary["already_done"] += 1
            continue               # drop on compaction

        method_name, arg_names = spec
        method = getattr(service, method_name)
        month = payload.get("month")  # credit the ORIGINAL period
        try:
            kwargs = {name: payload.get(name) for name in arg_names}
            status = method(month=month, **kwargs)
        except Exception as exc:
            # Unexpected replay error — leave the marker (claimed) and the line in
            # place; do NOT double-apply. Surfaced loudly for review.
            log.error("[billing][reconcile] replay of txn=%s (%s) raised: %s", txn_id, event_type, exc)
            kept.append(raw)
            continue

        if status == "redis":
            summary["replayed"] += 1   # durably applied; drop on compaction
        else:
            # Redis went down between claim and write → record_* re-queued the event
            # under a NEW txn_id (dead-letter), so its charge is not lost. This line's
            # marker is claimed; drop it (the new dead-letter line carries the charge).
            summary["requeued"] += 1

    if not dry_run:
        _compact(path, kept)
    log.info("[billing][reconcile] done: %s", summary)
    return summary


def _compact(path: Path, kept_lines: List[str]) -> None:
    """Rewrite the dead-letter keeping only unreconciled lines, after backing up
    the original. Atomic (write temp + os.replace)."""
    try:
        from galaxy.ai import cost_log
        with cost_log._WRITE_LOCK:
            if path.exists():
                bak = path.with_suffix(".jsonl.%d.bak" % int(time.time()))
                try:
                    bak.write_text(path.read_text(encoding="utf-8"), encoding="utf-8")
                except Exception as bexc:
                    log.warning("[billing][reconcile] backup before compaction failed: %s", bexc)
            tmp = path.with_suffix(".jsonl.tmp")
            tmp.write_text(("\n".join(kept_lines) + ("\n" if kept_lines else "")), encoding="utf-8")
            os.replace(str(tmp), str(path))
    except Exception as exc:
        log.error("[billing][reconcile] compaction failed (dead-letter left intact): %s", exc)


if __name__ == "__main__":  # manual / cron entrypoint
    logging.basicConfig(level=logging.INFO)
    import argparse
    ap = argparse.ArgumentParser(description="Replay the billing cost-event dead-letter into Redis.")
    ap.add_argument("--dry-run", action="store_true", help="scan + report, never write")
    args = ap.parse_args()
    print(json.dumps(reconcile_deadletter(dry_run=args.dry_run), indent=2))
