"""
Hermetic tests for pattern_router.PatternRouter.

Hermetic by design:
  - A fake baseline_fn is injected (no benchmark DB, no I/O).
  - The REAL multi-agent orchestrator is NEVER invoked. Dispatch is exercised
    only with a stubbed orchestrator_factory, and the gating (disabled flag /
    non-multi pattern) is asserted to keep the factory from ever being called.

Runnable two ways:
  - Directly:  python3 test_pattern_router.py   (prints PASS/FAIL + N/N, exit code)
  - Pytest:    pytest test_pattern_router.py
"""

from __future__ import annotations

import os
import sys

# Make `pattern_router` importable whether run directly or under pytest,
# without triggering the galaxy.ai package machinery (the orchestrator import
# is lazy and must never fire in these hermetic tests).
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from pattern_router import (  # noqa: E402
    DEFAULT_THRESHOLD,
    ENV_FLAG,
    Pattern,
    PatternRouter,
    default_baseline_fn,
)


# --------------------------------------------------------------------------- #
# Fixtures / helpers
# --------------------------------------------------------------------------- #
def _fixed_baseline(value):
    """Return a baseline_fn that always yields `value`, ignoring the domain."""
    return lambda domain: value


class _StubOrchestrator:
    """Stand-in for AgentOrchestrator; records the dispatch call."""

    def __init__(self):
        self.calls = []

    def generate_workflow(self, query, parallel=True, **kw):
        self.calls.append({"query": query, "parallel": parallel, "kw": kw})
        return {"stub_result": True, "query": query, "parallel": parallel}


class _SpyFactory:
    """Factory that records whether it was ever invoked."""

    def __init__(self, orchestrator):
        self.orchestrator = orchestrator
        self.invoked = 0

    def __call__(self, *a, **k):
        self.invoked += 1
        return self.orchestrator


# --------------------------------------------------------------------------- #
# decide(): capability gate
# --------------------------------------------------------------------------- #
def test_high_baseline_domain_single():
    r = PatternRouter(baseline_fn=_fixed_baseline(0.90), enabled=False)
    d = r.decide({"domain": "routing", "shape": "single"})
    assert d["pattern"] == Pattern.SINGLE, d
    assert d["baseline"] == 0.90 and d["threshold"] == DEFAULT_THRESHOLD
    assert "reason" in d and d["reason"]


def test_low_baseline_domain_multi_specialist():
    r = PatternRouter(baseline_fn=_fixed_baseline(0.30), enabled=False)
    d = r.decide({"domain": "target_triage", "shape": "open_ended"})
    assert d["pattern"] == Pattern.MULTI_SPECIALIST, d
    assert d["baseline"] == 0.30 and d["threshold"] == DEFAULT_THRESHOLD


def test_threshold_boundary_is_single():
    # baseline == threshold must resolve to SINGLE (>= gate).
    r = PatternRouter(baseline_fn=_fixed_baseline(DEFAULT_THRESHOLD), enabled=False)
    d = r.decide({"domain": "whatever", "shape": "single"})
    assert d["pattern"] == Pattern.SINGLE, d
    assert d["baseline"] == DEFAULT_THRESHOLD == d["threshold"]


def test_per_domain_threshold_override():
    # A per-domain threshold above the baseline flips a would-be SINGLE to MULTI.
    r = PatternRouter(
        baseline_fn=_fixed_baseline(0.80),
        thresholds={"cryo_em": 0.85},
        enabled=False,
    )
    d = r.decide({"domain": "cryo_em", "shape": "single"})
    assert d["pattern"] == Pattern.MULTI_SPECIALIST, d
    assert d["threshold"] == 0.85


# --------------------------------------------------------------------------- #
# decide(): shape rules (take precedence over the capability gate)
# --------------------------------------------------------------------------- #
def test_independent_items_parallel_fanout():
    r = PatternRouter(baseline_fn=_fixed_baseline(0.99), enabled=False)
    d = r.decide({"domain": "transcriptomics", "shape": "independent_items"})
    assert d["pattern"] == Pattern.PARALLEL_FANOUT, d
    # numbers still filled for auditability
    assert d["baseline"] == 0.99 and d["threshold"] == DEFAULT_THRESHOLD


def test_dependent_stages_pipeline():
    r = PatternRouter(baseline_fn=_fixed_baseline(0.10), enabled=False)
    d = r.decide({"domain": "genomics", "shape": "dependent_stages"})
    assert d["pattern"] == Pattern.PIPELINE, d
    assert "reason" in d and d["reason"]


# --------------------------------------------------------------------------- #
# route_and_maybe_dispatch(): gating
# --------------------------------------------------------------------------- #
def test_disabled_flag_never_dispatches_even_for_multi():
    stub = _StubOrchestrator()
    spy = _SpyFactory(stub)
    r = PatternRouter(
        baseline_fn=_fixed_baseline(0.20),  # -> MULTI_SPECIALIST
        enabled=False,
        orchestrator_factory=spy,
    )
    out = r.route_and_maybe_dispatch({"domain": "x", "shape": "single"}, "do thing")
    assert out["dispatched"] is False, out
    assert out["decision"]["pattern"] == Pattern.MULTI_SPECIALIST
    assert spy.invoked == 0, "orchestrator factory must NOT be called when disabled"
    assert stub.calls == []


def test_enabled_non_multi_does_not_dispatch():
    stub = _StubOrchestrator()
    spy = _SpyFactory(stub)
    r = PatternRouter(
        baseline_fn=_fixed_baseline(0.95),  # -> SINGLE
        enabled=True,
        orchestrator_factory=spy,
    )
    out = r.route_and_maybe_dispatch({"domain": "x", "shape": "single"}, "q")
    assert out["dispatched"] is False, out
    assert out["decision"]["pattern"] == Pattern.SINGLE
    assert spy.invoked == 0, "non-multi pattern must not invoke the orchestrator"


def test_enabled_multi_specialist_dispatches_with_stub():
    stub = _StubOrchestrator()
    spy = _SpyFactory(stub)
    r = PatternRouter(
        baseline_fn=_fixed_baseline(0.20),  # -> MULTI_SPECIALIST
        enabled=True,
        orchestrator_factory=spy,
    )
    out = r.route_and_maybe_dispatch({"domain": "x", "shape": "open_ended"}, "design a study")
    assert out["dispatched"] is True, out
    assert out["decision"]["pattern"] == Pattern.MULTI_SPECIALIST
    assert spy.invoked == 1
    assert len(stub.calls) == 1
    assert stub.calls[0]["query"] == "design a study"
    assert stub.calls[0]["parallel"] is True, "orchestrator must be called with parallel=True"
    assert out["result"]["stub_result"] is True


def test_dispatch_failure_degrades_to_decision_only():
    def _boom_factory(*a, **k):
        raise RuntimeError("orchestrator unavailable")

    r = PatternRouter(
        baseline_fn=_fixed_baseline(0.20),  # -> MULTI_SPECIALIST
        enabled=True,
        orchestrator_factory=_boom_factory,
    )
    out = r.route_and_maybe_dispatch({"domain": "x", "shape": "single"}, "q")
    assert out["dispatched"] is False, out
    assert out.get("degraded") is True
    assert "orchestrator unavailable" in out.get("error", "")
    assert out["decision"]["pattern"] == Pattern.MULTI_SPECIALIST


# --------------------------------------------------------------------------- #
# flag + default-table sanity
# --------------------------------------------------------------------------- #
def test_enabled_from_env_default_false(monkeypatch=None):
    # With the env var unset/explicit-None, the router is disabled by default.
    saved = os.environ.pop(ENV_FLAG, None)
    try:
        r = PatternRouter()  # enabled=None -> reads env (absent) -> False
        assert r.enabled is False
        os.environ[ENV_FLAG] = "true"
        r2 = PatternRouter()
        assert r2.enabled is True
    finally:
        os.environ.pop(ENV_FLAG, None)
        if saved is not None:
            os.environ[ENV_FLAG] = saved


def test_default_baseline_table_shapes_decision():
    # Using the real conservative static table (no injected baseline_fn):
    # a saturated domain -> SINGLE, an open-ended domain -> MULTI_SPECIALIST.
    r = PatternRouter(enabled=False)
    assert default_baseline_fn("routing") >= DEFAULT_THRESHOLD
    assert r.decide({"domain": "routing", "shape": "single"})["pattern"] == Pattern.SINGLE
    assert r.decide({"domain": "target_triage", "shape": "single"})["pattern"] == Pattern.MULTI_SPECIALIST
    # Unknown domain defaults low -> MULTI_SPECIALIST.
    assert r.decide({"domain": "totally_unknown", "shape": "single"})["pattern"] == Pattern.MULTI_SPECIALIST


# --------------------------------------------------------------------------- #
# Direct runner (python3 test_pattern_router.py)
# --------------------------------------------------------------------------- #
def _collect_tests():
    g = globals()
    return [(name, g[name]) for name in sorted(g) if name.startswith("test_") and callable(g[name])]


def _main():
    tests = _collect_tests()
    passed = 0
    failed = 0
    for name, fn in tests:
        try:
            fn()
            passed += 1
            print("PASS %s" % name)
        except Exception as exc:  # noqa: BLE001
            failed += 1
            print("FAIL %s: %s: %s" % (name, type(exc).__name__, exc))
    total = passed + failed
    print("\n%d/%d passed" % (passed, total))
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(_main())
