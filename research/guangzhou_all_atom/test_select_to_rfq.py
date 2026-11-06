"""Unit tests for G5 (select_to_rfq.py): selection JSON -> CRO synthesis RFQ CSV.

The contract under test: (1) the converter resolves ids -> sequences from the pool and
reproduces the ordered pick; (2) it accepts all three selection shapes; (3) it is SCORE-FREE
BY CONSTRUCTION — no internal design score (pAff, ΔG, HVI, iPTM, ...) can reach a CRO row.
"""
import csv
import importlib.util
import json
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


m = _load("select_to_rfq")


def test_selftest_passes():
    assert m._selftest() == 0


def test_selection_result_shape_resolves_from_pool():
    sel = {"selected": ["c2", "c1"], "pareto_front": ["c1", "c2", "c3"]}
    pool = m.load_pool_from_rows([
        {"identifier": "c1", "sequence": "ACDEF"},
        {"identifier": "c2", "sequence": "GHIKL"},
    ])
    rows, warn = m.build_rfq(m.extract_selection(sel, pool_target=None, rank="qnehvi"),
                             pool, "PDL1-A")
    assert [r["Item"] for r in rows] == ["PDL1-A-01", "PDL1-A-02"]
    assert rows[0]["Sequence_N_to_C"] == "GHIKL"  # order follows `selected`
    assert rows[0]["Length"] == "5"
    assert not warn


def test_mo_pool_shape_inline_seqs():
    mo = {"pools": {"PD-L1": {"qnehvi_topk": [{"seq": "MNPQR", "pAff": 7.1},
                                              {"seq": "STVWY", "pAff": 6.9}]}}}
    rows, _ = m.build_rfq(m.extract_selection(mo, pool_target="PD-L1", rank="qnehvi"),
                          {}, "PDL1-A")
    assert [r["Sequence_N_to_C"] for r in rows] == ["MNPQR", "STVWY"]


def test_scores_never_reach_cro_row():
    # a selection row carrying a score field must not propagate it to the CRO CSV
    mo = {"pools": {"T": {"composite_topk": [{"seq": "AAAAA", "pAff": 9.9, "logPapp": -5.1,
                                              "iptm": 0.9, "RUSH": "RUSH"}]}}}
    rows, _ = m.build_rfq(m.extract_selection(mo, pool_target="T", rank="composite"),
                          {}, "X")
    assert set(rows[0]) == set(m.CRO_COLUMNS)
    for forbidden in ("pAff", "logPapp", "iptm", "RUSH", "score"):
        assert forbidden not in rows[0]


def test_missing_sequence_drops_with_warning_not_crash():
    rows, warn = m.build_rfq(m.extract_selection(["ghost"], pool_target=None, rank="qnehvi"),
                             {}, "AVB6-B")
    assert rows == []
    assert len(warn) == 1 and "ghost" in warn[0]


def test_pool_cyclization_string_preserved_bool_ignored():
    pool = m.load_pool_from_rows([
        {"identifier": "a", "sequence": "AAAAA", "cyclization": "Disulfide (C1-C5)"},
        {"identifier": "b", "sequence": "CCCCC", "cyclic": True},  # bare bool -> default
    ])
    rows, _ = m.build_rfq([{"id": "a"}, {"id": "b"}], pool, "P")
    assert rows[0]["Cyclization"] == "Disulfide (C1-C5)"
    assert rows[1]["Cyclization"] == m.DEFAULTS["Cyclization"]


def test_csv_round_trip(tmp_path):
    pool = m.load_pool_from_rows([{"identifier": "c1", "sequence": "ACDEF"}])
    rows, _ = m.build_rfq([{"id": "c1"}], pool, "PDL1-A")
    out = tmp_path / "order.csv"
    m.write_csv(rows, out)
    back = list(csv.DictReader(open(out)))
    assert back[0]["Item"] == "PDL1-A-01"
    assert list(back[0].keys()) == m.CRO_COLUMNS
