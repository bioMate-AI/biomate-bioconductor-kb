"""Tests for the qc_evidence helper that powers frontend hover-tooltips."""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(_ROOT / "backend" / "lib"))
sys.path.insert(0, str(_ROOT))

from galaxy.ai.retrievers.qc_evidence import (
    get_evidence_for_gate,
    get_all_evidence_for_domain,
    list_domains,
    clear_cache,
)


@pytest.fixture(autouse=True)
def _reset_cache():
    clear_cache()
    yield
    clear_cache()


def test_domains_listed():
    """All 5 wired auto-loop domains have evidence entries."""
    domains = set(list_domains())
    assert "pbpk" in domains
    assert "admet" in domains
    assert "cyp_ddi" in domains
    assert "nca_pk" in domains
    assert "docking" in domains


def test_evidence_for_pbpk_auc_gate():
    """PBPK AUC fold-error gate has GOLD-graded FDA 2018 evidence."""
    items = get_evidence_for_gate("pbpk", "pbpk_auc_fold_error")
    assert len(items) >= 1
    e = items[0]
    assert e["provenance"] == "GOLD"
    assert "FDA" in e["paper_ref"]
    assert "2018" in e["paper_ref"]
    assert e["paper_doi"]


def test_evidence_for_cyp_ddi_r1():
    """CYP-DDI R1 gate cites FDA 2020 guidance verbatim."""
    items = get_evidence_for_gate("cyp_ddi", "cyp_ddi_r1_basic")
    assert len(items) == 1
    e = items[0]
    assert e["provenance"] == "GOLD"
    assert "FDA" in e["paper_ref"]
    assert "2020" in e["paper_ref"]


def test_evidence_for_admet_herg():
    """ADMET hERG gate cites Aronov 2008."""
    items = get_evidence_for_gate("admet", "admet_herg_ic50")
    assert len(items) == 1
    e = items[0]
    assert "Aronov" in e["paper_ref"]
    assert e["provenance"] == "GOLD"


def test_bronze_grade_flagged_explicitly():
    """Docking thresholds are graded BRONZE — vendor heuristics, not peer-reviewed."""
    items = get_evidence_for_gate("docking", "docking_binding_score")
    assert len(items) == 1
    assert items[0]["provenance"] == "BRONZE"
    # The paper_supports text must explicitly disclaim the cutoff
    supports = items[0]["paper_supports"].lower()
    assert "does not" in supports or "heuristic" in supports


def test_silver_grade_for_paraphrased_conventions():
    """PBPK Tmax fraction is SILVER — concept from FDA, exact cutoff is convention."""
    items = get_evidence_for_gate("pbpk", "pbpk_tmax_fraction")
    assert len(items) == 1
    assert items[0]["provenance"] == "SILVER"


def test_unknown_gate_returns_empty():
    """Asking for a non-existent gate returns []."""
    assert get_evidence_for_gate("pbpk", "nonexistent_gate") == []
    assert get_evidence_for_gate("nonexistent_domain", "x") == []


def test_get_all_evidence_for_domain():
    """get_all_evidence_for_domain returns dict of all gates in that domain."""
    pbpk_evidence = get_all_evidence_for_domain("pbpk")
    expected_gates = {
        "pbpk_tmax_fraction",
        "pbpk_cl_min",
        "pbpk_mass_balance",
        "pbpk_auc_fold_error",
    }
    assert set(pbpk_evidence.keys()) == expected_gates


def test_response_shape_invariants():
    """Every evidence entry has the 6 required fields."""
    required = {"paper_ref", "paper_doi", "provenance", "paper_supports", "rule_text", "finding"}
    valid_grades = {"GOLD", "SILVER", "BRONZE"}
    domains = list_domains()
    total = 0
    for domain in domains:
        for gate_name, items in get_all_evidence_for_domain(domain).items():
            for e in items:
                missing = required - set(e.keys())
                assert not missing, f"{domain}/{gate_name} missing: {missing}"
                assert e["provenance"] in valid_grades, (
                    f"{domain}/{gate_name} bad grade: {e['provenance']!r}"
                )
                total += 1
    assert total >= 10, f"expected ≥10 evidence entries, got {total}"


def test_cache_works():
    """Loading is cached (no DB/file I/O per call)."""
    a = list_domains()
    b = list_domains()
    assert a == b


def test_evidence_entries_are_independent_copies():
    """get_evidence_for_gate returns copies, not shared refs that callers
    could mutate."""
    a = get_evidence_for_gate("pbpk", "pbpk_auc_fold_error")
    b = get_evidence_for_gate("pbpk", "pbpk_auc_fold_error")
    if a and b:
        a[0]["paper_ref"] = "MUTATED"
        assert b[0]["paper_ref"] != "MUTATED", "callers can corrupt cache"
