"""Unit tests for G4: precomputed permeability predictions (predict_permeability_pool.py) +
peptide_verify perm_pred_csv lookup.

Contract: when a predictions CSV is supplied, permeability is LOOKED UP (id -> smiles -> seq)
instead of retraining the ensemble per candidate; the lookup returns the exact precomputed value
with PREDICTED provenance; a missing row falls back gracefully (no crash). The lookup path needs
neither rdkit nor the CycPeptMPDB CSV (it returns before any training), so these tests are cheap.
"""
import csv
import importlib.util
import sys
from pathlib import Path

import pytest

HERE = Path(__file__).resolve().parent


def _load(name):
    spec = importlib.util.spec_from_file_location(name, HERE / f"{name}.py")
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


pv_mod = _load("peptide_verify")
pool_mod = _load("predict_permeability_pool")


def _write_pred_csv(tmp_path, rows):
    p = tmp_path / "perm_pred.csv"
    with open(p, "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=["identifier", "sequence", "smiles",
                                           "logPapp_mean", "logPapp_std"])
        w.writeheader()
        w.writerows(rows)
    return p


def test_load_predictions_keys_by_id_smiles_seq(tmp_path):
    p = _write_pred_csv(tmp_path, [
        {"identifier": "c1", "sequence": "ACDEF", "smiles": "CC",
         "logPapp_mean": "-5.1", "logPapp_std": "0.3"},
    ])
    tbl = pv_mod._load_perm_predictions(p)
    assert tbl["id:c1"] == (-5.1, 0.3)
    assert tbl["smi:CC"] == (-5.1, 0.3)
    assert tbl["seq:ACDEF"] == (-5.1, 0.3)


def test_score_permeability_lookup_by_identifier(tmp_path):
    p = _write_pred_csv(tmp_path, [
        {"identifier": "c1", "sequence": "ACDEF", "smiles": "CC",
         "logPapp_mean": "-6.2", "logPapp_std": "0.4"},
    ])
    out = pv_mod._score_permeability("ACDEF", "CC", None, "c1", p)
    assert out.value == -6.2
    assert out.uncertainty == 0.4
    assert out.provenance == pv_mod.PREDICTED
    assert "precomputed pool CSV" in out.detail


def test_lookup_falls_back_when_no_row_and_no_training_csv(tmp_path):
    # an empty predictions CSV + a nonexistent training CSV -> UNAVAILABLE, never a crash
    p = _write_pred_csv(tmp_path, [])
    out = pv_mod._score_permeability("ZZZZZ", None, tmp_path / "nope.csv", "ghost", p)
    assert out.provenance != pv_mod.PREDICTED  # degraded, not a fake value
    assert out.value is None


def test_nan_std_becomes_none(tmp_path):
    p = _write_pred_csv(tmp_path, [
        {"identifier": "c2", "sequence": "GG", "smiles": "",
         "logPapp_mean": "-4.0", "logPapp_std": ""},
    ])
    out = pv_mod._score_permeability("GG", None, None, "c2", p)
    assert out.value == -4.0
    assert out.uncertainty is None


def test_verify_peptide_threads_perm_pred_csv(tmp_path):
    p = _write_pred_csv(tmp_path, [
        {"identifier": "d1", "sequence": "MKLV", "smiles": "",
         "logPapp_mean": "-5.5", "logPapp_std": "0.2"},
    ])
    props = pv_mod.verify_peptide(seq="MKLV", identifier="d1",
                                  perm_pred_csv=p, only=["permeability"])
    assert props.permeability.value == -5.5
    assert props.permeability.provenance == pv_mod.PREDICTED


def test_pool_record_normalisers():
    assert pool_mod._cid({"design_id": "x9"}) == "x9"
    assert pool_mod._seq({"Sequence_N_to_C": "ACD"}) == "ACD"
    assert pool_mod._smiles({"SMILES": "CCO"}) == "CCO"
    assert pool_mod._cid({}) == ""


def test_read_pool_json_and_jsonl(tmp_path):
    j = tmp_path / "pool.json"
    j.write_text('[{"identifier":"a","sequence":"AA"}]')
    assert pool_mod._read_pool(j) == [{"identifier": "a", "sequence": "AA"}]
    jl = tmp_path / "pool.jsonl"
    jl.write_text('{"identifier":"a","seq":"AA"}\n{"identifier":"b","seq":"BB"}\n')
    assert len(pool_mod._read_pool(jl)) == 2
