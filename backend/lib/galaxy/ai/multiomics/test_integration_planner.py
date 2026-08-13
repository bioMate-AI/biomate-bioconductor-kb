"""Tests for the multi-omics integration planner (recommendation → runnable plan).
Run: `cd backend && PYTHONPATH=lib python3.9 lib/galaxy/ai/multiomics/test_integration_planner.py`
"""
from galaxy.ai.multiomics.integration_planner import (
    plan_integration, to_execute_request, plan_pipeline, resolve_pipeline, run_pipeline,
    METHOD_WORKFLOW, OMICS_NORMALIZE_WORKFLOW,
)
from galaxy.ai.multiomics.method_selector import Modality

S = [f"s{i}" for i in range(50)]


def M(name, dtype, ids, feats=2000):
    return Modality(name=name, data_type=dtype, sample_ids=ids, n_features=feats)


def test_paired_continuous_plans_mofa2():
    mods = [M("rna", "rna", S), M("prot", "proteomics", S)]
    plan = plan_integration(mods, {"rna": "s3://a/rna.csv", "prot": "s3://a/prot.csv"})
    assert plan["runnable"] is True, plan
    assert plan["method"] == "MOFA2", plan["method"]
    assert plan["workflow_path"].endswith("mofa2/main.nf"), plan["workflow_path"]
    assert plan["params"]["omics"] == ["s3://a/rna.csv", "s3://a/prot.csv"]
    assert plan["params"]["n_factors"] == 10
    assert plan["normalization_plan"]["rna"]  # normalization carried through


def test_clustering_goal_plans_snf():
    mods = [M("rna", "rna", S), M("meth", "methylation", S)]
    plan = plan_integration(mods, {"rna": "a", "meth": "b"}, goal="clustering", n_clusters=3)
    assert plan["method"] == "SNF", plan["method"]
    assert plan["workflow_path"].endswith("snf_multiomics/main.nf")
    assert plan["params"]["n_clusters"] == 3
    assert "n_factors" not in plan["params"]


def test_partial_overlap_stabmap_not_runnable():
    a = [f"s{i}" for i in range(50)]
    b = [f"s{i}" for i in range(25, 75)]  # only partial sample overlap → mosaic
    mods = [M("rna", "scrna", a), M("atac", "scatac", b)]
    plan = plan_integration(mods, {"rna": "a", "atac": "b"})
    assert plan["method"] == "StabMap", plan["method"]
    assert plan["runnable"] is False
    assert plan["workflow_path"] is None
    assert "not yet packaged" in plan["reason"]


def test_no_heavy_deps_plans_mfa_with_concat_warning():
    mods = [M("rna", "rna", S), M("prot", "proteomics", S)]
    plan = plan_integration(mods, {"rna": "a", "prot": "b"}, constraints={"no_heavy_deps": True})
    assert plan["method"] == "MFA", plan["method"]
    assert plan["workflow_path"].endswith("rgcca_multiomics/main.nf")
    assert plan["runnable"] is True
    assert any("concatenat" in w.lower() for w in plan["warnings"]), plan["warnings"]


def test_missing_path_raises():
    mods = [M("rna", "rna", S), M("prot", "proteomics", S)]
    try:
        plan_integration(mods, {"rna": "a"})  # 'prot' path missing
        assert False, "expected ValueError"
    except ValueError as e:
        assert "prot" in str(e), str(e)


def test_single_modality_not_runnable():
    plan = plan_integration([M("rna", "rna", S)], {"rna": "a"})
    assert plan["method"] is None
    assert plan["runnable"] is False


def test_to_execute_request_shape():
    mods = [M("rna", "rna", S), M("prot", "proteomics", S)]
    plan = plan_integration(mods, {"rna": "s3://a", "prot": "s3://b"})
    req = to_execute_request(plan)
    assert req["nextflow_path"].endswith("mofa2/main.nf")
    assert req["params"]["omics"] == ["s3://a", "s3://b"]


def test_to_execute_request_rejects_unrunnable():
    try:
        to_execute_request({"runnable": False, "reason": "x"})
        assert False, "expected ValueError"
    except ValueError:
        pass


def test_pipeline_normalizes_then_integrates():
    mods = [M("rna", "rna", S), M("prot", "proteomics", S)]
    pipe = plan_pipeline(mods, {"rna": "s3://a/rna.csv", "prot": "s3://a/prot.csv"})
    assert pipe["runnable"] is True
    assert pipe["method"] == "MOFA2"
    assert len(pipe["steps"]) == 2
    s0, s1 = pipe["steps"]
    # step 0: normalize the RAW modality files
    assert s0["step"] == "normalize"
    assert s0["workflow_path"] == OMICS_NORMALIZE_WORKFLOW
    assert s0["params"]["omics"] == ["s3://a/rna.csv", "s3://a/prot.csv"]
    # step 1: integrate the NORMALIZED outputs of step 0
    assert s1["step"] == "integrate"
    assert s1["workflow_path"].endswith("mofa2/main.nf")
    # placeholder carries the DETERMINISTIC normalized basenames (view = input stem)
    assert s1["params"]["omics"] == {
        "from_step": 0, "output": "normalized",
        "views": ["normalized_rna.csv", "normalized_prot.csv"],
    }
    assert s1["params"]["n_factors"] == 10


def test_pipeline_resolves_to_concrete_execute_requests():
    mods = [M("rna", "rna", S), M("prot", "proteomics", S)]
    pipe = plan_pipeline(mods, {"rna": "s3://in/rna.csv", "prot": "s3://in/prot.csv"},
                         outdir="s3://out/run1")
    # step 0 ran and produced this output prefix; resolve step 1 against it
    reqs = resolve_pipeline(pipe, ["s3://out/run1/normalize", None])
    assert len(reqs) == 2
    assert reqs[0]["nextflow_path"] == OMICS_NORMALIZE_WORKFLOW
    assert reqs[0]["params"]["omics"] == ["s3://in/rna.csv", "s3://in/prot.csv"]
    assert reqs[1]["nextflow_path"].endswith("mofa2/main.nf")
    assert reqs[1]["params"]["omics"] == [
        "s3://out/run1/normalize/normalized_rna.csv",
        "s3://out/run1/normalize/normalized_prot.csv",
    ]


def test_pipeline_resolve_requires_upstream_prefix():
    mods = [M("rna", "rna", S), M("prot", "proteomics", S)]
    pipe = plan_pipeline(mods, {"rna": "a/rna.csv", "prot": "a/prot.csv"})
    try:
        resolve_pipeline(pipe, [None, None])  # step 0 prefix not yet available
        assert False, "expected ValueError"
    except ValueError as e:
        assert "step 0" in str(e)


def test_run_pipeline_sequences_and_wires_outputs():
    mods = [M("rna", "rna", S), M("prot", "proteomics", S)]
    pipe = plan_pipeline(mods, {"rna": "s3://in/rna.csv", "prot": "s3://in/prot.csv"})
    calls = []

    def fake_execute(nextflow_path, params):
        calls.append((nextflow_path, params["omics"]))
        # emulate the executor returning each run's output prefix
        return "s3://out/normalize" if "omics_normalize" in nextflow_path else "s3://out/mofa2"

    results = run_pipeline(pipe, fake_execute)
    assert len(results) == 2
    # step 0 ran on the RAW inputs
    assert calls[0][0] == OMICS_NORMALIZE_WORKFLOW
    assert calls[0][1] == ["s3://in/rna.csv", "s3://in/prot.csv"]
    # step 1 ran on step-0's NORMALIZED outputs (wired from the returned prefix)
    assert calls[1][0].endswith("mofa2/main.nf")
    assert calls[1][1] == [
        "s3://out/normalize/normalized_rna.csv",
        "s3://out/normalize/normalized_prot.csv",
    ]
    assert results[1]["output_prefix"] == "s3://out/mofa2"


def test_run_pipeline_raises_if_step_yields_no_prefix():
    mods = [M("rna", "rna", S), M("prot", "proteomics", S)]
    pipe = plan_pipeline(mods, {"rna": "s3://in/rna.csv", "prot": "s3://in/prot.csv"})
    try:
        run_pipeline(pipe, lambda p, params: None)  # executor returns nothing
        assert False, "expected ValueError"
    except ValueError as e:
        assert "no output prefix" in str(e)


def test_pipeline_warns_on_basename_collision():
    mods = [M("rna", "rna", S), M("prot", "proteomics", S)]
    # both inputs share basename "data.csv" → normalized_data.csv would collide
    pipe = plan_pipeline(mods, {"rna": "s3://a/data.csv", "prot": "s3://b/data.csv"})
    assert any("basename" in w for w in pipe["warnings"]), pipe["warnings"]


def test_pipeline_unrunnable_method_yields_no_steps():
    a = [f"s{i}" for i in range(50)]
    b = [f"s{i}" for i in range(25, 75)]
    pipe = plan_pipeline([M("rna", "scrna", a), M("atac", "scatac", b)],
                         {"rna": "a", "atac": "b"})
    assert pipe["method"] == "StabMap"
    assert pipe["runnable"] is False
    assert pipe["steps"] == []


def test_every_mapped_method_matches_a_canonical_name():
    # Guard: METHOD_WORKFLOW keys must be canonical names the selector can emit.
    from galaxy.ai.multiomics import method_selector as ms
    known = set(getattr(ms, "_METHOD_DESCRIPTIONS", {}).keys()) or {
        "MOFA2", "SNF", "MCIA", "intNMF", "iClusterPlus", "JIVE", "MFA", "StabMap",
    }
    for k in METHOD_WORKFLOW:
        assert k in known, f"{k} not a known method name"


if __name__ == "__main__":
    tests = [v for k, v in sorted(globals().items()) if k.startswith("test_") and callable(v)]
    passed = 0
    for t in tests:
        try:
            t()
            print(f"  PASS {t.__name__}")
            passed += 1
        except Exception as e:
            print(f"  FAIL {t.__name__}: {e}")
    print(f"\n{passed}/{len(tests)} tests passed")
    raise SystemExit(0 if passed == len(tests) else 1)
