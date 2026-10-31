"""Censored assay values and salt/parent compound identity.

Contract: docs/20261030_SYSUCC_HANDOFF.md open item 3.
"""
from __future__ import annotations

import csv

import pytest

pytest.importorskip("rdkit")

from galaxy.ai.drug_discovery.assay_ingestion import AssayIngestionService
from galaxy.ai.drug_discovery.assay_schema import (
    FLAG_MULTI_COMPONENT, FLAG_SALT_STRIPPED, AssayCSVValidator, structure_identity,
)
from galaxy.ai.drug_discovery.auto_retrain import build_training_rows

FIELDS = ["compound_id", "smiles", "assay_type", "value", "unit", "assay_date", "operator"]


def _row(**overrides):
    row = dict(compound_id="A", smiles="CCO", assay_type="IC50", value="10",
               unit="uM", assay_date="2026-10-01", operator="=")
    row.update(overrides)
    return row


@pytest.fixture
def write_csv(tmp_path):
    counter = iter(range(10_000))

    def _write(rows):
        path = tmp_path / f"batch{next(counter)}.csv"
        with path.open("w", newline="") as out:
            writer = csv.DictWriter(out, fieldnames=FIELDS)
            writer.writeheader()
            writer.writerows(rows)
        return str(path)
    return _write


@pytest.fixture
def svc(tmp_path):
    return AssayIngestionService(str(tmp_path / "assays.db"))


# ── Censored values ─────────────────────────────────────────────────────────

def test_censored_row_keeps_operator_and_is_flagged(write_csv):
    valid, errors = AssayCSVValidator().validate(write_csv([_row(operator=">")]))
    assert errors == []
    assert valid[0]["operator"] == ">" and valid[0]["censored"] is True
    exact, _ = AssayCSVValidator().validate(write_csv([_row(operator="=")]))
    assert exact[0]["censored"] is False


def test_censoring_operator_on_binary_flag_rejected(write_csv):
    valid, errors = AssayCSVValidator().validate(write_csv([_row(assay_type="Ames", value="1", unit="flag",
                                                                 operator="<")]))
    assert valid == [] and "not meaningful" in errors[0]


def test_greater_than_ic50_is_not_ranked_as_its_bound(svc, write_csv):
    """IC50 '>10 uM' must not tie with an exact 10 uM, let alone beat 12 uM."""
    result = svc.ingest("c", write_csv([
        _row(compound_id="EXACT10", smiles="CCO", value="10"),
        _row(compound_id="GT10", smiles="CCN", value="10", operator=">"),
        _row(compound_id="EXACT12", smiles="CCC", value="12"),
        _row(compound_id="EXACT1", smiles="CCCl", value="1"),
    ]))
    ranks = {r["compound_id"]: r for r in result["updated_ranks"]}
    order = [r["compound_id"] for r in result["updated_ranks"]]
    assert order.index("GT10") > order.index("EXACT10")
    assert order.index("GT10") > order.index("EXACT12")
    gt = ranks["GT10"]
    assert gt["objectives"]["potency"]["censored"] is True
    assert gt["censored_objectives"] == ["potency"]
    assert gt["combined_score"] == 0.0                       # conservative: no better than the worst
    assert gt["combined_score_upper"] == pytest.approx(ranks["EXACT10"]["combined_score"])  # at best = bound
    assert ranks["EXACT10"]["objectives"]["potency"]["censored"] is False
    assert any("GT10" in w and "censored" in w for w in result["warnings"])


def test_favourable_bound_scores_at_least_the_bound(svc, write_csv):
    result = svc.ingest("c", write_csv([
        _row(compound_id="LT", smiles="CCO", value="0.001", operator="<"),
        _row(compound_id="E1", smiles="CCN", value="0.01"),
        _row(compound_id="E2", smiles="CCC", value="1"),
    ]))
    ranks = {r["compound_id"]: r for r in result["updated_ranks"]}
    # Bound lies below every exact IC50 → clamped to the best normalised score.
    assert ranks["LT"]["combined_score"] == pytest.approx(1.0)
    assert ranks["LT"]["censored_objectives"] == ["potency"]


def test_bound_does_not_stretch_scale_of_exact_values(svc, write_csv):
    exact = svc.ingest("a", write_csv([_row(compound_id="X", value="1"),
                                       _row(compound_id="Y", smiles="CCN", value="2")]))
    with_bound = svc.ingest("b", write_csv([_row(compound_id="X", value="1"),
                                            _row(compound_id="Y", smiles="CCN", value="2"),
                                            _row(compound_id="Z", smiles="CCC", value="1000", operator=">")]))
    a = {r["compound_id"]: r["combined_score"] for r in exact["updated_ranks"]}
    b = {r["compound_id"]: r["combined_score"] for r in with_bound["updated_ranks"]}
    assert a["X"] == b["X"] and a["Y"] == b["Y"]


def test_herg_less_than_bound_is_penalised_conservatively(svc, write_csv):
    result = svc.ingest("c", write_csv([
        _row(compound_id="A", smiles="CCO", assay_type="hERG", value="30", operator="<"),
        _row(compound_id="B", smiles="CCN", assay_type="hERG", value="30"),
    ]))
    ranks = {r["compound_id"]: r for r in result["updated_ranks"]}
    assert ranks["A"]["combined_score"] < ranks["B"]["combined_score"]
    assert [r["compound_id"] for r in result["updated_ranks"]] == ["B", "A"]


def test_censored_labels_excluded_from_training(svc, write_csv):
    svc.ingest("c", write_csv([
        _row(compound_id="A", smiles="CCO", value="1"),
        _row(compound_id="B", smiles="CCN", value="5"),
        _row(compound_id="C", smiles="CCC", value="10", operator=">"),
    ]))
    rows = build_training_rows(svc.get_ranked_compounds("c"))
    assert rows.compound_ids == ["A", "B"]
    report = rows.report(3)
    assert report["skipped"] == [{"compound_id": "C", "reason": "censored_value",
                                  "censored_objectives": ["potency"]}]


def test_censoring_survives_reload(svc, write_csv):
    svc.ingest("c", write_csv([_row(compound_id="A", value="1"),
                               _row(compound_id="B", smiles="CCN", value="10", operator=">")]))
    reloaded = AssayIngestionService(svc.db_path).get_ranked_compounds("c")
    b = next(r for r in reloaded if r["compound_id"] == "B")
    assert b["objectives"]["potency"]["censored"] is True
    assert b["combined_score_upper"] >= b["combined_score"]
    assert {r["compound_id"]: r["censored"] for r in svc.get_campaign_results("c")} == {"A": False, "B": True}


# ── Salt forms / parent structure ───────────────────────────────────────────

@pytest.mark.parametrize("smiles, parent, salt_stripped", [
    ("CCN.OC(=O)C(=O)O", "CCN", True),                     # oxalate stripped although larger
    ("CC[NH3+].[O-]C(=O)C(=O)O", "CCN", True),             # charged ion pair → neutral parent
    ("CCN.Cl", "CCN", True),                                # hydrochloride
    ("CCN.CCN.OS(=O)(=O)O", "CCN", True),                   # 2:1 sulfate, repeated parent
    ("Cc1ccc(S(=O)(=O)O)cc1.CCN", "CCN", True),             # tosylate
    ("OC(=O)CC(O)(CC(=O)O)C(=O)O.CCN", "CCN", True),        # citrate (extra list)
    ("CC(=O)O[Na]", "CC(=O)O", True),                       # covalent sodium salt → acetic acid
    ("CCN", "CCN", False),
])
def test_parent_structure(smiles, parent, salt_stripped):
    ident, err = structure_identity(smiles)
    assert err is None and ident.parent == parent
    assert (FLAG_SALT_STRIPPED in ident.flags) == salt_stripped
    assert not ident.is_multi_component


@pytest.mark.parametrize("smiles", ["CCO.CCCO", "CCO.c1ccccc1", "c1ccccc1O.c1ccccc1N"])
def test_two_organic_fragments_are_flagged_not_collapsed(smiles):
    ident, _ = structure_identity(smiles)
    assert ident.is_multi_component and FLAG_MULTI_COMPONENT in ident.flags
    assert "." in ident.parent


def test_salt_and_free_base_under_one_id_is_not_a_conflict(svc, write_csv):
    result = svc.ingest("c", write_csv([
        _row(compound_id="A", smiles="CCN.Cl", value="1"),
        _row(compound_id="A", smiles="CCN", assay_type="hERG", value="30"),
    ]))
    assert result["errors"] == [] and result["ingested"] == 2
    assert any("share the parent structure CCN" in n for n in result["notes"])
    stored = svc.get_campaign_results("c")
    assert {r["smiles"] for r in stored} == {"CCN.Cl", "CCN"}           # as submitted
    assert {r["parent_smiles"] for r in stored} == {"CCN"}
    ranked = svc.get_ranked_compounds("c")
    assert ranked[0]["parent_smiles"] == "CCN"


def test_salt_against_previously_stored_free_base(svc, write_csv):
    svc.ingest("c", write_csv([_row(compound_id="A", smiles="CCN")]))
    later = svc.ingest("c", write_csv([_row(compound_id="A", smiles="CCN.OC(=O)C(=O)O", assay_type="Kd")]))
    assert later["errors"] == [] and later["ingested"] == 1
    assert any("share the parent" in n for n in later["notes"])


def test_different_parents_under_one_id_conflict(svc, write_csv):
    svc.ingest("c", write_csv([_row(compound_id="A", smiles="CCN.Cl")]))
    later = svc.ingest("c", write_csv([_row(compound_id="A", smiles="CCO.Cl", assay_type="Kd")]))
    assert later["ingested"] == 0 and "already records it as CCN" in later["errors"][0]


def test_mixture_is_not_the_same_compound_as_one_component(svc, write_csv):
    result = svc.ingest("c", write_csv([
        _row(compound_id="M", smiles="CCO.CCCO", value="1"),
        _row(compound_id="M", smiles="CCO", assay_type="hERG", value="30"),
    ]))
    assert result["ingested"] == 0 and all("conflicting structures" in e for e in result["errors"])


def test_mixture_flagged_and_excluded_from_training(svc, write_csv):
    result = svc.ingest("c", write_csv([
        _row(compound_id="M", smiles="CCO.CCCO", value="1"),
        _row(compound_id="A", smiles="CCN", value="2"),
        _row(compound_id="B", smiles="CCC", value="5"),
    ]))
    assert any("multi-component" in n and "'M'" in n for n in result["notes"])
    rows = build_training_rows(svc.get_ranked_compounds("c"))
    assert "M" not in rows.compound_ids
    assert {"compound_id": "M", "reason": "multi_component_structure",
            "parent_smiles": "CCCO.CCO"} in rows.skipped


def test_training_uses_parent_structure_for_salts(svc, write_csv):
    svc.ingest("c", write_csv([_row(compound_id="A", smiles="CCN.Cl", value="1"),
                               _row(compound_id="B", smiles="CCCN.OC(=O)C(=O)O", value="5")]))
    rows = build_training_rows(svc.get_ranked_compounds("c"))
    assert dict(zip(rows.compound_ids, rows.smiles)) == {"A": "CCN", "B": "CCCN"}


# ── Shared row-level path ───────────────────────────────────────────────────

def test_ingest_rows_accepts_numeric_values_and_upserts_by_source_record(svc):
    base = dict(compound_id="REG-1", smiles="CCN", assay_type="IC50", value=12.5, unit="nM",
                assay_date="2026-10-01", operator="=", source_system="benchling",
                source_record_id="res_1", provenance={"benchling_result_id": "res_1"})
    first = svc.ingest_rows("c", [base])
    assert first["ingested"] == 1 and first["errors"] == []
    again = svc.ingest_rows("c", [base])
    assert (again["ingested"], again["updated"], again["unchanged"]) == (0, 0, 1)
    edited = svc.ingest_rows("c", [{**base, "value": 20.0}])
    assert (edited["ingested"], edited["updated"]) == (0, 1)
    stored = svc.get_campaign_results("c")
    assert len(stored) == 1 and stored[0]["value_uM"] == pytest.approx(0.02)
    retracted = svc.retract_records("c", "benchling", ["res_1"])
    assert retracted["retracted"] == 1 and svc.get_campaign_results("c") == []
    assert svc.get_ranked_compounds("c") == []
