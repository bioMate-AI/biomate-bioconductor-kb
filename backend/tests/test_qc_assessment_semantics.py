"""Regression tests using the real QC modules without loading Galaxy's job runner."""
import importlib.util
import ast
import json
import io
import logging
import subprocess
import sys
import threading
import time
from pathlib import Path
from types import SimpleNamespace, ModuleType

import pytest

LIB = Path(__file__).resolve().parents[1] / "lib"
sys.path.insert(0, str(LIB))


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


qc = load("qc_assessment_monitor_test", LIB / "galaxy/jobs/qc_trace_monitor.py")
cryo = load("qc_assessment_cryo_test", LIB / "galaxy/webapps/galaxy/api/cryosparc_executor.py")


@pytest.fixture
def handler(tmp_path, monkeypatch):
    monkeypatch.setattr(qc, "SUGGESTER_AVAILABLE", False)
    return qc.NextflowQCGateHandler("test", tmp_path, lambda *args: None, None)


@pytest.mark.parametrize("name", ["NCA_ANALYSIS", "NCA_PKNCA_ANALYSIS"])
def test_nca_uses_nca_rules_not_pbpk(handler, name):
    passed, failures = handler._check_qc_thresholds(name, {
        "auc_extrap_pct_max": 50, "subjects_with_no_terminal_slope": 5, "n_subjects": 10,
    })
    assert passed is True  # both checks are advisory, not execution failures
    assert {f["metric"] for f in failures} == {"auc_extrap_pct_max", "subjects_with_no_terminal_slope"}


@pytest.mark.parametrize("name,metrics", [
    ("DOCKING_AUTODOCK_VINA", {}),
    ("UNRECOGNIZED", {"score": -1}),
    ("DOCKING_AUTODOCK_VINA", {"success": True}),
])
def test_no_evaluation_is_not_a_pass(handler, name, metrics):
    assert handler._check_qc_thresholds(name, metrics) == (None, [])


def test_postprocess_failure_is_assessment_only_and_report_is_normalized(handler):
    emitted = []
    handler.sse_callback = lambda kind, data: emitted.append((kind, data))
    handler._emit_qc_gate_event("QSAR_RF_MODEL", {"cv_r2_score": 0.2}, [
        {"metric": "cv_r2_score", "value": 0.2, "threshold": 0.5, "operator": "<"},
    ])
    event = next(data for kind, data in emitted if kind == "qc_gate_triggered")
    assert event["execution_control"] == "assessment_only"
    row = handler.get_qc_report()["events"][0]
    assert (row["status"], row["measured"], row["threshold"]) == ("fail", 0.2, 0.5)
    assert "action_taken" not in row


def test_missing_metrics_are_reported_unavailable(handler):
    handler._calculate_qc_metrics = lambda *args: None
    handler.handle_process_completion("1", "QSAR_RF_MODEL", "", "COMPLETED")
    report = handler.get_qc_report()
    assert report["events"][0]["status"] == "unavailable"
    assert "All processes passed" not in report["methods_text"]
    persisted = json.loads((handler.work_dir / "qc_events.json").read_text())
    assert persisted["events"][0]["status"] == "unavailable"


def test_normalization_is_idempotent_and_preserves_provenance():
    from galaxy.ai.qc_records import normalize_qc_events
    rows = normalize_qc_events([{"type": "gate", "process_name": "ADMET", "timestamp": "t",
        "failures": [{"metric": "DILI", "value": 0.875, "threshold": 0.5,
                      "entity": "caffeine", "source": "toxicity_report.json"}]}])
    assert normalize_qc_events(rows) == rows
    assert rows[0]["entity"] == "caffeine"
    assert rows[0]["source"] == "toxicity_report.json"
    assert normalize_qc_events([{"gate": "unknown"}])[0]["status"] == "not_evaluated"


def test_model_validation_has_no_placeholder_measurements(tmp_path):
    events = []
    run = SimpleNamespace(run_id="test", progress_percent=100)
    cryo._check_model_quality_gate_from_job(None, run, lambda _, text: events.append(json.loads(text)),
        "cryoem_spa_purified", str(tmp_path), False)
    assert events[0]["status"] == "not_evaluated"
    assert events[0]["value"] is None
    assert events[0]["threshold"] is None
    persisted = json.loads((tmp_path / "qc_audit.jsonl").read_text().strip())
    assert persisted["value"] is None
    assert persisted["status"] == "not_evaluated"


def test_real_cryo_halts_still_stop_execution(tmp_path):
    gate = cryo.check_motion_gate(200, 10, "cryoem_spa_purified")
    with pytest.raises(cryo.QCHaltException):
        cryo._fire_qc_halt(SimpleNamespace(run_id="test"), None, gate, str(tmp_path))


def executor_functions(*names, **bindings):
    """Execute the actual isolated functions without bootstrapping a Galaxy app."""
    path = LIB / "galaxy/webapps/galaxy/api/nextflow_executor.py"
    tree = ast.parse(path.read_text())
    nodes = [n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name in names]
    future = ast.ImportFrom(module="__future__", names=[ast.alias(name="annotations")], level=0)
    namespace = {"log": logging.getLogger(__name__), "time": time, "subprocess": subprocess,
                 "json": json, "Path": Path, **bindings}
    exec(compile(ast.fix_missing_locations(ast.Module(body=[future, *nodes], type_ignores=[])), str(path), "exec"), namespace)
    return namespace


@pytest.mark.parametrize("status,process", [
    ("completed", None), ("succeeded", None), ("running", None),
    ("running", SimpleNamespace(poll=lambda: 0)),
])
def test_unconfirmed_pause_never_overwrites_state(status, process):
    runs = {"run": {"status": status, "process": process}}
    writes = []
    store = SimpleNamespace(get_run=lambda _: runs["run"], update_run=lambda *a, **kw: writes.append(kw))
    ns = executor_functions("_terminate_run_process", _runs=runs, _runs_lock=threading.Lock(),
        get_run_state_store=lambda: store, _find_nextflow_pids_for_run=lambda _: [])
    result = ns["_terminate_run_process"]("run", soft=True)
    assert result["ok"] is False
    assert runs["run"]["status"] == status
    assert writes == []


@pytest.mark.parametrize("fails", [False, True])
def test_pause_requires_actual_controller_termination(fails):
    def terminate():
        if fails:
            raise OSError("cannot stop")
    process = SimpleNamespace(poll=lambda: None, terminate=terminate, wait=lambda **kw: -15, pid=42)
    runs = {"run": {"status": "running", "process": process}}
    store = SimpleNamespace(get_run=lambda _: runs["run"], update_run=lambda *a, **kw: None)
    ns = executor_functions("_terminate_run_process", _runs=runs, _runs_lock=threading.Lock(),
        get_run_state_store=lambda: store, _find_nextflow_pids_for_run=lambda _: [])
    result = ns["_terminate_run_process"]("run", soft=True)
    assert result["ok"] is (not fails)
    assert runs["run"]["status"] == ("running" if fails else "paused")


def test_html_export_preserves_fail_and_unavailable_without_pass_or_retry_claim():
    ns = executor_functions("_render_qc_report_html", "_html_escape", "_render_failures_cells", "_render_warnings_cells")
    html = ns["_render_qc_report_html"]({"events": [
        {"type": "gate", "process_name": "QSAR", "timestamp": "t",
         "failures": [{"metric": "cv_r2_score", "value": 0.2, "threshold": 0.5}]},
        {"gate": "model_validation", "status": "not_evaluated"},
    ]})
    assert "cv_r2_score" in html and "0.2" in html
    assert "NOT EVALUATED" in html
    assert ">PASSED<" not in html
    assert "all processes passed automatically" not in ns["_render_qc_report_html"]({"events": []})


def test_standard_output_reconstruction_is_read_only_and_preserves_sources(handler):
    from galaxy.ai.qc_records import assess_qc_document
    rows = assess_qc_document({"process": "NCA_PKNCA_ANALYSIS", "auc_extrap_pct_max": 50},
                             handler._check_qc_thresholds, "s3://bucket/nca/qc_metrics.json")
    assert rows[0]["status"] == "advisory"
    assert rows[0]["source"] == "s3://bucket/nca/qc_metrics.json"
    assert rows[0]["execution_control"] == "assessment_only"
    rows = assess_qc_document({"_all_metrics": [{"name": "absent", "pass": None}]},
                             handler._check_qc_thresholds, "qc_report.json")
    assert rows[0]["status"] == "not_evaluated"


def test_gate_only_output_is_a_result_not_an_executed_action(handler):
    from galaxy.ai.qc_records import assess_qc_document
    from galaxy.ai.retrievers.qc_gate_reader import build_gate_event
    rows = assess_qc_document({"process": "OPENFE_ANALYSIS", "cycle_closure_kcal_per_mol": 4},
        handler._check_qc_thresholds, "qc_metrics.json",
        lambda p, m: build_gate_event(p, "openfe", m)["gates"])
    assert rows and rows[0]["status"] == "fail"
    assert "action_taken" not in rows[0]


def test_reconstruction_covers_nca_openfe_and_unknown_outputs_without_events(monkeypatch):
    jobs = ModuleType("galaxy.jobs")
    jobs.__path__ = []
    monkeypatch.setitem(sys.modules, "galaxy.jobs", jobs)
    monkeypatch.setitem(sys.modules, "galaxy.jobs.qc_trace_monitor", qc)
    monkeypatch.setattr(qc, "SUGGESTER_AVAILABLE", False)
    docs = {
        "run/nca/qc_metrics.json": {"process": "NCA_PKNCA_ANALYSIS", "auc_extrap_pct_max": 50},
        "run/openfe/qc_metrics.json": {"process": "OPENFE_ANALYSIS", "cycle_closure_kcal_per_mol": 4},
        "run/unknown/qc_metrics.json": {"process": "UNKNOWN", "value": 1},
    }
    writes = []
    client = SimpleNamespace(
        get_bucket_location=lambda **kw: {"LocationConstraint": "us-east-1"},
        get_object=lambda **kw: {"Body": io.BytesIO(json.dumps(docs[kw["Key"]]).encode())},
        put_object=lambda **kw: writes.append(kw),
    )
    monkeypatch.setitem(sys.modules, "boto3", SimpleNamespace(client=lambda *a, **kw: client))
    store = SimpleNamespace(get_run=lambda _: {"outdir": "s3://bucket/run", "qc_overrides": {}})
    ns = executor_functions("_reconstruct_qc_from_s3", get_run_state_store=lambda: store)
    failures = ns["_reconstruct_qc_from_s3"]("run", [
        {"name": "qc_metrics.json", "s3_uri": f"s3://bucket/{key}"} for key in docs
    ], "drug_discovery", {}, True)
    assert len(failures) == 1
    report = json.loads(writes[0]["Body"])
    assert {row["status"] for row in report["events"]} == {"fail", "advisory", "not_evaluated"}
    assert report["evaluation_context"] == "retrospective"
    assert all(row["source"].startswith("s3://bucket/") for row in report["events"])


def test_drug_discovery_domain_does_not_force_nca_into_admet_path(monkeypatch):
    jobs = ModuleType("galaxy.jobs")
    jobs.__path__ = []
    monkeypatch.setitem(sys.modules, "galaxy.jobs", jobs)
    monkeypatch.setitem(sys.modules, "galaxy.jobs.qc_trace_monitor", qc)
    called = []
    ns = executor_functions("_evaluate_qc_from_s3",
        _reconstruct_qc_from_s3=lambda *args: called.append(args) or [])
    ns["_evaluate_qc_from_s3"]("run", [], "drug_discovery", {}, retrospective=True)
    assert called and called[0][2] == "drug_discovery"


def test_existing_cryo_completion_assessment_keeps_its_report_path(monkeypatch):
    jobs = ModuleType("galaxy.jobs")
    jobs.__path__ = []
    monkeypatch.setitem(sys.modules, "galaxy.jobs", jobs)
    monkeypatch.setitem(sys.modules, "galaxy.jobs.qc_trace_monitor", qc)
    ns = executor_functions("_evaluate_qc_from_s3", _build_qc_report_from_s3_files=lambda *args: {
        "_all_metrics": [{"name": "FSC 0.143 resolution (Å)", "measured": 10,
                          "threshold": 4, "pass": False, "unit": "Å"}],
    })
    failures = ns["_evaluate_qc_from_s3"]("run", [{"s3_uri": "s3://bucket/run/fsc.json"}], "cryo_em", {})
    assert len(failures) == 1
    assert failures[0]["metric"] == "fsc_resolution_angstrom"
