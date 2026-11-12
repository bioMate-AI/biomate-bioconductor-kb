"""Data-fidelity guards for assay ingestion, ranking coverage and study-report ingestion.

Covers the defects recorded in internal project notes
(Cases 1 and 4, deliberate data errors).
"""
from __future__ import annotations

import csv

import pytest

from galaxy.ai.drug_discovery.assay_ingestion import AssayIngestionService
from galaxy.ai.drug_discovery.assay_schema import AssayCSVValidator
from galaxy.ai.drug_discovery.evidence_provenance import detect_glp_status, is_prediction_only
from galaxy.ai.drug_discovery.wetlab_report_ingester import (
    MEASURED, PREDICTED, WetLabReportIngester,
)

FIELDS = ["compound_id", "smiles", "assay_type", "value", "unit", "assay_date", "operator"]


def _row(**overrides):
    row = dict(compound_id="A", smiles="CCO", assay_type="IC50", value="10",
               unit="nM", assay_date="2026-10-01", operator="=")
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


# ── Endpoint physical validation ────────────────────────────────────────────

@pytest.mark.parametrize("overrides", [
    dict(assay_type="IC50", value="-10"),
    dict(assay_type="IC50", value="0"),
    dict(assay_type="EC50", value="-1", unit="uM"),
    dict(assay_type="Ki", value="-0.5"),
    dict(assay_type="Kd", value="-10"),
    dict(assay_type="hERG", value="0", unit="uM"),
    dict(assay_type="solubility", value="-3", unit="uM"),
    dict(assay_type="pIC50", value="25", unit=""),
    dict(assay_type="pIC50", value="0.2", unit=""),
    dict(assay_type="percent_inhibition", value="180", unit="%"),
    dict(assay_type="percent_inhibition", value="-40", unit="%"),
    dict(assay_type="Ames", value="0.5", unit="uM"),
    dict(assay_type="Ames", value="1", unit="nM"),   # would silently become 0.001
    dict(assay_type="selectivity_ratio", value="-2", unit="fold"),
    dict(assay_type="IC50", value="10", unit="%"),   # percent is not a concentration
], ids=lambda o: f"{o['assay_type']}={o['value']}{o.get('unit', 'nM')}")
def test_physically_impossible_values_rejected(write_csv, overrides):
    valid, errors = AssayCSVValidator().validate(write_csv([_row(**overrides)]))
    assert valid == []
    assert errors and errors[0].startswith("Row 2:")


@pytest.mark.parametrize("overrides, normalized", [
    (dict(assay_type="IC50", value="10", unit="nM"), (0.01, "uM")),
    (dict(assay_type="pIC50", value="7.5", unit=""), (7.5, "-log10(M)")),
    (dict(assay_type="percent_inhibition", value="-8", unit="%"), (-8.0, "%")),
    (dict(assay_type="percent_inhibition", value="112", unit="%"), (112.0, "%")),
    (dict(assay_type="Ames", value="1", unit="uM"), (1.0, "flag")),
    (dict(assay_type="permeability", value="0", unit="uM"), (0.0, "uM")),
])
def test_physically_valid_values_accepted(write_csv, overrides, normalized):
    valid, errors = AssayCSVValidator().validate(write_csv([_row(**overrides)]))
    assert errors == []
    assert valid[0]["value_uM"] == pytest.approx(normalized[0])
    assert valid[0]["unit_normalized"] == normalized[1]


def test_negative_ic50_not_persisted(svc, write_csv):
    result = svc.ingest("c", write_csv([_row(value="-10")]))
    assert result["ingested"] == 0
    assert "IC50 must be > 0" in result["errors"][0]
    assert svc.get_campaign_results("c") == []


# ── Structure identity ──────────────────────────────────────────────────────

def test_conflicting_structures_in_one_batch_rejected(svc, write_csv):
    result = svc.ingest("c", write_csv([_row(), _row(smiles="c1ccccc1", assay_type="hERG", unit="uM")]))
    assert result["ingested"] == 0
    assert len(result["errors"]) == 2
    assert all("conflicting structures" in e for e in result["errors"])


def test_conflict_against_previously_ingested_rows(svc, write_csv):
    assert svc.ingest("c", write_csv([_row()]))["ingested"] == 1
    later = svc.ingest("c", write_csv([
        _row(smiles="OCC", assay_type="hERG", value="30", unit="uM"),       # same ethanol, other spelling
        _row(smiles="c1ccccc1", assay_type="Kd", value="5"),               # benzene: conflict
        _row(compound_id="B", smiles="c1ccccc1", value="20"),              # other ID: fine
    ]))
    assert later["ingested"] == 2
    assert len(later["errors"]) == 1
    assert "already records it as CCO" in later["errors"][0]
    stored = {(r["compound_id"], r["assay_type"]) for r in svc.get_campaign_results("c")}
    assert ("A", "Kd") not in stored and ("A", "hERG") in stored


def test_identity_is_scoped_to_campaign(svc, write_csv):
    svc.ingest("c1", write_csv([_row()]))
    assert svc.ingest("c2", write_csv([_row(smiles="c1ccccc1")]))["errors"] == []


def test_unparseable_smiles_rejected(write_csv):
    valid, errors = AssayCSVValidator().validate(write_csv([_row(smiles="C1CC(")]))
    assert valid == [] and "could not be parsed" in errors[0]


# ── Ranking coverage ────────────────────────────────────────────────────────

def test_incomplete_candidate_not_ranked_as_lead(svc, write_csv):
    svc.ingest("c", write_csv([
        _row(compound_id=c, smiles=s, value=v)
        for c, s, v in (("A", "CCO", "1"), ("B", "CCN", "10"), ("C", "CCC", "100"))
    ]))
    svc.ingest("c", write_csv([
        _row(compound_id=c, smiles=s, assay_type="hERG", value=v, unit="uM")
        for c, s, v in (("A", "CCO", "1"), ("B", "CCN", "50"), ("C", "CCC", "25"))
    ]))
    result = svc.ingest("c", write_csv([_row(compound_id="D", smiles="CCCl", value="0.1")]))

    ranks = result["updated_ranks"]
    assert [r["compound_id"] for r in ranks][0] == "B"
    assert ranks[-1]["compound_id"] == "D"
    d = ranks[-1]
    assert d["coverage_status"] == "incomplete"
    assert d["missing_objectives"] == ["safety"] and d["measured_objectives"] == ["potency"]
    assert all(r["coverage_status"] == "complete" for r in ranks[:-1])
    assert len(result["warnings"]) == 1 and "Compound D" in result["warnings"][0]
    # Contract keys survive a reload and keep the combined_score name.
    reloaded = AssayIngestionService(svc.db_path).get_ranked_compounds("c")
    assert [r["compound_id"] for r in reloaded] == [r["compound_id"] for r in ranks]
    assert {"combined_score", "coverage_status", "missing_objectives"} <= set(reloaded[-1])
    assert isinstance(reloaded[-1]["combined_score"], float)


def test_single_objective_campaign_is_complete(svc, write_csv):
    result = svc.ingest("c", write_csv([_row(compound_id="A"), _row(compound_id="B", smiles="CCN", value="50")]))
    assert result["warnings"] == []
    assert [r["compound_id"] for r in result["updated_ranks"]] == ["A", "B"]


# ── Study-report provenance ─────────────────────────────────────────────────

RAT_REPORT = """Study ID: QA-RAT-001
Single-dose intravenous pharmacokinetics in rat.
Measured terminal half-life = 8 h.
Cmax = 250 ng/mL.
AUCinf = 1500 ng.h/mL.
hERG IC50 = 5000 nM.
NOAEL = 25 mg/kg/day in rat.
"""


def test_species_extracted_not_defaulted_to_human():
    r = WetLabReportIngester().ingest_text(RAT_REPORT, source_reference="T")
    assert r.t_half_h.species == "rat"
    assert r.noael_mg_kg_day.species == "rat" and r.noael_species == "rat"
    # In vitro hERG does not inherit the in vivo study species.
    assert r.herg_ic50_uM_measured.species == "unspecified"
    no_species = WetLabReportIngester().ingest_text("Terminal half-life = 3 h.")
    assert no_species.t_half_h.species == "unspecified"


def test_mixed_species_document_does_not_guess():
    r = WetLabReportIngester().ingest_text(
        "PK was studied in rats and dogs.\nTerminal half-life = 4 h.\nClearance of 12.5 mL/min/kg in dogs.")
    assert r.t_half_h.species == "unspecified"
    assert r.cl_mlminkg.species == "dog" and r.cl_mlminkg.value == 12.5
    assert r.provenance_warnings


def test_cmax_and_auc_extracted_with_units():
    r = WetLabReportIngester().ingest_text(RAT_REPORT)
    assert (r.cmax_ngml.value, r.cmax_ngml.unit) == (250.0, "ng/mL")
    assert (r.auc_inf_ngmlh.value, r.auc_inf_ngmlh.unit) == (1500.0, "ng·h/mL")
    micro = WetLabReportIngester().ingest_text("Cmax = 1.2 µg/mL\nAUC0-inf = 3.5 μg·h/mL")
    assert micro.cmax_ngml.value == pytest.approx(1200.0)
    assert micro.auc_inf_ngmlh.value == pytest.approx(3500.0)


def test_prediction_only_text_not_recorded_as_measured():
    r = WetLabReportIngester().ingest_text(
        "Computational prediction only: terminal half-life = 8 h. No measurements were collected.")
    assert r.t_half_h is None
    assert r.predicted_values["t_half_h"]["source"] == PREDICTED
    assert r.predicted_values["t_half_h"]["confidence"] == "LOW"
    assert "measured_species" not in r.to_pk_summary_override()
    assert "t_half_h" not in r.to_pk_summary_override()


def test_predicted_line_separated_from_measured_lines():
    r = WetLabReportIngester().ingest_text(
        "Study in rat.\nMeasured terminal half-life = 8 h.\nPredicted Cmax = 300 ng/mL (PBPK simulation).")
    assert r.t_half_h.source == MEASURED and r.t_half_h.confidence == "HIGH"
    assert r.cmax_ngml is None and r.predicted_values["cmax_ngml"]["value"] == 300.0


def test_glp_status_not_assumed():
    ing = WetLabReportIngester()
    assert ing.ingest_structured({"t_half_h": 8}).glp_certified is None
    assert ing.ingest_structured({"t_half_h": 8, "glp_certified": True}).glp_certified is True
    assert ing.ingest_structured({"t_half_h": 8, "glp": "no"}).glp_certified is False
    assert ing.ingest_text("Terminal half-life = 8 h.").glp_certified is None
    assert detect_glp_status("This study was not conducted under GLP.") is False
    assert detect_glp_status("Not a real compound or GLP study.") is False
    assert detect_glp_status("Conducted in compliance with 21 CFR Part 58.") is True
    assert detect_glp_status("The study was GLP-compliant.") is True


def test_structured_rejects_impossible_values():
    with pytest.raises(ValueError, match="t_half_h must be > 0"):
        WetLabReportIngester().ingest_structured({"t_half_h": -3})
    with pytest.raises(ValueError, match="fu_plasma"):
        WetLabReportIngester().ingest_structured({"fu_plasma": 1.5})


def test_to_dict_round_trip_keeps_provenance():
    ing = WetLabReportIngester()
    first = ing.ingest_text("Study in rat.\nMeasured terminal half-life = 8 h.\nPredicted Cmax = 300 ng/mL.\n"
                            "hERG IC50 = 5 uM.", source_reference="R")
    again = ing.ingest_structured(first.to_dict(), source_reference="R")
    assert again.t_half_h.species == "rat" and again.t_half_h.confidence == "HIGH"
    assert again.herg_ic50_uM_measured.value == 5.0
    assert again.cmax_ngml is None and "cmax_ngml" in again.predicted_values
    assert again.glp_certified is None


def test_pdf_extractor_ames_bool_maps_to_genotox_label():
    r = WetLabReportIngester().ingest_structured({"ames_result": True})
    assert r.ames_in_vitro == "positive" and r.genotox_battery_result == "positive"


def test_prediction_only_detector_ignores_ordinary_not_measured():
    assert is_prediction_only("Computational prediction only.")
    assert not is_prediction_only("Cmax was not measured in this cohort. Half-life = 4 h.")
