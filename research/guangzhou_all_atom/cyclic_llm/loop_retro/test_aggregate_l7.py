"""Tests for the source-cluster bootstrap (L7j (3)). Run: python3 test_aggregate_l7.py"""
import os, sys, numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import aggregate_l7 as G

def world(n_src=12, n_per=40, n_seeds=8, lab_sd=0.0, seed_sd=0.05, rng_seed=0):
    """Arm A's advantage over arm B in lab s is `adv_s` (lab heterogeneity lab_sd around mean 0.10); seeds add small noise. y is the label; scores are y*quality + noise."""
    rng = np.random.default_rng(rng_seed); y = rng.standard_normal(n_src * n_per); srcs = [f"lab{i // n_per}" for i in range(n_src * n_per)]
    adv = 0.10 + lab_sd * rng.standard_normal(n_src); res = {}
    for k in range(n_seeds):
        E = rng.choice(n_src * n_per, n_src * 30, replace=False); res[k] = {"E": E.tolist()}
        for arm, base in (("A", 0.5), ("B", 0.5)):
            sc = np.zeros(len(E))
            for j, i in enumerate(E):
                s = int(srcs[i][3:]); q = base + (adv[s] if arm == "A" else 0.0); sc[j] = q * y[i] + (1 - q) * rng.standard_normal() + seed_sd * rng.standard_normal()
            res[k][arm] = {"E_scores_final": sc.tolist()}
    return res, y, srcs

def widths(lab_sd):
    res, y, srcs = world(lab_sd=lab_sd); c = G.cluster_contrast(G.source_rho_table(res, "A", y, srcs), G.source_rho_table(res, "B", y, srcs))
    return c, (c["ci_cluster"][1] - c["ci_cluster"][0]), (c["ci_seed_only"][1] - c["ci_seed_only"][0])

def test_cluster_ci_wider_than_seed_ci_when_lab_effects_vary():
    c_h, wc_h, ws_h = widths(lab_sd=0.35); c_o, wc_o, ws_o = widths(lab_sd=0.0)
    print(f"  heterogeneous labs: n_sources {c_h['n_sources']}, mean {c_h['mean']}, cluster width {wc_h:.3f} vs seed-only width {ws_h:.3f}  |  homogeneous: cluster {wc_o:.3f} vs seed-only {ws_o:.3f}")
    assert wc_h > 1.5 * ws_h, "with varying lab effects the cluster CI must be clearly wider than the lab-blind seed CI"
    assert wc_h > 1.5 * wc_o, "lab heterogeneity must widen the cluster CI relative to a homogeneous world"
    assert c_h["interval_type"].startswith("bootstrap CI of the mean over SOURCES")

def test_cluster_contrast_detects_a_uniform_effect_and_a_null():
    res, y, srcs = world(lab_sd=0.0); c = G.cluster_contrast(G.source_rho_table(res, "A", y, srcs), G.source_rho_table(res, "B", y, srcs)); assert c["ci_cluster"][0] > 0, c
    res2, y2, s2 = world(lab_sd=0.0, rng_seed=1)
    for k in res2: res2[k]["A"] = res2[k]["B"]                                   # identical arms: contrast must be exactly zero
    c0 = G.cluster_contrast(G.source_rho_table(res2, "A", y2, s2), G.source_rho_table(res2, "B", y2, s2)); assert c0["mean"] == 0.0 and c0["ci_cluster"] == [0.0, 0.0]

def test_deterministic_regeneration():
    res, y, srcs = world(lab_sd=0.3); a = G.cluster_contrast(G.source_rho_table(res, "A", y, srcs), G.source_rho_table(res, "B", y, srcs)); b = G.cluster_contrast(G.source_rho_table(res, "A", y, srcs), G.source_rho_table(res, "B", y, srcs)); assert a == b

def test_constant_scores_count_as_zero_not_missing():
    res, y, srcs = world(lab_sd=0.0)
    for k in res: res[k]["B"]["E_scores_final"] = [0.0] * len(res[k]["B"]["E_scores_final"])
    tb = G.source_rho_table(res, "B", y, srcs); assert tb and all(v == 0.0 for d in tb.values() for v in d.values())


def test_point_estimate_lies_inside_its_seed_only_interval_with_unbalanced_sources():
    """QA finding: with sources evaluated in only some seeds, the seed-only interval must be an interval for the SAME reported mean."""
    rng = np.random.default_rng(3); ta, tb = {}, {}
    for s in range(11):
        seeds = [k for k in range(10) if rng.random() < 0.7] or [0, 1, 2, 3]
        if len(seeds) < 3: seeds = [0, 1, 2, 3]
        for k in seeds: ta.setdefault(f"lab{s}", {})[k] = 0.3 + 0.2 * rng.standard_normal(); tb.setdefault(f"lab{s}", {})[k] = 0.25 + 0.2 * rng.standard_normal()
    c = G.cluster_contrast(ta, tb); lo, hi = c["ci_seed_only"]; assert lo <= c["mean"] <= hi, c; lo, hi = c["ci_cluster"]; assert lo <= c["mean"] <= hi, c


def test_nan_guard_never_propagates():
    res, y, srcs = world(lab_sd=0.2)
    ta = G.source_rho_table(res, "A", y, srcs); tb = G.source_rho_table(res, "B", y, srcs); clean = G.cluster_contrast(ta, tb)
    ta2 = {s: dict(v) for s, v in ta.items()}; first = sorted(ta2)[0]; k0 = sorted(ta2[first])[0]; ta2[first][k0] = float("nan")          # one NaN per-seed value
    c = G.cluster_contrast(ta2, tb); assert c["mean"] is not None and np.isfinite(c["mean"]) and all(np.isfinite(c["ci_cluster"])) and all(np.isfinite(c["ci_seed_only"])), c
    ta3 = {s: dict(v) for s, v in ta.items()}
    for k in list(ta3[first]): ta3[first][k] = float("nan")                                                                                   # a whole source NaN: dropped, other sources unaffected
    c3 = G.cluster_contrast(ta3, tb); assert c3["n_sources"] == clean["n_sources"] - 1 and np.isfinite(c3["mean"]), c3
    allnan = {s: {k: float("nan") for k in v} for s, v in ta.items()}; c4 = G.cluster_contrast(allnan, tb); assert c4["mean"] is None and c4["interval_type"] == "insufficient clusters", c4
    res2 = {k: {"E": v["E"], "A": {"E_scores_final": [float("nan")] + v["A"]["E_scores_final"][1:]}} for k, v in res.items()}
    tt = G.source_rho_table(res2, "A", y, srcs); assert all(np.isfinite(x) for d in tt.values() for x in d.values()), "a NaN score must make that (source, seed) missing, not a number"


def test_no_input_is_dropped_or_overwritten_and_aware_blind_stay_apart():
    """Regression test for the 2026-10-30 code-review finding C1: aware and blind GBM share backend 'gbm'. Every file must be loaded under exactly one key; overlapping arms must raise."""
    import tempfile, json as J
    root = tempfile.mkdtemp(); mk = lambda name, val, arms=("loop_sub",): None
    def write(dirname, backend, regime, seed, arms, val):
        d = os.path.join(root, dirname); os.makedirs(d, exist_ok=True); r = {"backend": backend, "regime": regime, "seed": seed}
        for a in arms: r[a] = {"hits": [val], "E_scores_final": [0.0]}
        J.dump(r, open(os.path.join(d, f"{backend}_{regime}_{seed}.json"), "w"))
    write("res7f_gbm_aware", "gbm", "A", 0, ("loop_sub",), 86); write("res7f_gbm_blind", "gbm", "A", 0, ("loop_sub",), 87); write("res7f_gbm_phys", "gbm_physchem", "A", 0, ("loop_sub",), 90)
    write("res7k_gbm_confirm", "gbm", "A", 10, ("loop_sub",), 80); write("res7m_gbm", "gbm", "A", 0, ("loop", "random_fb"), 70)
    dirs = [os.path.join(root, x) for x in sorted(os.listdir(root))]; man = []; S = G.load_small(dirs, man)
    assert len(man) == 5 and len({f for f, _ in man}) == 5, "every file must be read exactly once"
    keys = sorted({k for _, k in man}); assert ("gbm_aware", "A") in keys and ("gbm_blind", "A") in keys and ("gbm_aware_confirm", "A") in keys and ("gbm_aware_srcmatch", "A") in keys and ("gbm_physchem", "A") in keys, keys
    assert S[("gbm_aware", "A")][0]["loop_sub"]["hits"] == [86] and S[("gbm_blind", "A")][0]["loop_sub"]["hits"] == [87], "aware and blind must not overwrite each other"
    assert sum(len(v) for v in S.values()) == 5, "total tasks loaded must equal files"
    write("res7f_gbm_aware2", "gbm", "A", 0, ("loop_sub",), 99)                                                       # a second 'aware' directory repeating the same arm for the same task
    dirs2 = [os.path.join(root, x) for x in sorted(os.listdir(root))]
    try: G.load_small(dirs2); raise AssertionError("an overlapping-arm collision must raise, not overwrite")
    except ValueError: pass

if __name__ == "__main__":
    for n, f in list(globals().items()):
        if n.startswith("test_"): f(); print("PASS", n)
