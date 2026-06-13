"""#49 — metrics smoke."""
from __future__ import annotations
from galaxy.ai.drug_discovery.regulatory_metrics import (
    record_call, record_fallback, snapshot, reset,
)


def test_empty_snapshot():
    reset()
    s = snapshot()
    assert s["calls_total"] == 0
    assert s["fallbacks_total"] == 0
    assert s["fallback_rate"] == 0.0
    assert s["calls_by_section_source"] == {}


def test_records_calls_and_latency():
    reset()
    record_call("admet", "local", 0.5)
    record_call("admet", "local", 1.5)
    record_call("admet", "gemini", 3.0)
    s = snapshot()
    assert s["calls_total"] == 3
    assert s["calls_by_section_source"]["admet/local"] == 2
    assert s["calls_by_section_source"]["admet/gemini"] == 1
    assert s["latency_by_source"]["local"]["n"] == 2
    assert s["latency_by_source"]["local"]["p50_ms"] in (500.0, 1500.0)
    assert s["latency_by_source"]["gemini"]["p50_ms"] == 3000.0


def test_fallback_rate():
    reset()
    record_call("tox_genotox", "local", 0.1)
    record_call("tox_genotox", "gemini", 1.0)
    record_fallback("tox_genotox", "audit_fail:CITE_002:genotox_missing_S2R1")
    s = snapshot()
    assert s["fallbacks_total"] == 1
    assert s["fallback_rate"] == 0.5
    assert s["fallbacks_by_section_reason"]["tox_genotox/audit_fail:CITE_002:genotox_missing_S2R1"] == 1


def test_latency_ring_caps_at_10k():
    reset()
    for _ in range(10_500):
        record_call("admet", "local", 0.001)
    s = snapshot()
    assert s["latency_by_source"]["local"]["n"] == 10_000
    assert s["calls_total"] == 10_500


def test_p95_above_p50():
    reset()
    for i in range(100):
        record_call("admet", "local", i * 0.01)
    s = snapshot()
    lat = s["latency_by_source"]["local"]
    assert lat["p50_ms"] < lat["p95_ms"] < lat["p99_ms"] <= lat["max_ms"]
