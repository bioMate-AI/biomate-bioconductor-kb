"""B4 — checker → auto-loop wrapper smoke tests."""
from __future__ import annotations
import unittest.mock as m
from galaxy.ai.drug_discovery import ind_assembly
from galaxy.ai.drug_discovery.ind_autoloop import llm_narrative_with_retry


def test_clean_first_attempt_stops_early():
    calls = []
    def fake(section_type, data, region, audit_constraint="", user_prompt_override=""):
        calls.append(audit_constraint)
        return "Genotoxicity was assessed per ICH S2(R1). The Ames bacterial reverse mutation assay was negative."
    with m.patch.object(ind_assembly, "_llm_narrative", fake):
        text, tried = llm_narrative_with_retry("tox_genotox", {}, max_attempts=3)
    assert len(calls) == 1
    assert tried == []
    assert "S2(R1)" in text and "Ames" in text


def test_failing_attempt_triggers_retry_with_constraint():
    calls = []
    outputs = [
        "Genotoxicity was assessed per ICH S2(R1). No findings.",
        "Genotoxicity was assessed per ICH S2(R1). The Ames bacterial reverse mutation assay was negative.",
    ]
    def fake(section_type, data, region, audit_constraint="", user_prompt_override=""):
        calls.append(audit_constraint)
        return outputs[len(calls) - 1] if len(calls) <= len(outputs) else outputs[-1]
    with m.patch.object(ind_assembly, "_llm_narrative", fake):
        text, tried = llm_narrative_with_retry("tox_genotox", {}, max_attempts=3)
    assert calls[0] == ""
    assert "Ames" in calls[1].lower() or "bacterial reverse" in calls[1].lower()
    assert tried == ["CONTENT_002:genotox_missing_ames"]
    assert "Ames" in text


def test_max_attempts_returns_fewest_findings():
    calls = []
    def fake(section_type, data, region, audit_constraint="", user_prompt_override=""):
        calls.append(audit_constraint)
        if len(calls) == 1:
            return "Genotoxicity was assessed. No findings."
        return "Genotoxicity per ICH S2(R1)."
    with m.patch.object(ind_assembly, "_llm_narrative", fake):
        text, tried = llm_narrative_with_retry("tox_genotox", {}, max_attempts=3)
    assert len(calls) == 3
    assert "S2(R1)" in text


def test_empty_narrative_stops_no_constraints():
    calls = []
    def fake(section_type, data, region, audit_constraint="", user_prompt_override=""):
        calls.append(audit_constraint)
        return ""
    with m.patch.object(ind_assembly, "_llm_narrative", fake):
        text, tried = llm_narrative_with_retry("tox_genotox", {}, max_attempts=2)
    assert len(calls) == 1
    assert tried == []
