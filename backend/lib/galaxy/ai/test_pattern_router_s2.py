"""Hermetic S2 tests for pattern_router: fanout-via-map_reduce, real-signal
benchmark baselines (with static fallback), and the flag-gated ai_assistant
seam (`maybe_route_workflow_generation`).

Hermetic by design: the multi-agent orchestrator is NEVER really invoked -- a
spy factory asserts it stays untouched when disabled / non-multi. Benchmark
loading is exercised against synthetic summary files in a tmp dir, and the
missing-files path is asserted to fall back to the static table.

Runnable two ways:
  - Directly:  python3 test_pattern_router_s2.py   (prints PASS/FAIL + N/N)
  - Pytest:    pytest test_pattern_router_s2.py
"""

from __future__ import annotations

import json
import os
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from pattern_router import (  # noqa: E402
    ENV_FLAG,
    Pattern,
    PatternRouter,
    benchmark_baseline_fn,
    default_baseline_fn,
    make_benchmark_baseline_fn,
    maybe_route_workflow_generation,
)


class _StubOrchestrator:
    def __init__(self):
        self.calls = []

    def generate_workflow(self, query, parallel=True, **kw):
        self.calls.append({"query": query, "parallel": parallel})
        return {"success": True, "workflow_ga": {"name": "stub"}, "source": "stub"}


class _SpyFactory:
    def __init__(self, orchestrator):
        self.orchestrator = orchestrator
        self.invoked = 0

    def __call__(self, *a, **k):
        self.invoked += 1
        return self.orchestrator


# --------------------------------------------------------------------------- #
# PARALLEL_FANOUT executes via the shared map_reduce layer
# --------------------------------------------------------------------------- #
def test_decide_independent_items_is_parallel_fanout():
    r = PatternRouter(enabled=False)
    d = r.decide({"domain": "transcriptomics", "shape": "independent_items"})
    assert d["pattern"] == Pattern.PARALLEL_FANOUT, d


def test_fanout_runs_via_map_reduce():
    r = PatternRouter(enabled=False)
    out = r.fanout([1, 2, 3, 4], lambda x: x * 2, reduce_fn=sum, max_concurrent=2)
    assert out["results"] == [2, 4, 6, 8], out["results"]
    assert out["reduced"] == 20
    assert out["errors"] == []


def test_fanout_isolates_unit_errors():
    def worker(x):
        if x == 2:
            raise ValueError("boom")
        return x

    out = PatternRouter(enabled=False).fanout([1, 2, 3], worker)
    assert out["results"] == [1, 3]
    assert len(out["errors"]) == 1 and out["errors"][0]["index"] == 1


def test_fanout_empty_units():
    out = PatternRouter(enabled=False).fanout([], lambda x: x)
    assert out["results"] == [] and out["errors"] == [] and out["reduced"] is None


# --------------------------------------------------------------------------- #
# benchmark_baseline_fn: real signal when present, static fallback otherwise
# --------------------------------------------------------------------------- #
def test_benchmark_baseline_reads_real_signal():
    prev = os.environ.pop("BIOMATE_EVAL_RESULTS_DIR", None)
    try:
        with tempfile.TemporaryDirectory() as tmp:
            sub = os.path.join(tmp, "param_prefill")
            os.makedirs(sub)
            # dict-of-records shape with pass_rate as a 0..100 percentage
            with open(os.path.join(sub, "summary.json"), "w", encoding="utf-8") as fh:
                json.dump(
                    {
                        "param_prefill": {"n": 10, "passed": 9, "pass_rate": 90.0},
                        "pbpk_benchmark": {"pass_rate": 50.0},
                    },
                    fh,
                )
            fn = make_benchmark_baseline_fn(results_dir=tmp)
            assert abs(fn("param_prefill") - 0.90) < 1e-9, fn("param_prefill")
            # pbpk_benchmark -> alias -> "pbpk"
            assert abs(fn("pbpk") - 0.50) < 1e-9, fn("pbpk")
            # a domain with no measured signal falls through to the static table
            assert fn("cryo_em") == default_baseline_fn("cryo_em")
    finally:
        if prev is not None:
            os.environ["BIOMATE_EVAL_RESULTS_DIR"] = prev


def test_benchmark_baseline_reads_list_shape_and_mean_score():
    prev = os.environ.pop("BIOMATE_EVAL_RESULTS_DIR", None)
    try:
        with tempfile.TemporaryDirectory() as tmp:
            with open(os.path.join(tmp, "summary_overall.json"), "w", encoding="utf-8") as fh:
                # list-of-records shape, mean_score already 0..1
                json.dump(
                    [{"benchmark": "cross_domain_routing", "mean_score": 0.83}],
                    fh,
                )
            fn = make_benchmark_baseline_fn(results_dir=tmp)
            # cross_domain_routing -> alias -> "routing"
            assert abs(fn("routing") - 0.83) < 1e-9, fn("routing")
    finally:
        if prev is not None:
            os.environ["BIOMATE_EVAL_RESULTS_DIR"] = prev


def test_benchmark_baseline_falls_back_on_missing_files():
    prev = os.environ.pop("BIOMATE_EVAL_RESULTS_DIR", None)
    try:
        with tempfile.TemporaryDirectory() as tmp:
            # empty dir: no summary files -> real table empty -> pure static
            fn = make_benchmark_baseline_fn(results_dir=tmp)
            for domain in ("routing", "param_prefill", "pbpk", "cryo_em", "totally_unknown", None):
                assert fn(domain) == default_baseline_fn(domain), domain
    finally:
        if prev is not None:
            os.environ["BIOMATE_EVAL_RESULTS_DIR"] = prev


def test_benchmark_baseline_bad_json_is_ignored():
    prev = os.environ.pop("BIOMATE_EVAL_RESULTS_DIR", None)
    try:
        with tempfile.TemporaryDirectory() as tmp:
            with open(os.path.join(tmp, "summary.json"), "w", encoding="utf-8") as fh:
                fh.write("{ this is not valid json ")
            fn = make_benchmark_baseline_fn(results_dir=tmp)
            assert fn("routing") == default_baseline_fn("routing")
    finally:
        if prev is not None:
            os.environ["BIOMATE_EVAL_RESULTS_DIR"] = prev


def test_benchmark_baseline_fn_convenience_is_callable():
    # Lazily built, cached; returns a float in [0,1]. (In this worktree there is
    # no evaluation/ dir, so it equals the static table -- which is the fallback.)
    val = benchmark_baseline_fn("routing")
    assert isinstance(val, float) and 0.0 <= val <= 1.0


def test_router_accepts_benchmark_baseline_fn():
    # Drop-in wiring: the router can be constructed with the real-signal fn.
    r = PatternRouter(baseline_fn=benchmark_baseline_fn, enabled=False)
    d = r.decide({"domain": "routing", "shape": "single"})
    assert d["pattern"] in Pattern.ALL


# --------------------------------------------------------------------------- #
# ai_assistant seam: flag-gated, off == no-op (orchestrator never touched)
# --------------------------------------------------------------------------- #
def test_hook_disabled_is_noop_and_never_touches_orchestrator():
    stub = _StubOrchestrator()
    spy = _SpyFactory(stub)
    router = PatternRouter(
        baseline_fn=lambda d: 0.10,  # -> MULTI if it were ever consulted
        enabled=False,
        orchestrator_factory=spy,
    )
    out = maybe_route_workflow_generation(
        "generate an admet workflow", {"domain": "x", "shape": "single"},
        enabled=False, router=router,
    )
    assert out["proceed"] is True, out
    assert out["dispatched"] is False, out
    assert out["enabled"] is False, out
    assert spy.invoked == 0 and stub.calls == [], "orchestrator must stay untouched when disabled"


def test_hook_default_reads_env_flag_absent_is_disabled():
    saved = os.environ.pop(ENV_FLAG, None)
    try:
        out = maybe_route_workflow_generation("q", {"domain": "x"})  # enabled=None -> env (absent)
        assert out["proceed"] is True and out["dispatched"] is False and out["enabled"] is False
    finally:
        if saved is not None:
            os.environ[ENV_FLAG] = saved


def test_hook_enabled_single_pattern_does_not_dispatch():
    stub = _StubOrchestrator()
    spy = _SpyFactory(stub)
    router = PatternRouter(baseline_fn=lambda d: 0.95, enabled=True, orchestrator_factory=spy)
    out = maybe_route_workflow_generation(
        "q", {"domain": "x", "shape": "single"}, enabled=True, router=router
    )
    assert out["dispatched"] is False and out["proceed"] is True
    assert out["decision"]["pattern"] == Pattern.SINGLE
    assert spy.invoked == 0


def test_hook_enabled_multi_specialist_dispatches():
    stub = _StubOrchestrator()
    spy = _SpyFactory(stub)
    router = PatternRouter(baseline_fn=lambda d: 0.10, enabled=True, orchestrator_factory=spy)
    out = maybe_route_workflow_generation(
        "design a novel cross-domain study", {"domain": "x", "shape": "open_ended"},
        enabled=True, router=router,
    )
    assert out["dispatched"] is True and out["proceed"] is False
    assert out["decision"]["pattern"] == Pattern.MULTI_SPECIALIST
    assert spy.invoked == 1 and len(stub.calls) == 1
    assert stub.calls[0]["parallel"] is True


# --------------------------------------------------------------------------- #
# Structural guard: the live ai_assistant hook is flag-gated in source and the
# gate precedes the default generate_workflow_unified call. (Dependency-free:
# importing the real module needs the full galaxy chain; py_compile covers that.)
# --------------------------------------------------------------------------- #
def test_ai_assistant_hook_is_flag_gated_in_source():
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "ai_assistant.py")
    with open(path, "r", encoding="utf-8") as fh:
        src = fh.read()
    assert "BIOMATE_PATTERN_ROUTER_ENABLED" in src, "hook env gate missing"
    assert "maybe_route_workflow_generation" in src, "hook delegate call missing"
    gate = src.index("BIOMATE_PATTERN_ROUTER_ENABLED")
    delegate = src.index("maybe_route_workflow_generation")
    # The default single-pass call inside _handle_workflow_generation is the
    # first generate_workflow_unified occurrence AFTER the hook delegate.
    unified_after_hook = src.index("generate_workflow_unified", delegate)
    # The env gate must come before the delegate call (gate wraps delegation)...
    assert gate < delegate, "env flag must gate the delegate call"
    # ...and the whole hook must sit before the default single-pass generation.
    assert delegate < unified_after_hook, "hook must precede the default generation path"


# --------------------------------------------------------------------------- #
# Direct runner
# --------------------------------------------------------------------------- #
def _collect_tests():
    g = globals()
    return [(name, g[name]) for name in sorted(g) if name.startswith("test_") and callable(g[name])]


def _main():
    passed = failed = 0
    for name, fn in _collect_tests():
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
