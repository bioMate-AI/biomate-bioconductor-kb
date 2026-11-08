"""Hermetic tests for map_reduce (no network, pure in-process workers).

Runnable two ways:
  - Directly:  python3 test_map_reduce.py   (prints PASS/FAIL + N/N, exit code)
  - Pytest:    pytest test_map_reduce.py
"""

from __future__ import annotations

import os
import sys
import threading
import time

# Make `map_reduce` importable whether run directly or under pytest, without
# triggering the galaxy.ai package machinery.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from map_reduce import (  # noqa: E402
    ON_ERROR_COLLECT,
    ON_ERROR_RAISE,
    map_reduce,
)


# --------------------------------------------------------------------------- #
# Ordering
# --------------------------------------------------------------------------- #
def test_order_preserved_despite_out_of_order_completion():
    # Later units finish FIRST (sleep inversely to value) -> if ordering were by
    # completion, results would be reversed. We assert input order regardless.
    def worker(x):
        time.sleep((10 - x) * 0.005)
        return x * x

    out = map_reduce([1, 2, 3, 4, 5], worker, max_concurrent=5)
    assert out["results"] == [1, 4, 9, 16, 25], out["results"]
    assert out["errors"] == []
    assert out["reduced"] is None


# --------------------------------------------------------------------------- #
# Concurrency cap
# --------------------------------------------------------------------------- #
def test_concurrency_cap_respected():
    lock = threading.Lock()
    state = {"in_flight": 0, "max_in_flight": 0}

    def worker(x):
        with lock:
            state["in_flight"] += 1
            if state["in_flight"] > state["max_in_flight"]:
                state["max_in_flight"] = state["in_flight"]
        try:
            time.sleep(0.02)  # hold the slot so overlap is observable
            return x
        finally:
            with lock:
                state["in_flight"] -= 1

    cap = 3
    out = map_reduce(list(range(12)), worker, max_concurrent=cap)
    assert out["results"] == list(range(12)), out["results"]
    assert state["max_in_flight"] <= cap, state["max_in_flight"]
    # Sanity: with 12 units and a real pool the cap should actually be reached.
    assert state["max_in_flight"] >= 2, state["max_in_flight"]


# --------------------------------------------------------------------------- #
# Error isolation
# --------------------------------------------------------------------------- #
def test_one_failing_unit_isolated_others_succeed():
    def worker(x):
        if x == 2:
            raise ValueError("boom on 2")
        return x * 10

    out = map_reduce([0, 1, 2, 3], worker, max_concurrent=4)
    # Successful results, in input order, with the failed unit omitted.
    assert out["results"] == [0, 10, 30], out["results"]
    assert len(out["errors"]) == 1, out["errors"]
    err = out["errors"][0]
    assert err["index"] == 2
    assert err["unit"] == 2
    assert err["type"] == "ValueError"
    assert "boom on 2" in err["error"]


def test_multiple_errors_in_input_order():
    def worker(x):
        if x in (1, 3):
            raise RuntimeError("fail-%d" % x)
        return x

    out = map_reduce([0, 1, 2, 3, 4], worker)
    assert out["results"] == [0, 2, 4], out["results"]
    assert [e["index"] for e in out["errors"]] == [1, 3], out["errors"]


def test_on_error_raise_reraises_first():
    def worker(x):
        if x == 1:
            raise KeyError("nope")
        return x

    raised = False
    try:
        map_reduce([0, 1, 2], worker, on_error=ON_ERROR_RAISE)
    except KeyError:
        raised = True
    assert raised, "on_error='raise' must re-raise the unit's exception"


def test_invalid_on_error_rejected():
    rejected = False
    try:
        map_reduce([1], lambda x: x, on_error="explode")
    except ValueError:
        rejected = True
    assert rejected


# --------------------------------------------------------------------------- #
# reduce_fn
# --------------------------------------------------------------------------- #
def test_reduce_fn_applied_to_successful_results():
    out = map_reduce([1, 2, 3, 4], lambda x: x, reduce_fn=sum, max_concurrent=2)
    assert out["results"] == [1, 2, 3, 4]
    assert out["reduced"] == 10


def test_reduce_fn_sees_only_successes():
    def worker(x):
        if x == 3:
            raise ValueError("x")
        return x

    out = map_reduce([1, 2, 3, 4], worker, reduce_fn=lambda rs: sum(rs))
    assert out["reduced"] == 1 + 2 + 4, out["reduced"]


# --------------------------------------------------------------------------- #
# Empty units
# --------------------------------------------------------------------------- #
def test_empty_units():
    out = map_reduce([], lambda x: x, max_concurrent=4)
    assert out["results"] == []
    assert out["errors"] == []
    assert out["reduced"] is None


def test_empty_units_with_reduce_fn():
    out = map_reduce([], lambda x: x, reduce_fn=lambda rs: {"n": len(rs)})
    assert out["reduced"] == {"n": 0}, out["reduced"]


def test_none_units_treated_as_empty():
    out = map_reduce(None, lambda x: x)  # type: ignore[arg-type]
    assert out["results"] == [] and out["errors"] == []


# --------------------------------------------------------------------------- #
# Direct runner (python3 test_map_reduce.py)
# --------------------------------------------------------------------------- #
def _collect_tests():
    g = globals()
    return [(name, g[name]) for name in sorted(g) if name.startswith("test_") and callable(g[name])]


def _main():
    passed = 0
    failed = 0
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
