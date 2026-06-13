"""Tests for the shadow telemetry shim — must never raise, must respect flags."""

import json
import sys
from pathlib import Path
from types import SimpleNamespace

import pytest

REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "lib" / "galaxy" / "ai"))

from chain_composer import telemetry  # noqa: E402


@pytest.fixture(autouse=True)
def _isolate(tmp_path, monkeypatch):
    log_file = tmp_path / "shadow.jsonl"
    monkeypatch.setenv("BIOMATE_COMPOSER_SHADOW_LOG", str(log_file))
    monkeypatch.delenv("BIOMATE_COMPOSER_SHADOW", raising=False)
    monkeypatch.delenv("BIOMATE_COMPOSER_SHADOW_PCT", raising=False)
    monkeypatch.delenv("BIOMATE_COMPOSER_SHADOW_MAX_PER_SESSION", raising=False)
    telemetry.reset_session_counts()
    yield log_file


def _fake_chain():
    # Mirrors the real ComposedChain schema from chain_composer/types.py.
    return SimpleNamespace(
        source="curated_passthrough",
        surfacing_mode="upfront",
        confidence=0.91,
        signals={"curated_chain_score": 1.0, "pattern_match_score": 0.8},
        steps=[SimpleNamespace(order=1, workflow_name="nf-core/rnaseq", role="primary")],
        verifier_report={"ok": True, "errors": []},
        patterns_used=["sequential_omics_pipeline"],
    )


def test_default_off_writes_nothing(_isolate, monkeypatch):
    monkeypatch.setattr("chain_composer.telemetry.compose_chain", _fake_chain, raising=False)
    telemetry.shadow_log("any query", {"sessionId": "s1"})
    assert not _isolate.exists()


def test_enabled_writes_record(_isolate, monkeypatch):
    monkeypatch.setenv("BIOMATE_COMPOSER_SHADOW", "1")
    import chain_composer.telemetry as tmod
    monkeypatch.setattr(tmod, "compose_chain", lambda q: _fake_chain(), raising=False)
    # Also patch the deferred import in shadow_log by injecting a fake composer module.
    import sys as _sys
    fake_mod = SimpleNamespace(compose_chain=lambda q: _fake_chain())
    monkeypatch.setitem(_sys.modules, "chain_composer.composer", fake_mod)

    telemetry.shadow_log("rna-seq DE analysis", {"sessionId": "s1", "userId": "u1"})

    assert _isolate.exists()
    line = _isolate.read_text().strip().splitlines()[-1]
    rec = json.loads(line)
    assert rec["query"] == "rna-seq DE analysis"
    assert rec["session_id"] == "s1"
    assert rec["user_id"] == "u1"
    assert rec["composer"]["source"] == "curated_passthrough"
    assert rec["composer"]["mode"] == "upfront"
    assert rec["composer"]["confidence"] == pytest.approx(0.91)
    assert rec["composer"]["step_count"] == 1
    assert rec["composer"]["steps"][0]["workflow_name"] == "nf-core/rnaseq"
    assert rec["composer"]["verifier_ok"] is True
    assert rec["composer"]["patterns"] == ["sequential_omics_pipeline"]
    assert "latency_ms" in rec


def test_composer_exception_is_swallowed(_isolate, monkeypatch):
    monkeypatch.setenv("BIOMATE_COMPOSER_SHADOW", "1")
    import sys as _sys
    def _boom(_):
        raise RuntimeError("composer exploded")
    fake_mod = SimpleNamespace(compose_chain=_boom)
    monkeypatch.setitem(_sys.modules, "chain_composer.composer", fake_mod)

    telemetry.shadow_log("anything", {"sessionId": "s2"})  # must not raise

    rec = json.loads(_isolate.read_text().strip().splitlines()[-1])
    assert "error" in rec
    assert "composer exploded" in rec["error"]


def test_zero_pct_disables(_isolate, monkeypatch):
    monkeypatch.setenv("BIOMATE_COMPOSER_SHADOW", "1")
    monkeypatch.setenv("BIOMATE_COMPOSER_SHADOW_PCT", "0")
    import sys as _sys
    fake_mod = SimpleNamespace(compose_chain=lambda q: _fake_chain())
    monkeypatch.setitem(_sys.modules, "chain_composer.composer", fake_mod)

    telemetry.shadow_log("q", {"sessionId": "s3"})
    assert not _isolate.exists()


def test_session_cap_respected(_isolate, monkeypatch):
    monkeypatch.setenv("BIOMATE_COMPOSER_SHADOW", "1")
    monkeypatch.setenv("BIOMATE_COMPOSER_SHADOW_MAX_PER_SESSION", "2")
    import sys as _sys
    fake_mod = SimpleNamespace(compose_chain=lambda q: _fake_chain())
    monkeypatch.setitem(_sys.modules, "chain_composer.composer", fake_mod)

    for _ in range(5):
        telemetry.shadow_log("q", {"sessionId": "capped"})

    lines = _isolate.read_text().strip().splitlines()
    assert len(lines) == 2


def test_query_truncated(_isolate, monkeypatch):
    monkeypatch.setenv("BIOMATE_COMPOSER_SHADOW", "1")
    import sys as _sys
    fake_mod = SimpleNamespace(compose_chain=lambda q: _fake_chain())
    monkeypatch.setitem(_sys.modules, "chain_composer.composer", fake_mod)

    big = "x" * 5000
    telemetry.shadow_log(big, {"sessionId": "s5"})
    rec = json.loads(_isolate.read_text().strip().splitlines()[-1])
    assert len(rec["query"]) == 1000
