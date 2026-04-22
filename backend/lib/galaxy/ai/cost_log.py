"""
cost_log.py — Durable file-based LLM cost logger for BioMate.

Writes one JSON line per LLM call to $BIOMATE_COST_LOG_DIR/llm_costs.jsonl.
Also forwards usage events to Lago (metering/billing) when LAGO_API_URL is set.

Pricing reference (update when model pricing changes):
  https://www.anthropic.com/api  /  https://openai.com/pricing
"""
from __future__ import annotations

import json
import logging
import os
import threading
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, Any, List, Optional

log = logging.getLogger(__name__)

_DEFAULT_DIR = Path(os.environ.get("BIOMATE_COST_LOG_DIR", "/tmp/biomate-cost-logs"))
_WRITE_LOCK = threading.Lock()

# ---------------------------------------------------------------------------
# Token pricing table (USD per 1 000 tokens)
# ---------------------------------------------------------------------------
_PRICE_PER_1K: Dict[str, Dict[str, float]] = {
    # Claude models
    "claude-sonnet-4-6":                  {"input": 0.003,    "output": 0.015},
    "claude-sonnet-4-5":                  {"input": 0.003,    "output": 0.015},
    "claude-3-5-sonnet-20241022":         {"input": 0.003,    "output": 0.015},
    "claude-3-5-sonnet-20240620":         {"input": 0.003,    "output": 0.015},
    "claude-haiku-4-5":                   {"input": 0.00025,  "output": 0.00125},
    "claude-3-haiku-20240307":            {"input": 0.00025,  "output": 0.00125},
    "claude-3-opus-20240229":             {"input": 0.015,    "output": 0.075},
    # Gemini models
    "gemini-2.5-flash":                   {"input": 0.000075, "output": 0.00030},
    # OpenAI models
    "gpt-4o":                             {"input": 0.0025,   "output": 0.01},
    "gpt-4o-mini":                        {"input": 0.00015,  "output": 0.0006},
    "gpt-4-turbo":                        {"input": 0.01,     "output": 0.03},
    "gpt-3.5-turbo":                      {"input": 0.0005,   "output": 0.0015},
}
_DEFAULT_PRICE = {"input": 0.003, "output": 0.015}  # fallback to claude-sonnet pricing


def _price_for(model: str) -> Dict[str, float]:
    for key, price in _PRICE_PER_1K.items():
        if key in model.lower():
            return price
    return _DEFAULT_PRICE


def compute_cost(model: str, input_tokens: int, output_tokens: int) -> float:
    """Return total USD cost for an LLM call."""
    p = _price_for(model)
    return round((input_tokens * p["input"] + output_tokens * p["output"]) / 1000, 8)


def _forward_to_lago(entry: Dict[str, Any]) -> None:
    """Send one LLM usage event to Lago. Runs in background thread, never raises."""
    lago_url = os.environ.get("LAGO_API_URL", "").rstrip("/")
    lago_key = os.environ.get("LAGO_API_KEY", "")
    if not lago_url or not lago_key:
        return
    try:
        import urllib.request
        raw_uid = entry.get("user_id") or ""
        # Lago subscription IDs are created as "bm_{uuid}_base" by auth-service.ts.
        # Raw postgres UUIDs won't match — prefix and suffix must be added.
        if raw_uid and not raw_uid.startswith("bm_"):
            external_sub_id = f"bm_{raw_uid}_base"
        else:
            external_sub_id = raw_uid or "anonymous"
        ts_epoch = int(datetime.fromisoformat(entry["ts"]).timestamp())
        shared_props = {
            "model": entry.get("model", ""),
            "session_id": entry.get("session_id", ""),
        }
        # Emit two events matching the Lago billable metrics: llm_input_tokens + llm_output_tokens.
        # Three events:
        # - llm_input_tokens / llm_output_tokens: field must be "tokens" (sum_agg on field_name=tokens)
        # - llm: field must be "value" (total tokens); this is what the base plan charges against
        input_tokens = entry.get("input_tokens", 0)
        output_tokens = entry.get("output_tokens", 0)
        events = [
            {
                "transaction_id": str(uuid.uuid4()),
                "external_subscription_id": external_sub_id,
                "code": "llm_input_tokens",
                "timestamp": ts_epoch,
                "properties": {**shared_props, "tokens": input_tokens},
            },
            {
                "transaction_id": str(uuid.uuid4()),
                "external_subscription_id": external_sub_id,
                "code": "llm_output_tokens",
                "timestamp": ts_epoch,
                "properties": {**shared_props, "tokens": output_tokens},
            },
            {
                "transaction_id": str(uuid.uuid4()),
                "external_subscription_id": external_sub_id,
                "code": "llm",
                "timestamp": ts_epoch,
                "properties": {**shared_props, "value": input_tokens + output_tokens},
            },
        ]
        headers = {
            "Content-Type": "application/json",
            "Authorization": f"Bearer {lago_key}",
        }
        for event in events:
            body = json.dumps({"event": event}).encode("utf-8")
            req = urllib.request.Request(
                f"{lago_url}/api/v1/events",
                data=body,
                headers=headers,
                method="POST",
            )
            with urllib.request.urlopen(req, timeout=5) as resp:
                status_code = resp.getcode()
                if status_code not in (200, 201):
                    log.debug("[CostLog→Lago] HTTP %s for %s", status_code, event["code"])
                else:
                    log.debug("[CostLog→Lago] %s accepted for user=%s", event["code"], external_sub_id)
    except Exception as exc:
        log.debug("[CostLog→Lago] Forward failed (non-fatal): %s", exc)


def record(
    user_id: str,
    session_id: str,
    model: str,
    input_tokens: int,
    output_tokens: int,
    duration_ms: float = 0.0,
    extra: Optional[Dict[str, Any]] = None,
) -> None:
    """Append one cost record to the JSONL log file and forward to Lago. Thread-safe, never raises."""
    try:
        _DEFAULT_DIR.mkdir(parents=True, exist_ok=True)
        cost_usd = compute_cost(model, input_tokens, output_tokens)
        entry = {
            "ts": datetime.now(timezone.utc).isoformat(),
            "user_id": user_id or "anonymous",
            "session_id": session_id or "",
            "model": model,
            "input_tokens": input_tokens,
            "output_tokens": output_tokens,
            "total_tokens": input_tokens + output_tokens,
            "cost_usd": cost_usd,
            "duration_ms": round(duration_ms, 1),
        }
        if extra:
            entry.update(extra)
        line = json.dumps(entry, ensure_ascii=False) + "\n"
        log_path = _DEFAULT_DIR / "llm_costs.jsonl"
        with _WRITE_LOCK:
            with open(log_path, "a", encoding="utf-8") as fh:
                fh.write(line)
        log.info(
            "[CostLog] %s | %s | in=%d out=%d | $%.6f",
            user_id, model, input_tokens, output_tokens, cost_usd,
        )
        # Forward to Lago in background — non-blocking, non-fatal
        threading.Thread(target=_forward_to_lago, args=(entry,), daemon=True).start()
    except Exception as exc:
        log.warning("[CostLog] Failed to write cost entry: %s", exc)


def query(
    user_id: Optional[str] = None,
    since_ts: Optional[str] = None,
) -> List[Dict[str, Any]]:
    """
    Read all cost records from the JSONL log, optionally filtered by
    user_id and/or since_ts (ISO8601 string).
    """
    log_path = _DEFAULT_DIR / "llm_costs.jsonl"
    if not log_path.exists():
        return []
    records: List[Dict[str, Any]] = []
    try:
        with open(log_path, "r", encoding="utf-8") as fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                try:
                    entry = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if user_id and entry.get("user_id") != user_id:
                    continue
                if since_ts and entry.get("ts", "") < since_ts:
                    continue
                records.append(entry)
    except Exception as exc:
        log.warning("[CostLog] Failed to read cost log: %s", exc)
    return records


def summary(user_id: Optional[str] = None) -> Dict[str, Any]:
    """Return aggregated cost/token summary for a user (or all users)."""
    records = query(user_id=user_id)
    total_cost = sum(r.get("cost_usd", 0.0) for r in records)
    total_input = sum(r.get("input_tokens", 0) for r in records)
    total_output = sum(r.get("output_tokens", 0) for r in records)
    return {
        "total_calls": len(records),
        "total_cost_usd": round(total_cost, 6),
        "total_input_tokens": total_input,
        "total_output_tokens": total_output,
        "total_tokens": total_input + total_output,
        "user_id": user_id or "all",
    }
