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

from decomposed_dag import (  # noqa: E402
    build_dag_plan, pick_workflow_match, bind_shared_inputs, to_pipeline_card, DAG_RESOLVE_MIN_SCORE,
    type_satisfies,
)
from galaxy.chain.dag import validate_plan  # noqa: E402

Match = namedtuple("Match", ["filename", "score"])

Task = namedtuple("Task", ["id", "description", "depends_on", "parallel_with"])


def _ok(t):
    return {"nextflow_path": "%s.nf" % t.id, "parameters": {"p": 1}}


def _fail(_t):
    return None


def _task(tid, deps=None, par=None):
    return Task(tid, "do " + tid, deps, par)


def _assert_executable(plan):
    # The assembled steps + connections must pass the real chain-DAG executor contract.
    validate_plan(plan["steps"], plan.get("connections", []), plan["max_parallel"])


# type_provider: every workflow consumes + produces the "data" type → handoffs match
def _tp_match(_path):
    return (["data"], ["data"])


# type_provider where outputs never match the next step's inputs → no handoff
def _tp_mismatch(path):
    return (["in_" + path], ["out_" + path])


def test_sequential_plan_is_valid():
    plan = build_dag_plan([_task("a"), _task("b"), _task("c")], _ok, type_provider=_tp_match)
    assert plan["execution_mode"] == "dag"
    assert [s["depends_on"] for s in plan["steps"]] == [[], [1], [2]]
    # each dependent step got a type-matched connection from its dependency
    assert {(c["from_step"], c["to_step"]) for c in plan["connections"]} == {(1, 2), (2, 3)}
    _assert_executable(plan)


def test_sequential_without_types_refuses():
    # dependent steps but no type_provider → cannot verify handoff → fallback (None)
    assert build_dag_plan([_task("a"), _task("b")], _ok) is None


def test_dependent_type_mismatch_refuses():
    # a's outputs never match b's inputs → no connection → fallback (None)
    assert build_dag_plan([_task("a"), _task("b")], _ok, type_provider=_tp_mismatch) is None


def test_parallel_tasks_become_roots_no_connections():
    # two tasks declared parallel → both roots, no inter-step connection needed
    plan = build_dag_plan([_task("a", par=[2]), _task("b", par=[1])], _ok)
    assert [s["depends_on"] for s in plan["steps"]] == [[], []]
    assert plan["connections"] == []          # fan-out: no handoff
    assert plan["max_parallel"] >= 2
    _assert_executable(plan)


def test_explicit_backward_deps_kept_forward_dropped():
    # step 3 depends on 1 (backward, kept) and 5 (out of range, dropped)
    plan = build_dag_plan([_task("a"), _task("b"), _task("c", deps=[1, 5])], _ok, type_provider=_tp_match)
    assert plan["steps"][2]["depends_on"] == [1]
    assert (1, 3) in {(c["from_step"], c["to_step"]) for c in plan["connections"]}
    _assert_executable(plan)


# ── fix #2 (2026-10-21): SEMANTIC type handoff, not exact string match ──────────
def _tp_semantic(path):
    # step a PRODUCES counts_matrix; step b CONSUMES counts (an alias of counts_matrix,
    # NOT an identical string). Exact match would refuse this; type_satisfies wires it.
    if path == "a.nf":
        return ([], ["counts_matrix"])
    return (["counts"], [])


def test_type_satisfies_semantic_and_refusal():
    assert type_satisfies("counts_matrix", "counts")   # alias-table equivalence
    assert type_satisfies("bam", "input_bam")          # substring alias
    assert type_satisfies("vcf", "vcf")                # identity
    assert not type_satisfies("bam", "vcf")            # genuinely incompatible → refuse
    assert not type_satisfies("fasta", "pdbqt")


def test_semantic_handoff_wires_equivalent_types():
    # counts_matrix (a's output) satisfies counts (b's input) via the alias table —
    # this would FAIL the old exact `t in dst_in` match; the connection records the
    # distinct source/dest type tokens (proving it is semantic, not identity).
    plan = build_dag_plan([_task("a"), _task("b")], _ok, type_provider=_tp_semantic)
    assert plan is not None
    assert len(plan["connections"]) == 1
    c = plan["connections"][0]
    assert (c["from_output"], c["to_input"]) == ("counts_matrix", "counts")
    assert c["from_output"] != c["to_input"]           # NOT exact match → semantic handoff
    _assert_executable(plan)


def test_semantic_handoff_still_refuses_incompatible():
    # bam output does NOT satisfy a vcf input → no connection → safe fallback (None)
    def _tp(path):
        return ([], ["bam"]) if path == "a.nf" else (["vcf"], [])
    assert build_dag_plan([_task("a"), _task("b")], _ok, type_provider=_tp) is None


def test_unresolvable_task_returns_none():
    assert build_dag_plan([_task("a"), _task("b")], _fail) is None
    # a partial resolver (second task fails) → None, never a half-built DAG
    def partial(t):
        return _ok(t) if t.id == "a" else None
    assert build_dag_plan([_task("a"), _task("b")], partial) is None


def test_empty_tasks_returns_none():
    assert build_dag_plan([], _ok) is None


def test_max_parallel_bounded():
    plan = build_dag_plan([_task("a", par=[2]), _task("b", par=[1])], _ok, max_parallel=99)
    assert 1 <= plan["max_parallel"] <= 16


def test_pick_match_confident_resolves():
    got = pick_workflow_match([Match("rnaseq.nf", 15.0), Match("other.nf", 14.0)])
    assert got == {"nextflow_path": "rnaseq.nf", "parameters": {}}


def test_pick_match_low_score_refused():
    assert pick_workflow_match([Match("weak.nf", 3.0)]) is None       # below medium bar
    assert DAG_RESOLVE_MIN_SCORE == 6.0


def test_pick_match_empty_or_no_filename():
    assert pick_workflow_match([]) is None
    assert pick_workflow_match(None) is None
    assert pick_workflow_match([Match(None, 99.0)]) is None


def test_pick_match_accepts_dicts():
    assert pick_workflow_match([{"filename": "x.nf", "score": 10}]) == {"nextflow_path": "x.nf", "parameters": {}}
    assert pick_workflow_match([{"filename": "x.nf", "score": 1}]) is None


def test_build_dag_with_pick_resolver():
    # end-to-end: resolver backed by pick_workflow_match assembles a valid DAG
    def resolver(t):
        return pick_workflow_match([Match("%s.nf" % t.id, 12.0)])
    plan = build_dag_plan([_task("a"), _task("b")], resolver, type_provider=_tp_match)
    assert plan is not None
    _assert_executable(plan)
    # a task whose only match is weak → whole plan falls back (None)
    def weak(t):
        return pick_workflow_match([Match("%s.nf" % t.id, 2.0)])
    assert build_dag_plan([_task("a")], weak) is None


def _fanout_plan():
    # two parallel roots (fan-out of two tools over the same input)
    return build_dag_plan([_task("a", par=[2]), _task("b", par=[1])], _ok)


def test_bind_shared_input_fanout_csv():
    plan = bind_shared_inputs(_fanout_plan(), ["s3://b/samples.csv"])
    assert all(s["parameters"].get("samplesheet") == "s3://b/samples.csv" for s in plan["steps"])


def test_bind_shared_input_dict_ref_fastq():
    plan = bind_shared_inputs(_fanout_plan(), [{"path": "reads_R1.fastq"}])
    assert all(s["parameters"].get("reads") == "reads_R1.fastq" for s in plan["steps"])


def test_bind_unknown_ext_or_no_input_is_noop():
    p1 = bind_shared_inputs(_fanout_plan(), ["mystery.xyz"])
    assert all(s["parameters"] == {"p": 1} for s in p1["steps"])    # unknown ext → resolver params unchanged
    p2 = bind_shared_inputs(_fanout_plan(), [])
    assert all(s["parameters"] == {"p": 1} for s in p2["steps"])    # no input → unchanged
    assert bind_shared_inputs(None, ["x.csv"]) is None


def test_bind_does_not_overwrite_and_skips_dependent_steps():
    # dependent plan (type-matched) → only the root gets the shared input
    plan = build_dag_plan([_task("a"), _task("b")], _ok, type_provider=_tp_match)
    bind_shared_inputs(plan, ["in.vcf"])
    assert plan["steps"][0]["parameters"].get("vcf") == "in.vcf"    # root bound
    assert "vcf" not in plan["steps"][1]["parameters"]              # dependent step untouched
    # does not overwrite a resolver-set param
    plan2 = _fanout_plan()
    plan2["steps"][0]["parameters"]["samplesheet"] = "already.csv"
    bind_shared_inputs(plan2, ["new.csv"])
    assert plan2["steps"][0]["parameters"]["samplesheet"] == "already.csv"


def test_to_pipeline_card_shape():
    plan = build_dag_plan([_task("a", par=[2]), _task("b", par=[1])], _ok)
    card = to_pipeline_card(plan, name="Peptide screen")
    assert card["workflow_type"] == "pipeline"      # frontend render trigger
    assert card["execution_mode"] == "dag"
    assert card["name"] == "Peptide screen"
    assert card["connections"] == plan["connections"]
    assert card["max_parallel"] == plan["max_parallel"]
    assert len(card["pipeline_steps"]) == 2
    s0 = card["pipeline_steps"][0]
    # fields the chat card / submit path read
    assert set(["id", "workflow_name", "nextflow_path", "params", "depends_on"]).issubset(s0)
    assert s0["nextflow_path"] == "a.nf"
    assert s0["depends_on"] == []
    assert to_pipeline_card(None) is None


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
