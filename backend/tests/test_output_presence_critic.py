"""Tests for the generic OutputPresence / low-N result-floor critic.

Advisory-only (FLAG). Covers the three result-floor conditions (missing/absent
outputs, empty tables, zero significant features), the silence path for a healthy
run, grounding, and end-to-end dispatch.

Run:
    cd backend && PYTHONPATH=lib python3.9 -m pytest tests/test_output_presence_critic.py -q
"""
import sys
import types
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
_LIB = ROOT / "backend" / "lib"
sys.path.insert(0, str(_LIB))

try:  # noqa: SIM105
    import galaxy.ai.critics  # noqa: F401
except Exception:
    _stub = types.ModuleType("galaxy.ai")
    _stub.__path__ = [str(_LIB / "galaxy" / "ai")]
    sys.modules["galaxy.ai"] = _stub

from galaxy.ai.critics import (  # noqa: E402
    RunContext, RemediationKind, Severity, run_critics_from_run_meta, get_registry,
)
from galaxy.ai.critics.critics.output_presence import OutputPresenceCritic  # noqa: E402


def _manifest(files):
    return {"kind": "results_manifest", "run_id": "run-x",
            "workflow_domain": "transcriptomics", "files": files}


def _ctx(design, files, inline=None):
    return RunContext.from_contract(design, _manifest(files), inline_artifacts=inline)


# ── validation fixtures: SILENT (healthy run) ─────────────────────────────────

DESIGN = {"kind": "design", "run_id": "run-x", "workflow_domain": "transcriptomics",
          "design": {}}
HEALTHY_FILES = [{"name": "de_results.csv", "role": "table", "size": 4096},
                 {"name": "pipeline.log", "role": "log", "size": 200}]
HEALTHY_SUMMARY = {"results_summary.json": {"n_significant": 128, "n_rows": 2000}}


def test_output_presence_silent_on_healthy_run():
    ctx = _ctx(DESIGN, HEALTHY_FILES, HEALTHY_SUMMARY)
    assert OutputPresenceCritic().detect(ctx) == []


def test_output_presence_silent_without_manifest():
    # bare context (no manifest) must NOT guess that the run failed.
    ctx = RunContext(run_id="r")
    assert OutputPresenceCritic().detect(ctx) == []


# ── 1. missing / absent outputs ───────────────────────────────────────────────

def test_missing_declared_expected_output_fires():
    design = {"design": {"expected_outputs": ["deseq2_results.csv"]}}
    ctx = _ctx(design, [{"name": "pipeline.log", "role": "log", "size": 10}])
    iss = next(i for i in OutputPresenceCritic().detect(ctx)
               if i.code == "missing_expected_outputs")
    assert "deseq2_results.csv" in iss.subjects
    assert iss.severity == Severity.WARNING
    assert iss.is_cited


def test_no_primary_output_when_only_qc_and_logs():
    ctx = _ctx(DESIGN, [{"name": "qc_report.html", "role": "qc", "size": 500},
                        {"name": "run.log", "role": "log", "size": 50}])
    iss = next(i for i in OutputPresenceCritic().detect(ctx) if i.code == "no_primary_output")
    assert iss.severity == Severity.WARNING
    assert iss.is_cited


def test_no_outputs_when_manifest_declares_zero_files():
    ctx = _ctx(DESIGN, [])
    iss = next(i for i in OutputPresenceCritic().detect(ctx) if i.code == "no_outputs")
    assert iss.metrics["n_outputs"] == 0


# ── 2. empty result tables ────────────────────────────────────────────────────

def test_empty_result_table_fires_on_zero_bytes():
    ctx = _ctx(DESIGN, [{"name": "de_results.csv", "role": "table", "size": 0}])
    iss = next(i for i in OutputPresenceCritic().detect(ctx) if i.code == "empty_results")
    assert "de_results.csv" in iss.subjects
    assert iss.severity == Severity.WARNING
    assert iss.is_cited


# ── 3. zero significant features (ADVISORY null result) ───────────────────────

def test_zero_significant_features_is_advisory():
    ctx = _ctx(DESIGN,
               [{"name": "de_results.csv", "role": "table", "size": 2048}],
               inline={"results_summary.json": {"n_significant": 0, "n_rows": 1500}})
    iss = next(i for i in OutputPresenceCritic().detect(ctx)
               if i.code == "zero_significant_features")
    assert iss.severity == Severity.ADVISORY   # legitimate null result, surfaced not alarmed
    assert iss.is_cited
    # a non-empty table with zero hits is NOT an "empty_results" issue
    assert not any(i.code == "empty_results" for i in OutputPresenceCritic().detect(ctx))


# ── remediation ───────────────────────────────────────────────────────────────

def test_output_presence_remediation_is_advisory_flag():
    critic = OutputPresenceCritic()
    ctx = _ctx(DESIGN, [{"name": "de_results.csv", "role": "table", "size": 0}])
    iss = critic.detect(ctx)[0]
    rem = critic.remediate(iss, ctx)
    assert rem.kind == RemediationKind.FLAG
    assert rem.params_delta == {}
    assert rem.applied is False


# ── end-to-end through hook + registry ────────────────────────────────────────

def test_output_presence_issues_carry_confidence_hint():
    # a run that trips several floors at once
    ctx = _ctx({"design": {"expected_outputs": ["deseq2_results.csv"]}},
               [{"name": "de_results.csv", "role": "table", "size": 0}],
               inline={"results_summary.json": {"n_significant": 0}})
    issues = OutputPresenceCritic().detect(ctx)
    assert issues
    for iss in issues:
        c = getattr(iss, "confidence", None)
        assert c is not None and 0.0 < c <= 1.0


def test_output_presence_registered_in_default_registry():
    ids = {c.critic_id for c in get_registry().all()}
    assert "output.presence" in ids


def test_output_presence_full_hook_publishes_missing_output():
    design = {"run_id": "run-x", "workflow_domain": "transcriptomics",
              "design": {"expected_outputs": ["deseq2_results.csv"]}}
    run_meta = {"run_id": "run-x", "design": design,
                "results_manifest": _manifest([{"name": "pipeline.log", "role": "log", "size": 5}])}
    report = run_critics_from_run_meta(run_meta)
    codes = {f.issue.code for f in report.findings if f.published}
    assert "missing_expected_outputs" in codes
