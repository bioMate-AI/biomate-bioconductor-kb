"""Unit tests for peptide_select.py — CPU, pure-logic, no GPU/AWS/training data.

Covers the A2 acceptance surface (docs/20260925_PEPTIDE_EXECUTION_PLAN.md):
  * Pareto correctness (dominance, direction handling per objective).
  * Missing-field degradation (verify's fail-safe ``None`` must not crash selection; the three
    ``missing`` policies; drop-when-nothing-usable; whole-column-unavailable).
  * Batch diversity (near-duplicates are not all returned; diversity_weight has effect).
  * Composition with peptide_verify (``from_verify`` adapts real PeptideProperties objects).

Run: ``python -m pytest test_peptide_select.py``
"""
import importlib.util
import sys
from pathlib import Path

import pytest

_HERE = Path(__file__).resolve().parent


def _load(name):
    spec = importlib.util.spec_from_file_location(name, _HERE / f"{name}.py")
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod  # dataclass introspection needs the module registered
    spec.loader.exec_module(mod)
    return mod


ps = _load("peptide_select")
Candidate = ps.Candidate
select_batch = ps.select_batch
compute_pareto_front = ps.compute_pareto_front
from_verify = ps.from_verify

import numpy as np  # noqa: E402


# ------------------------------------------------------------------ helpers
def _cand(cid, dG=None, perm=None, sa=None, safety=None, seq=None, smiles=None):
    return Candidate(
        identifier=cid,
        objectives={"affinity_dG": dG, "permeability": perm,
                    "synthetic_accessibility": sa, "safety": safety},
        seq=seq, smiles=smiles,
    )


# ================================================================== Pareto correctness
def test_pareto_front_pure_math_all_maximize():
    # already-oriented (higher=better) scores
    scores = np.array([
        [1.0, 0.0],   # A: best obj0
        [0.0, 1.0],   # B: best obj1
        [0.5, 0.5],   # C: middle, non-dominated
        [0.4, 0.4],   # D: dominated by C
        [0.9, 0.9],   # E: dominates C and D
    ])
    mask = compute_pareto_front(scores)
    # E dominates C,D; A and B are extreme non-dominated; E non-dominated
    assert mask.tolist() == [True, True, False, False, True]


def test_direction_handling_dG_and_sa_are_minimized():
    # Two candidates identical except affinity_dG. More-negative dG must be preferred (minimize).
    # Give the strong-binder a WORSE (lower) permeability so it can only win via the dG axis;
    # the weak-binder wins the permeability axis -> both should be Pareto-optimal, proving the
    # dG axis was correctly oriented (if dG were maximized, the -50 candidate would be dominated).
    strong = _cand("strong", dG=-50.0, perm=-6.5, sa=3.0, safety=0.8, seq="AAAA")
    weak = _cand("weak", dG=-10.0, perm=-4.0, sa=3.0, safety=0.8, seq="CCCC")
    res = select_batch([], _candidates=[strong, weak], n_select=2)
    assert set(res.pareto_front) == {"strong", "weak"}
    assert res.directions["affinity_dG"] == "minimize"
    assert res.directions["synthetic_accessibility"] == "minimize"
    assert res.directions["permeability"] == "maximize"
    assert res.directions["safety"] == "maximize"


def test_dominated_candidate_excluded_from_pareto():
    # 'best' beats 'meh' on every axis in the correct direction -> meh dominated.
    best = _cand("best", dG=-40.0, perm=-5.0, sa=2.0, safety=0.9, seq="AAAA")
    meh = _cand("meh", dG=-20.0, perm=-7.0, sa=6.0, safety=0.4, seq="CCCC")
    also = _cand("also", dG=-38.0, perm=-5.1, sa=2.1, safety=0.85, seq="DDDD")
    res = select_batch([], _candidates=[best, meh, also], n_select=3)
    assert "best" in res.pareto_front
    assert "meh" not in res.pareto_front  # strictly dominated


# ================================================================== missing-field degradation
def test_missing_dG_does_not_crash_and_candidate_survives():
    # A physics-pending candidate (dG=None) must still be selectable via its other axes.
    pending = _cand("pending", dG=None, perm=-4.5, sa=2.0, safety=0.95, seq="AAAA")
    scored = _cand("scored", dG=-30.0, perm=-6.0, sa=4.0, safety=0.5, seq="CCCC")
    res = select_batch([], _candidates=[pending, scored], n_select=2)
    assert res.n_dropped == 0
    # pending is excellent on perm/sa/safety -> should be Pareto-optimal despite missing dG
    assert "pending" in res.pareto_front
    assert res.hvi["pending"] >= 0.0  # scored, not crashed


def test_candidate_with_no_usable_objective_is_dropped_not_crashed():
    ghost = _cand("ghost")  # all None
    real = _cand("real", dG=-25.0, perm=-5.0, sa=3.0, safety=0.7, seq="AAAA")
    res = select_batch([], _candidates=[ghost, real], n_select=2)
    assert "ghost" in res.dropped
    assert res.n_dropped == 1
    assert res.selected == ["real"]


def test_whole_column_unavailable_is_dropped_from_objectives():
    # No candidate has permeability -> that objective is dropped, others still used.
    a = _cand("a", dG=-30.0, perm=None, sa=2.0, safety=0.8, seq="AAAA")
    b = _cand("b", dG=-20.0, perm=None, sa=4.0, safety=0.6, seq="CCCC")
    res = select_batch([], _candidates=[a, b], n_select=2)
    assert "permeability" not in res.objectives
    assert set(res.objectives) == {"affinity_dG", "synthetic_accessibility", "safety"}


def test_impute_worst_vs_mean_policies_both_run():
    pending = _cand("pending", dG=None, perm=-4.0, sa=2.0, safety=0.9, seq="AAAA")
    scored = _cand("scored", dG=-30.0, perm=-6.0, sa=5.0, safety=0.4, seq="CCCC")
    r_worst = select_batch([], _candidates=[pending, scored], missing="impute_worst_observed")
    r_mean = select_batch([], _candidates=[pending, scored], missing="impute_mean")
    assert r_worst.missing_policy == "impute_worst_observed"
    assert r_mean.missing_policy == "impute_mean"
    assert set(r_worst.selected) == set(r_mean.selected) == {"pending", "scored"}


def test_skip_objective_falls_back_when_it_removes_everything():
    # Every objective has at least one missing value -> skip_objective would kill all columns,
    # so it must fall back to worst-imputation rather than returning nothing.
    a = _cand("a", dG=-30.0, perm=None, sa=2.0, safety=None, seq="AAAA")
    b = _cand("b", dG=None, perm=-5.0, sa=None, safety=0.7, seq="CCCC")
    res = select_batch([], _candidates=[a, b], missing="skip_objective", n_select=2)
    assert res.n_pool == 2  # nobody dropped, selection still happened
    assert set(res.selected) == {"a", "b"}


def test_empty_pool_returns_empty_result_not_crash():
    res = select_batch([], _candidates=[], n_select=5)
    assert res.selected == []
    assert "empty pool" in res.notes


# ================================================================== diversity
def test_diversity_prefers_spread_over_near_duplicates():
    # Three near-identical high-scorers + one distinct decent-scorer. With diversity ON, the batch
    # of 2 should NOT be two of the near-duplicates.
    dup1 = _cand("dup1", dG=-40.0, perm=-5.0, sa=2.0, safety=0.9, seq="AAAAAAAA")
    dup2 = _cand("dup2", dG=-39.9, perm=-5.0, sa=2.0, safety=0.9, seq="AAAAAAAA")
    dup3 = _cand("dup3", dG=-39.8, perm=-5.0, sa=2.0, safety=0.9, seq="AAAAAAAA")
    distinct = _cand("distinct", dG=-35.0, perm=-5.2, sa=2.5, safety=0.85, seq="WYWYWYWY")
    res = select_batch([], _candidates=[dup1, dup2, dup3, distinct],
                       n_select=2, diversity_weight=0.6)
    assert "distinct" in res.selected  # the diverse pick got in
    assert res.diversity_score > 0.0


def test_diversity_metric_sequence_fallback_when_no_fp():
    # identifiers only, no seq/smiles -> if RDKit present but no mol, metric is sequence/none.
    a = Candidate("a", {"affinity_dG": -30.0, "permeability": -5.0,
                        "synthetic_accessibility": 3.0, "safety": 0.7})
    b = Candidate("b", {"affinity_dG": -20.0, "permeability": -6.0,
                        "synthetic_accessibility": 4.0, "safety": 0.6})
    res = select_batch([], _candidates=[a, b], n_select=2)
    assert res.diversity_metric in {"sequence_identity", "none"}
    assert set(res.selected) == {"a", "b"}


def test_batch_size_respected():
    cands = [_cand(f"c{i}", dG=-20.0 - i, perm=-5.0 - 0.1 * i, sa=3.0, safety=0.7,
                   seq="A" * (i + 3)) for i in range(8)]
    res = select_batch([], _candidates=cands, n_select=3)
    assert len(res.selected) == 3
    assert len(set(res.selected)) == 3  # no repeats


def test_n_select_larger_than_pool_returns_whole_pool():
    cands = [_cand(f"c{i}", dG=-20.0 - i, perm=-5.0, sa=3.0, safety=0.7, seq="A" * (i + 3))
             for i in range(3)]
    res = select_batch([], _candidates=cands, n_select=10)
    assert len(res.selected) == 3


# ================================================================== composition with peptide_verify
def test_from_verify_adapts_real_peptideproperties():
    pv_mod = _load("peptide_verify")
    PropertyValue = pv_mod.PropertyValue
    PeptideProperties = pv_mod.PeptideProperties
    MEASURED, PREDICTED, PROXY, UNAVAILABLE = (
        pv_mod.MEASURED, pv_mod.PREDICTED, pv_mod.PROXY, pv_mod.UNAVAILABLE)

    p1 = PeptideProperties(identifier="d1", sequence="ACDEF")
    p1.affinity_dG = PropertyValue(-34.2, MEASURED, None, "mmgbsa", "kcal/mol")
    p1.permeability = PropertyValue(-5.1, PREDICTED, 0.4, "perm", "log Papp")
    p1.synthetic_accessibility = PropertyValue(3.8, PROXY, None, "sa", "SA")
    p1.safety = PropertyValue(0.71, PROXY, 0.09, "stab", "P(stable)")

    p2 = PeptideProperties(identifier="d2", sequence="GGGGG")
    p2.affinity_dG = PropertyValue(None, UNAVAILABLE, detail="no physics JSON")  # missing dG
    p2.permeability = PropertyValue(-4.0, PREDICTED, 0.5, "perm", "log Papp")
    p2.synthetic_accessibility = PropertyValue(2.5, PROXY, None, "sa", "SA")
    p2.safety = PropertyValue(0.9, PROXY, 0.05, "stab", "P(stable)")

    cands = from_verify([p1, p2])
    assert cands[0].identifier == "d1" and cands[0].objectives["affinity_dG"] == -34.2
    assert cands[0].provenance["affinity_dG"] == MEASURED
    assert cands[1].objectives["affinity_dG"] is None  # degraded field carried through as None
    assert cands[1].objectives["permeability"] == -4.0

    # full A1 -> A2 path: select over the adapted pool, missing dG on d2 handled gracefully
    res = select_batch([p1, p2], n_select=2)
    assert res.n_dropped == 0
    assert set(res.selected) == {"d1", "d2"}


def test_select_batch_end_to_end_via_verify_batch_hook():
    # Uses verify_batch with mocked scorers -> real PeptideProperties -> select_batch. No re-score.
    pv_mod = _load("peptide_verify")
    PropertyValue = pv_mod.PropertyValue
    MEASURED, PREDICTED, PROXY = pv_mod.MEASURED, pv_mod.PREDICTED, pv_mod.PROXY

    def scorers_for(dG, perm):
        return {
            "affinity_dG": lambda ctx, _d=dG: PropertyValue(_d, MEASURED, None, "m", "kcal/mol"),
            "permeability": lambda ctx, _p=perm: PropertyValue(_p, PREDICTED, 0.3, "p", "logPapp"),
            "synthetic_accessibility": lambda ctx: PropertyValue(3.0, PROXY, None, "s", "SA"),
            "safety": lambda ctx: PropertyValue(0.7, PROXY, 0.1, "st", "P(stable)"),
        }

    props = [
        pv_mod.verify_peptide(seq="AAAA", identifier="a", _scorers=scorers_for(-40.0, -4.5)),
        pv_mod.verify_peptide(seq="CCCC", identifier="b", _scorers=scorers_for(-20.0, -6.5)),
        pv_mod.verify_peptide(seq="WYWY", identifier="c", _scorers=scorers_for(-30.0, -5.0)),
    ]
    res = select_batch(props, n_select=2)
    assert len(res.selected) == 2
    assert res.n_pool == 3 and res.n_dropped == 0
    # 'a' dominates on both physics axes present -> must be Pareto-optimal and picked
    assert "a" in res.pareto_front and "a" in res.selected


if __name__ == "__main__":
    sys.exit(pytest.main([__file__, "-v"]))
