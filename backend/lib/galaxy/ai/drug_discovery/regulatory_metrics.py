"""
Lane #49 — in-memory observability for the regulatory-LLM call path.

Thread-safe counters + bounded latency ring + JSON-serialisable snapshot.
Pure stdlib. Wire-points in ind_assembly._llm_narrative:

    from .regulatory_metrics import record_call, record_fallback
    record_call(section_type=..., source="local"|"gemini", elapsed_s=...)
    record_fallback(section_type=..., reason="empty"|"audit_fail:...")

The snapshot() output is the shape a /api/regulatory_llm/metrics endpoint
would return; a Prometheus exporter could later read the same dict via the
exposed lock.
"""
from __future__ import annotations
import threading, time
from collections import defaultdict
from typing import Any

_metrics_lock = threading.Lock()
_call_count: dict[tuple[str, str], int] = defaultdict(int)
_fallback_count: dict[tuple[str, str], int] = defaultdict(int)
_latencies_ms: dict[str, list[float]] = defaultdict(list)
_MAX_LATENCIES = 10_000
_start_ts = time.time()


def record_call(section_type: str, source: str, elapsed_s: float) -> None:
    """source ∈ {local, gemini, frontier, ...}"""
    with _metrics_lock:
        _call_count[(section_type, source)] += 1
        bucket = _latencies_ms[source]
        bucket.append(round(elapsed_s * 1000.0, 2))
        if len(bucket) > _MAX_LATENCIES:
            del bucket[: len(bucket) - _MAX_LATENCIES]


def record_fallback(section_type: str, reason: str) -> None:
    """reason ∈ {empty, audit_fail:..., timeout, ...}"""
    with _metrics_lock:
        _fallback_count[(section_type, reason)] += 1


def _percentile(sorted_vals: list[float], p: float) -> float:
    if not sorted_vals:
        return 0.0
    k = max(0, min(len(sorted_vals) - 1,
                   int(round((p / 100.0) * (len(sorted_vals) - 1)))))
    return sorted_vals[k]


def snapshot() -> dict[str, Any]:
    """Read-only snapshot of all counters + p50/p95/p99 per source."""
    with _metrics_lock:
        calls = {f"{sec}/{src}": n for (sec, src), n in _call_count.items()}
        fallbacks = {f"{sec}/{reason}": n for (sec, reason), n in _fallback_count.items()}
        latencies = {}
        for src, bucket in _latencies_ms.items():
            if not bucket:
                continue
            s = sorted(bucket)
            latencies[src] = {
                "n":      len(s),
                "p50_ms": _percentile(s, 50),
                "p95_ms": _percentile(s, 95),
                "p99_ms": _percentile(s, 99),
                "max_ms": s[-1],
            }
        total_calls = sum(_call_count.values())
        total_fallbacks = sum(_fallback_count.values())
        fallback_rate = (total_fallbacks / total_calls) if total_calls else 0.0
        return {
            "uptime_s": round(time.time() - _start_ts, 1),
            "calls_total": total_calls,
            "fallbacks_total": total_fallbacks,
            "fallback_rate": round(fallback_rate, 4),
            "calls_by_section_source": calls,
            "fallbacks_by_section_reason": fallbacks,
            "latency_by_source": latencies,
        }


def reset() -> None:
    """Test-only — wipes all counters."""
    with _metrics_lock:
        _call_count.clear()
        _fallback_count.clear()
        _latencies_ms.clear()
