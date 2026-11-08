"""Declared-gate fallback in NextflowQCGateHandler._check_qc_thresholds.

Covers the general data-driven path added 2026-11-04: a workflow process with
NO hardcoded QC branch can still get real gates by DECLARING them in its
qc_metrics.json (a `gates` / `declared_gates` list). The hardcoded branches are
untouched; this only adds evaluation of declared gates and folds the results
into the existing (qc_passed, failures) return.
"""
import sys
import tempfile
from pathlib import Path
from unittest.mock import Mock

sys.path.insert(0, str(Path(__file__).parent.parent / "lib"))

from galaxy.jobs.qc_trace_monitor import NextflowQCGateHandler


# A process name that matches NONE of the hardcoded `in process_upper` branches.
NOVEL_PROC = "SOME_NOVEL_DOMAIN_STEP"


def _handler():
    return NextflowQCGateHandler(
        invocation_id="test-inv",
        work_dir=Path(tempfile.mkdtemp()),
        sse_callback=lambda t, d: None,
        app=Mock(),
        workflow_domain="novel_domain",
    )


def test_no_gates_no_hardcoded_branch_is_unchanged():
    """No declared gates + no hardcoded match → (None, []) exactly as before."""
    h = _handler()
    assert h._check_qc_thresholds(NOVEL_PROC, {"some_metric": 0.9}) == (None, [])


def test_declared_halt_gate_blocks():
    """A failing halt gate on a brand-new domain blocks the run (qc_passed False)."""
    h = _handler()
    passed, failures = h._check_qc_thresholds(NOVEL_PROC, {
        "concordance": 0.55,
        "gates": [
            {"metric": "concordance", "op": ">=", "threshold": 0.80,
             "severity": "halt", "name": "Concordance gate",
             "evidence": "institutional SOP v3", "provenance": "institutional"},
        ],
    })
    assert passed is False                       # blocking failure present
    assert len(failures) == 1
    f = failures[0]
    assert f["metric"] == "concordance"
    assert f["advisory"] is False
    assert f["value"] == 0.55 and f["threshold"] == 0.80
    assert f["provenance"] == "institutional"


def test_declared_advisory_gate_does_not_block():
    """A failing advisory gate is reported but does NOT block (qc_passed True)."""
    h = _handler()
    passed, failures = h._check_qc_thresholds(NOVEL_PROC, {
        "noise_fraction": 0.42,
        "gates": [
            {"metric": "noise_fraction", "op": "<=", "threshold": 0.30,
             "severity": "advisory", "name": "Noise advisory"},
        ],
    })
    assert passed is True                        # advisory is non-blocking
    assert len(failures) == 1
    assert failures[0]["advisory"] is True


def test_declared_passing_gate_yields_no_failure():
    """A gate whose condition is satisfied produces no failure and passes."""
    h = _handler()
    passed, failures = h._check_qc_thresholds(NOVEL_PROC, {
        "concordance": 0.95,
        "gates": [
            {"metric": "concordance", "op": ">=", "threshold": 0.80, "severity": "halt"},
        ],
    })
    assert passed is True
    assert failures == []


def test_mixed_halt_and_advisory():
    """One halt (fails) + one advisory (fails) → blocked, both reported."""
    h = _handler()
    passed, failures = h._check_qc_thresholds(NOVEL_PROC, {
        "concordance": 0.55, "noise_fraction": 0.42,
        "gates": [
            {"metric": "concordance", "op": ">=", "threshold": 0.80, "severity": "halt"},
            {"metric": "noise_fraction", "op": "<=", "threshold": 0.30, "severity": "advisory"},
        ],
    })
    assert passed is False
    assert len(failures) == 2
    advisory = {f["metric"]: f["advisory"] for f in failures}
    assert advisory["concordance"] is False
    assert advisory["noise_fraction"] is True


def test_dict_form_declared_gates_also_work():
    """Declared gates given as a name→spec dict (not a list) are accepted."""
    h = _handler()
    passed, failures = h._check_qc_thresholds(NOVEL_PROC, {
        "concordance": 0.55,
        "declared_gates": {
            "Concordance gate": {"metric": "concordance", "op": ">=",
                                 "threshold": 0.80, "severity": "halt"},
        },
    })
    assert passed is False
    assert failures[0]["metric"] == "concordance"


def test_malformed_gates_never_break_the_path():
    """A bad gate spec must not raise — fallback is best-effort (returns None,[])."""
    h = _handler()
    # threshold missing → GateSpecError inside the engine → swallowed.
    result = h._check_qc_thresholds(NOVEL_PROC, {
        "concordance": 0.55,
        "gates": [{"metric": "concordance", "op": ">="}],
    })
    assert result == (None, [])


if __name__ == "__main__":
    import pytest
    raise SystemExit(pytest.main([__file__, "-v"]))
