"""Unit tests for the Phase-0 run-contract population + the critic-hook attach.

Covers the GATING workstream (make the run contract real + wire the post-run critic
hook) added to ``nextflow_executor.py``:

  * ``_build_design_json`` now populates a REAL design block (non-null formula /
    covariates / exposure) per workflow class — asserted for a bioc survival (Cox)
    case AND an nf-core differentialabundance (DESeq2) case, plus the declared
    contract inputs (exposure / known_confounders / known_batch) carried from params,
    and the nf-core samplesheet group-size inference.
  * ``_run_critic_hook`` returns an explicit ``{"status":"not_judged"}`` marker for a
    gap/failed run (no readable contract) so it does NOT present as clean, and a real
    ``critic_report`` for a healthy run.
  * ``_infer_workflow_domain`` stamps a real domain (so critic dispatch is by-domain).

Pure Python — no AWS / R / network. The executor module imports the heavy Galaxy app
at top level, which is not available in a minimal/sparse checkout, so we import the
module in isolation behind lightweight stubs for the few Galaxy symbols it needs.

Run:
    cd backend && PYTHONPATH=lib python3.9 -m pytest tests/test_design_contract_and_critic_hook.py -q
    cd backend && PYTHONPATH=lib python3.9 tests/test_design_contract_and_critic_hook.py   # direct
"""
import importlib.util
import json
import sys
import types
from pathlib import Path

_LIB = Path(__file__).resolve().parents[1] / "lib"


def _load_executor_isolated():
    """Load galaxy.webapps.galaxy.api.nextflow_executor behind stubs for the heavy
    Galaxy imports it does at module scope (Router / DependsOnTrans / ProvidesUserContext
    / galaxy.ai.runs). The critics package (galaxy.ai.critics) is loaded for REAL from
    the same lib, so the hook attach exercises the real framework."""
    sys.path.insert(0, str(_LIB))

    def _mod(name, path=None):
        m = types.ModuleType(name)
        if path is not None:
            m.__path__ = path
        sys.modules[name] = m
        return m

    if "galaxy" not in sys.modules:
        _mod("galaxy", [str(_LIB / "galaxy")])
    _mod("galaxy.managers", [])
    ctx = _mod("galaxy.managers.context")
    ctx.ProvidesUserContext = type("ProvidesUserContext", (), {})
    _mod("galaxy.webapps", [])
    _mod("galaxy.webapps.galaxy", [])
    api = _mod("galaxy.webapps.galaxy.api", [str(_LIB / "galaxy/webapps/galaxy/api")])

    class _Router:
        def __init__(self, *a, **k):
            pass

        def __getattr__(self, _n):
            def _deco(*a, **k):
                def _wrap(fn):
                    return fn
                return _wrap
            return _deco

    api.Router = _Router
    api.DependsOnTrans = object()
    # galaxy.ai is a REAL namespace package (critics live under it); only stub .runs.
    if "galaxy.ai" not in sys.modules:
        _mod("galaxy.ai", [str(_LIB / "galaxy/ai")])
    runs = _mod("galaxy.ai.runs")
    runs.get_run_state_store = lambda *a, **k: None
    boot = _mod("galaxy.ai.runs.bootstrap")
    boot.ensure_poller_started = lambda *a, **k: None

    spec = importlib.util.spec_from_file_location(
        "galaxy.webapps.galaxy.api.nextflow_executor",
        str(_LIB / "galaxy/webapps/galaxy/api/nextflow_executor.py"),
    )
    m = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = m
    spec.loader.exec_module(m)
    return m


NE = _load_executor_isolated()


def _loader_for(files):
    """An artifact_loader serving a dict of {s3_uri: dict/str} as JSON bytes."""
    def _loader(ref):
        v = files.get(ref)
        if v is None:
            return None
        if isinstance(v, (dict, list)):
            return json.dumps(v).encode("utf-8")
        return v.encode("utf-8") if isinstance(v, str) else v
    return _loader


# ── Task 1: design.json population ────────────────────────────────────────────

def test_design_json_bioc_survival_populates_formula_and_covariates():
    qc_uri = "s3://b/run1/survival_qc.json"
    survival_qc = {
        "primary_covariate": "treatment",
        "naive_primary_hr": 0.817,
        "adjusted_primary_hr": 0.806,
        "schoenfeld_global_p": 0.21,
        "omitted_confounders": [
            {"name": "ecog", "hr": 1.9, "p": 0.003},
            {"name": "liver_mets", "hr": 2.1, "p": 0.01},
        ],
    }
    info = {"nextflow_path": "bioc/survival/cox_proportional_hazards_regression.nf",
            "workflow_domain": "survival"}
    files = [{"name": "survival_qc.json", "s3_uri": qc_uri}]
    design = NE._build_design_json(
        "run1", info, {"exposure_of_interest": "treatment"},
        s3_output_files=files, artifact_loader=_loader_for({qc_uri: survival_qc}),
    )
    blk = design["design"]
    assert design["schema_version"] == "1.1"
    assert blk["formula"] and "Surv" in blk["formula"], blk
    assert "treatment" in blk["covariates"] and "ecog" in blk["covariates"], blk
    assert blk["exposure_of_interest"] == "treatment"
    assert "ecog" in blk["candidate_covariates"]
    assert blk["design_source"] == "workflow"


def test_design_json_nfcore_diffab_populates_formula_and_covariates():
    qc_uri = "s3://b/run2/qc_metrics.json"
    qc_metrics = {
        "domain": "transcriptomics",
        "design_qc": {
            "treated_vs_control": {
                "blocking_var": "cell_line",
                "confounded": True,
                "naive_design": "~condition",
                "final_design": "~cell_line+condition",
                "n_sig_block": 400,
                "n_sig_corrected": 1028,
            }
        },
    }
    info = {"nextflow_path": "nfcore/differentialabundance/main.nf",
            "workflow_domain": "transcriptomics"}
    files = [{"name": "qc_metrics.json", "s3_uri": qc_uri}]
    design = NE._build_design_json(
        "run2", info, {}, s3_output_files=files,
        artifact_loader=_loader_for({qc_uri: qc_metrics}),
    )
    blk = design["design"]
    assert blk["formula"] == "~cell_line+condition", blk
    assert blk["covariates"] == ["cell_line", "condition"], blk
    assert "cell_line" in blk["candidate_covariates"]
    assert blk["exposure_of_interest"] == "condition"
    assert blk["contrasts"] and blk["contrasts"][0]["id"] == "treated_vs_control"


def test_design_json_declared_inputs_carried_and_not_overwritten():
    params = {"exposure_of_interest": "drug", "known_confounders": "age, sex",
              "known_batch": ["plate"]}
    design = NE._build_design_json("r", {"nextflow_path": "x/y.nf"}, params)
    blk = design["design"]
    assert blk["exposure_of_interest"] == "drug"
    assert blk["known_confounders"] == ["age", "sex"]
    assert blk["known_batch"] == ["plate"]


def test_design_json_nfcore_samplesheet_group_sizes_inferred():
    ss_uri = "s3://b/run3/samplesheet.csv"
    csv = "sample,condition,batch\ns1,treated,b1\ns2,treated,b2\ns3,control,b1\ns4,control,b2\n"
    info = {"nextflow_path": "nfcore/rnaseq/main.nf", "workflow_domain": "transcriptomics"}
    # samplesheet is an input param the loader can fetch by its path
    params = {"samplesheet": ss_uri}
    design = NE._build_design_json(
        "run3", info, params, s3_output_files=[],
        artifact_loader=_loader_for({ss_uri: csv}),
    )
    blk = design["design"]
    assert blk["group_sizes"] == {"treated": 2, "control": 2}, blk
    assert blk["design_source"] == "inferred"
    assert "batch" in blk["candidate_covariates"]


def test_design_json_backward_compatible_legacy_keys_present():
    design = NE._build_design_json("r", {"nextflow_path": "x/y.nf"}, {})
    blk = design["design"]
    # legacy v1.0 keys must still exist (additive change)
    for k in ("formula", "covariates", "group_sizes"):
        assert k in blk
    assert blk["formula"] is None and blk["covariates"] == []


# ── Task 2/4: not-judged marker + hook attach ─────────────────────────────────

def test_critic_hook_gap_run_is_not_judged():
    report = NE._run_critic_hook("gap1", {"run_id": "gap1"})  # no design/results_manifest
    assert report is not None
    assert report.get("status") == "not_judged"
    assert report.get("reason") == "no readable contract"


def test_critic_hook_healthy_run_returns_critic_report():
    run_meta = {
        "run_id": "ok1",
        "workflow_domain": "survival",
        "design": {"design": {"formula": "Surv(time,status) ~ treatment"}},
        "results_manifest": {"files": []},
    }
    report = NE._run_critic_hook("ok1", run_meta)
    assert report is not None
    # healthy run → a real critic report envelope (NOT the not_judged marker)
    assert report.get("status") != "not_judged"
    assert report.get("kind") == "critic_report"


# ── Task 5: domain stamping ───────────────────────────────────────────────────

def test_infer_workflow_domain_from_path():
    assert NE._infer_workflow_domain(
        "bioc/survival/cox_proportional_hazards_regression.nf") == "survival"
    assert NE._infer_workflow_domain(
        "nfcore/differentialabundance/main.nf") == "transcriptomics"


def _run_all():
    fns = [v for k, v in sorted(globals().items()) if k.startswith("test_") and callable(v)]
    passed = 0
    for fn in fns:
        fn()
        print(f"  PASS {fn.__name__}")
        passed += 1
    print(f"\n{passed}/{len(fns)} tests passed")


if __name__ == "__main__":
    _run_all()
