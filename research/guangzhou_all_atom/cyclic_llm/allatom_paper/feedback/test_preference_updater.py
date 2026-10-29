import numpy as np

from .preference_updater import (GradedPreferenceUpdater, KLWeightGate, LegacyBinaryGRPO, dpo_loss_and_grad_coef,
                                 rank_advantage)
from . import toy_policy as TP


def test_rank_advantage_ties_and_constant():
    a = rank_advantage([1, 2, 3])
    assert np.allclose(a, [-0.5, 0.0, 0.5])
    t = rank_advantage([1, 1, 3])
    assert abs(t[0] - t[1]) < 1e-12 and t[2] > t[0]
    assert np.all(rank_advantage([0.7] * 5) == 0)


def test_pairs_drop_zero_variance_small_groups_and_count_them():
    u = GradedPreferenceUpdater(group_size=4, margin=0.05)
    samples = list("abcdefghijklm")
    scores = [0.5] * 4 + [0.1, 0.9, 0.3, 0.7] + [0.2, 0.4, None, 0.6, 0.8]
    groups = [0] * 4 + [1] * 4 + [2] * 5
    pairs, d = u.make_pairs(samples, scores, group_by=groups)
    ps = u.last_index_pairs
    assert d["frac_zero_variance_groups"] == 1 / 3 and d["n_invalid_excluded"] == 1
    assert all(g != "0" for g in (p.group for p in pairs))         # the constant group produced no pair
    assert all(scores[w] - scores[l] >= 0.05 for w, l in zip(ps.winners, ps.losers))
    assert d["n_pairs"] == len(pairs) > 0 and d["n_groups_kept"] >= 1 and d["mean_margin"] >= 0.05
    assert all(p.margin >= 0.05 and isinstance(p.chosen, str) for p in pairs)
    u2 = GradedPreferenceUpdater(group_size=5, margin=0.05)
    _, d2 = u2.make_pairs(samples, scores, group_by=groups)
    assert d2["frac_small_groups_dropped"] > 0                      # groups of 4 are below group_size 5


def test_margin_filters_pairs():
    u = GradedPreferenceUpdater(group_size=4, margin=0.5)
    pairs, _ = u.make_pairs(list("abcd"), [0.1, 0.2, 0.3, 0.4], group_by=[0] * 4)
    assert len(pairs) == 0
    pairs, _ = u.make_pairs(list("abcd"), [0.0, 0.2, 0.3, 0.9], margin=0.5, group_by=[0] * 4)
    assert len(pairs) == 1


def test_dpo_coefficient_sign_and_value():
    loss, dz = dpo_loss_and_grad_coef(0.0, 0.0, 0.0, 0.0, beta=0.5)
    assert abs(loss - np.log(2)) < 1e-12 and abs(dz + 0.5) < 1e-12   # z=0 -> d/dz = -0.5
    _, dz_big = dpo_loss_and_grad_coef(5.0, -5.0, 0.0, 0.0, beta=1.0)
    assert -1e-3 < dz_big < 0                                       # already satisfied -> tiny gradient


def test_legacy_zero_advantage_when_all_pass():
    L = LegacyBinaryGRPO(threshold=0.2)
    adv, frac0 = L.advantages({0: [0.5, 0.6, 0.9], 1: [0.1, 0.5, 0.6]})
    assert np.all(adv[0] == 0) and frac0 == 0.5 and np.any(adv[1] != 0)


def test_gate_sequence():
    g = KLWeightGate()
    assert g.update(1, 0.0, 0.0) == "continue"                       # before check_from
    assert g.update(3, 0.001, 0.001) == "raise_lr_rank_once"
    assert g.update(4, 0.001, 0.001) == "continue"                   # recheck_after not reached
    assert g.update(5, 0.001, 0.001) == "stop"
    g2 = KLWeightGate()
    assert g2.update(3, 0.2, 0.2) == "continue"


def test_toy_control_old_fails_new_learns_on_concentrated_start():
    gl, gg, kl_g, kl_l, z_l = [], [], [], [], []
    for s in range(10):
        env = TP.make_env(s, start="concentrated")
        a = TP.run(env, "legacy", rounds=10, lr=2.0, seed=s)
        b = TP.run(env, "graded", rounds=10, lr=2.0, seed=s)
        gl.append(a["gain"]), gg.append(b["gain"]), kl_l.append(a["kl"]), kl_g.append(b["kl"])
        z_l.append(np.mean([h["frac_zero_variance_groups"] for h in a["hist"]]))
    assert np.mean(z_l) > 0.9                                         # the stall: >90% of groups have zero variance
    assert abs(np.mean(gl)) < 0.01 and np.mean(kl_l) < 0.01           # legacy learns nothing, KL ~ 0
    assert np.mean(gg) > 0.10 and np.mean(kl_g) > 0.01                # graded updater learns (control that can fail)


def test_toy_control_legacy_works_when_variance_exists():
    gl = []
    for s in range(10):
        env = TP.make_env(s, start="broad")
        gl.append(TP.run(env, "legacy", rounds=10, lr=2.0, seed=s)["gain"])
    assert np.mean(gl) > 0.01                                        # so the stall is the variance structure, not a broken legacy code path
