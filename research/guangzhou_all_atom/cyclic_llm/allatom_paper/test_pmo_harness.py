"""Unit tests for pmo_harness.py. Run on EC2 spot / Spark (owner rule: no compute on the laptop): `python3.11 -m pytest -q`."""
import math
import os
import random
import sys

import numpy as np
import pytest

sys.path.insert(0, os.path.dirname(__file__))
import pmo_harness as H  # noqa: E402

IDENT = lambda s: s if isinstance(s, str) and s else None  # identity canon for string-world toy objectives


def table_verifier(table, name="tbl", role="train", trained_on=frozenset()):
    return H.Verifier(name=name, fn=lambda s: table[s], role=role, trained_on=frozenset(trained_on))


def test_budget_enforced():
    counter = {"i": 0}

    def sampler(rng):
        counter["i"] += 1
        return "C" * counter["i"]

    v = H.Verifier("len", lambda s: len(s) / 100.0)
    r = H.run_one(H.random_search(sampler), v, budget=50, seed=0, canon=IDENT)
    assert r["calls"] == 50 and len(r["curve"]) == 50
    assert r["auc_topk"] > 0


@pytest.mark.skipif(not H.HAVE_RDKIT, reason="needs RDKit")
def test_duplicates_and_invalid_not_charged():
    v = H.Verifier("n", lambda s: float(len(s)))
    o = H.BudgetedOracle(v, budget=10)
    first = o("CCO")                      # proposal 1: charged
    second = o("OCC")                     # proposal 2: same canonical SMILES -> cache hit, not charged
    third = o("CCO")                      # proposal 3: cache hit again
    assert first is not None and first == second == third
    assert o("this is not smiles") is None   # proposal 4: invalid, not charged
    assert o.calls == 1 and o.n_dup == 2 and o.n_invalid == 1 and o.n_proposals == 4


def test_constraint_failures_are_free():
    v = H.Verifier("n", lambda s: 1.0)
    o = H.BudgetedOracle(v, budget=5, canon=IDENT, constraint=lambda s: "N" not in s)
    assert o("CCN") is None and o("CCC") == 1.0
    assert o.calls == 1 and o.n_constraint_fail == 1


def test_proposal_cap_stops_infinite_loop():
    v = H.Verifier("n", lambda s: 1.0)
    r = H.run_one(H.random_search(lambda rng: "same"), v, budget=100, seed=0, canon=IDENT, max_proposals_factor=3)
    assert r["calls"] == 1 and r["n_proposals"] <= 301 and r["n_dup"] >= 1


def test_auc_hand_computed():
    tbl = {"a": 1.0, "b": 3.0, "c": 2.0, "d": 5.0}
    v = table_verifier(tbl)
    o = H.BudgetedOracle(v, budget=4, canon=IDENT)
    for s in "abcd":
        o(s)
    curve = o.topk_curve(k=2)
    assert np.allclose(curve, [1.0, 2.0, 2.5, 4.0])
    assert math.isclose(H.auc_topk(curve), 2.375)


def test_padding_when_run_stops_early():
    tbl = {"a": 1.0, "b": 3.0, "c": 2.0, "d": 5.0}
    o = H.BudgetedOracle(table_verifier(tbl), budget=6, canon=IDENT)
    for s in "abcd":
        o(s)
    curve = o.topk_curve(k=2)
    assert len(curve) == 6 and np.allclose(curve, [1, 2, 2.5, 4, 4, 4])
    assert math.isclose(H.auc_topk(curve), (1 + 2 + 2.5 + 4 + 4 + 4) / 6)


def test_no_calls_gives_zero_curve():
    o = H.BudgetedOracle(table_verifier({"a": 1.0}), budget=3, canon=IDENT)
    assert np.allclose(o.topk_curve(5), [0, 0, 0])


def test_topk_with_fewer_than_k_items_uses_available():
    o = H.BudgetedOracle(table_verifier({"a": 2.0, "b": 4.0}), budget=2, canon=IDENT)
    o("a"); o("b")
    assert np.allclose(o.topk_curve(k=10), [2.0, 3.0])


def test_heldout_cannot_be_an_oracle():
    h = H.Verifier("h", lambda s: 0.0, role="heldout")
    with pytest.raises(H.HeldOutVerifierError):
        H.BudgetedOracle(h, budget=5)


def test_independence_check():
    t = H.Verifier("A", lambda s: 0.0, role="train", trained_on=frozenset({"lab1", "lab2"}))
    h_ok = H.Verifier("B", lambda s: 0.0, role="heldout", trained_on=frozenset({"lab3"}))
    h_same_name = H.Verifier("A", lambda s: 0.0, role="heldout")
    h_overlap = H.Verifier("C", lambda s: 0.0, role="heldout", trained_on=frozenset({"lab2"}))
    assert H.check_independent([t], [h_ok])
    for bad in (h_same_name, h_overlap):
        with pytest.raises(H.HeldOutVerifierError):
            H.check_independent([t], [bad])


def test_heldout_applied_only_to_final_topk():
    calls = []
    t = H.Verifier("T", lambda s: float(s.count("A")), role="train", trained_on=frozenset({"x"}))
    h = H.Verifier("H", lambda s: calls.append(s) or 1.0, role="heldout", trained_on=frozenset({"y"}))
    r = H.run_one(H.random_search(lambda rng: "".join(rng.choice("AB") for _ in range(12))), t, budget=40, seed=1,
                  canon=IDENT, heldout=[h], k=5)
    assert len(calls) <= 5 and r["heldout"]["H"] == 1.0


ALPHA = "ABCD"


def _sample(rng, n=30):
    return "".join(rng.choice(ALPHA) for _ in range(n))


def _a_fraction(s):
    return s.count("A") / len(s)


def hill_climb(oracle, rng):
    cur = _sample(rng)
    best = oracle(cur)
    while True:
        i = rng.randrange(len(cur))
        cand = cur[:i] + rng.choice(ALPHA) + cur[i + 1:]
        sc = oracle(cand)
        if sc is not None and (best is None or sc >= best):
            cur, best = cand, sc


def test_run_one_is_deterministic():
    v = H.Verifier("a", _a_fraction)
    a = H.run_one(H.random_search(_sample), v, 60, seed=5, canon=IDENT)
    b = H.run_one(H.random_search(_sample), v, 60, seed=5, canon=IDENT)
    c = H.run_one(H.random_search(_sample), v, 60, seed=6, canon=IDENT)
    assert np.array_equal(a["curve"], b["curve"]) and not np.array_equal(a["curve"], c["curve"])


def _auc_list(opt, verifier, seeds, budget=200):
    return [H.run_one(opt, verifier, budget, s, canon=IDENT)["auc_topk"] for s in seeds]


def test_planted_improvement_is_detected():
    v = H.Verifier("a", _a_fraction)
    seeds = range(20)
    hc = _auc_list(hill_climb, v, seeds)
    rs = _auc_list(H.random_search(_sample), v, seeds)
    c = H.paired_contrast(hc, rs)
    assert c["mean"] > 0.1 and c["ci_wide"][0] > 0


def test_identical_optimiser_under_same_seeds_contrast_is_exactly_zero():
    v = H.Verifier("a", _a_fraction)
    x = _auc_list(hill_climb, v, range(10))
    c = H.paired_contrast(x, x)
    assert c["mean"] == 0 and c["ci_boot_mean"] == [0.0, 0.0]


def test_noise_reward_gives_no_systematic_gain():
    v = H.hash_noise_verifier()
    seeds = range(40)
    hc = _auc_list(hill_climb, v, seeds)
    rs = _auc_list(H.random_search(_sample), v, seeds)
    c = H.paired_contrast(hc, rs)
    se = c["sd"] / math.sqrt(c["n"])
    assert abs(c["mean"]) < 4 * se + 0.02       # no learnable signal: difference is selection noise only


def test_copy_seed_control_plateaus():
    v = H.Verifier("a", _a_fraction)
    seeds = ["AAAB", "ABBB", "BBBB", "AAAA", "ABAB"]
    r = H.run_one(H.copy_seed(seeds), v, budget=30, seed=0, canon=IDENT, k=2)
    assert r["calls"] == 5
    assert np.allclose(r["curve"][4:], r["curve"][4])


def test_mde_formula():
    assert math.isclose(H.mde_paired(1.0, 16), (1.959964 + 0.841621) / 4, rel_tol=1e-4)


def test_cluster_contrast_and_gate():
    per = {"permeability": [0.05, 0.06, 0.04, 0.05], "binding": [0.04, 0.05, 0.05, 0.04], "stability": [-0.01, 0.0, 0.01, 0.0]}
    cc = H.cluster_paired_contrast(per)
    assert cc["n_clusters"] == 3 and cc["per_cluster"]["permeability"] > 0.04
    contrasts = {k: H.paired_contrast(np.array(v) + 0.0, np.zeros(len(v))) for k, v in per.items()}
    g = H.gate_primary(contrasts, margin=0.03, min_pass=2)
    assert g["verdict"] == "PASS" and set(g["passed_families"]) == {"permeability", "binding"}
    g2 = H.gate_primary(contrasts, margin=0.03, min_pass=3)
    assert g2["verdict"] == "FAIL"


def test_gate_requires_margin_and_positive_lower_bound():
    c_small = H.paired_contrast([0.02] * 8, [0.0] * 8)     # below margin
    c_noisy = H.paired_contrast([0.2, -0.1, 0.25, -0.1, 0.2, -0.1, 0.2, -0.1], [0.0] * 8)  # mean ok, lower bound <= 0
    g = H.gate_primary({"a": c_small, "b": c_noisy}, margin=0.03, min_pass=1)
    assert g["verdict"] == "FAIL"


# ---------------------------------------------------------------- amendment A1: three-way split + Goodhart-gap monitor
def _v(name, role, srcs=()):
    return H.Verifier(name=name, fn=lambda s: 0.5, role=role, trained_on=frozenset(srcs))


def test_three_way_ok_and_violations():
    tr, st, ho = [_v("t", "train", {"A"})], [_v("s", "stop", {"S"})], [_v("h", "heldout", {"B"})]
    assert H.check_three_way(tr, st, ho)
    import pytest
    with pytest.raises(H.HeldOutVerifierError):
        H.check_three_way(tr, [_v("s2", "stop", {"A"})], ho)            # stop shares a source with train
    with pytest.raises(H.HeldOutVerifierError):
        H.check_three_way(tr, st, [_v("h2", "heldout", {"S"})])         # held-out shares a source with stop
    with pytest.raises(H.HeldOutVerifierError):
        H.check_three_way(tr, [_v("t", "stop", {"S"})], ho)             # same name as a train verifier
    with pytest.raises(H.HeldOutVerifierError):
        H.check_three_way(tr, [_v("s3", "train", {"S"})], ho)           # wrong role


def test_stop_role_is_not_an_oracle():
    import pytest
    with pytest.raises(H.HeldOutVerifierError):
        H.BudgetedOracle(_v("s", "stop", {"S"}), 10)


def test_stop_monitor_fires_only_on_divergence():
    m = H.StopMonitor(patience=2, min_gain=0.005)
    for t, s in [(0.4, 0.4), (0.5, 0.5), (0.6, 0.6)]:                    # both improve: no stop
        assert not m.update([t], [s])
    m2 = H.StopMonitor(patience=2, min_gain=0.005)
    fired = [m2.update([t], [s]) for t, s in [(0.4, 0.4), (0.5, 0.5), (0.6, 0.49), (0.7, 0.48), (0.8, 0.47)]]
    assert fired == [False, False, False, True, True] and m2.stopped_at == 4
    assert m2.gap_curve[-1] > m2.gap_curve[0]


def test_stop_monitor_does_not_fire_when_train_stalls_too():
    m = H.StopMonitor(patience=2, min_gain=0.005)
    for t, s in [(0.4, 0.4), (0.5, 0.5), (0.5, 0.5), (0.5, 0.5), (0.5, 0.5)]:  # plateau, no divergence
        assert not m.update([t], [s])


def test_gate_primary_requires_explicit_margin_and_accepts_per_family_margins():
    c = H.paired_contrast([0.5] * 8, [0.0] * 8)
    import pytest
    with pytest.raises(ValueError):
        H.gate_primary({"a": c, "b": c})                                   # no default margin any more (A4)
    g = H.gate_primary({"a": c, "b": c}, margin={"a": 0.4, "b": 0.6}, min_pass=1)
    assert g["passed_families"] == ["a"]                                  # b's own margin 0.6 is not met


def test_wall_clock_cap_stops_a_run_and_pads_the_curve():
    counter = {"i": 0}

    def sampler(rng):
        counter["i"] += 1
        return "C" * counter["i"]

    v = H.Verifier("len", lambda s: len(s) / 100.0)
    r = H.run_one(H.random_search(sampler), v, budget=50, seed=0, canon=IDENT, max_seconds=0.0)
    assert r["calls"] == 0 and len(r["curve"]) == 50                       # stopped at once, curve padded to the budget length


def test_stop_reason_is_recorded_for_budget_wallclock_and_stall():
    v = H.Verifier("len", lambda s: len(s) / 100.0)
    c = {"i": 0}

    def sampler(rng):
        c["i"] += 1
        return "C" * c["i"]

    r1 = H.run_one(H.random_search(sampler), v, budget=20, seed=0, canon=IDENT)
    assert r1["stop_reason"] == "budget_spent" and r1["budget_fraction_used"] == 1.0
    c["i"] = 0
    r2 = H.run_one(H.random_search(sampler), v, budget=20, seed=0, canon=IDENT, max_seconds=0.0)
    assert r2["stop_reason"] == "wallclock" and r2["budget_fraction_used"] == 0.0

    def stalls(oracle, rng):
        oracle("C"); raise H.BudgetExhausted("edit_ga stalled: low yield")
    r3 = H.run_one(stalls, v, budget=20, seed=0, canon=IDENT)
    assert r3["stop_reason"] == "optimizer_stalled" and r3["calls"] == 1
