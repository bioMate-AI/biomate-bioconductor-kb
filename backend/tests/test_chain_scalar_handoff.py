"""Unit tests for the chain scalar {{stepN.field}} handoff resolver
(workflow_chain.substitute_step_templates / _flatten_scalars). This is the fix for
the defect found in the 2026-10-24 live proof: the chain executor only wired output
FILES, so a scalar like ADMET herg_ic50 never reached CiPA — step 2 ran with the
literal '{{step1.herg_ic50_nM}}'. These tests pin the pure resolution logic."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parents[1] / "lib"))

from galaxy.webapps.galaxy.api.workflow_chain import (  # noqa: E402
    substitute_step_templates,
    _flatten_scalars,
)


def test_flatten_scalars_leaf_and_dotted():
    out = {}
    _flatten_scalars({"herg_ic50_nM": 12.0, "qc": {"dili_risk": "high", "p": 0.875}}, out)
    assert out["herg_ic50_nM"] == 12.0          # leaf
    assert out["dili_risk"] == "high"           # nested leaf
    assert out["qc.dili_risk"] == "high"        # dotted path
    assert out["qc.p"] == 0.875


def test_whole_value_template_keeps_type():
    params = {"herg_ic50_nM": "{{step1.herg_ic50_nM}}", "cmax_nM": "{{step1.cmax_nM}}"}
    scalars = {1: {"herg_ic50_nM": 12.0, "cmax_nM": 3.4}}
    out, warnings = substitute_step_templates(params, scalars)
    assert out["herg_ic50_nM"] == 12.0 and isinstance(out["herg_ic50_nM"], float)
    assert out["cmax_nM"] == 3.4
    assert warnings == []


def test_dotted_field_resolves():
    params = {"risk": "{{step1.qc.dili_risk}}"}
    out, _ = substitute_step_templates(params, {1: {"qc.dili_risk": "high"}})
    assert out["risk"] == "high"


def test_embedded_template_string_substitution():
    params = {"note": "hERG={{step1.herg_ic50_nM}} uM at step1"}
    out, warnings = substitute_step_templates(params, {1: {"herg_ic50_nM": 12.0}})
    assert out["note"] == "hERG=12.0 uM at step1"
    assert warnings == []


def test_unresolved_template_is_left_literal_and_warned():
    # The live-proof case: the field name does not exist in step1's outputs.
    params = {"herg_ic50_nM": "{{step1.herg_ic50_nM}}"}
    out, warnings = substitute_step_templates(params, {1: {"herg_ic50_uM": 0.012}})
    assert out["herg_ic50_nM"] == "{{step1.herg_ic50_nM}}"   # unchanged, not a default
    assert len(warnings) == 1 and "herg_ic50_nM" in warnings[0]


def test_non_string_and_plain_params_pass_through():
    params = {"n": 500, "model": "MPNN", "flag": True}
    out, warnings = substitute_step_templates(params, {1: {}})
    assert out == params and warnings == []


def test_no_prior_step_scalars_warns_not_crashes():
    out, warnings = substitute_step_templates({"x": "{{step2.foo}}"}, {})
    assert out["x"] == "{{step2.foo}}" and len(warnings) == 1
