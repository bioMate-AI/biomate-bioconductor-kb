"""Tests for build_dag_plan — the decomposed-tasks → executable-DAG assembly.

Validates the assembled plan against the REAL executor contract
(`galaxy.chain.dag.validate_plan`), so a built plan is guaranteed executable.
Hermetic: injected resolver, no network, no LLM.

Run: python backend/lib/galaxy/ai/test_decomposed_dag.py   (needs backend/lib on path)
"""
import os
import sys
from collections import namedtuple

_HERE = os.path.dirname(os.path.abspath(__file__))              # backend/lib/galaxy/ai
sys.path.insert(0, _HERE)                                       # import decomposed_dag (sibling)
sys.path.insert(0, os.path.join(_HERE, os.pardir, os.pardir))   # backend/lib → galaxy.chain.dag

from decomposed_dag import build_dag_plan  # noqa: E402
from galaxy.chain.dag import validate_plan  # noqa: E402

Task = namedtuple("Task", ["id", "description", "depends_on", "parallel_with"])


def _ok(t):
    return {"nextflow_path": "%s.nf" % t.id, "parameters": {"p": 1}}


def _fail(_t):
    return None


def _task(tid, deps=None, par=None):
    return Task(tid, "do " + tid, deps, par)


def _assert_executable(plan):
    # The assembled steps must pass the real chain-DAG executor contract.
    validate_plan(plan["steps"], [], plan["max_parallel"])  # raises if invalid


def test_sequential_plan_is_valid():
    plan = build_dag_plan([_task("a"), _task("b"), _task("c")], _ok)
    assert plan["execution_mode"] == "dag"
    assert [s["depends_on"] for s in plan["steps"]] == [[], [1], [2]]
    assert all(s["nextflow_path"].endswith(".nf") for s in plan["steps"])
    _assert_executable(plan)


def test_parallel_tasks_become_roots():
    # two tasks declared parallel → both roots (depends_on []), run in first wave
    plan = build_dag_plan([_task("a", par=[2]), _task("b", par=[1])], _ok)
    assert [s["depends_on"] for s in plan["steps"]] == [[], []]
    assert plan["max_parallel"] >= 2
    _assert_executable(plan)


def test_explicit_backward_deps_kept_forward_dropped():
    # step 3 depends on 1 (backward, kept) and 5 (out of range, dropped)
    plan = build_dag_plan([_task("a"), _task("b"), _task("c", deps=[1, 5])], _ok)
    assert plan["steps"][2]["depends_on"] == [1]
    _assert_executable(plan)


def test_unresolvable_task_returns_none():
    assert build_dag_plan([_task("a"), _task("b")], _fail) is None
    # a partial resolver (second task fails) → None, never a half-built DAG
    def partial(t):
        return _ok(t) if t.id == "a" else None
    assert build_dag_plan([_task("a"), _task("b")], partial) is None


def test_empty_tasks_returns_none():
    assert build_dag_plan([], _ok) is None


def test_max_parallel_bounded():
    plan = build_dag_plan([_task("a"), _task("b")], _ok, max_parallel=99)
    assert 1 <= plan["max_parallel"] <= 16


if __name__ == "__main__":
    import traceback
    fns = [v for k, v in sorted(globals().items()) if k.startswith("test_") and callable(v)]
    passed = 0
    for fn in fns:
        try:
            fn(); print("PASS", fn.__name__); passed += 1
        except Exception:
            print("FAIL", fn.__name__); traceback.print_exc()
    print("%d/%d passed" % (passed, len(fns)))
    sys.exit(0 if passed == len(fns) else 1)
