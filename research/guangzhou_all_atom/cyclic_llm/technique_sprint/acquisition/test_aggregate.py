#!/usr/bin/env python3
"""Positive controls for the T2 decision machinery: synthetic result files with a KNOWN right verdict (pre-registration 1.8)."""
import os, sys, json, tempfile
import numpy as np
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
import aggregate_acq as G


def fake(scenario, n=30, seed=0):
    rng = np.random.default_rng(seed); R = {}
    base = {"A": 230.0, "B": 60.0, "L": 55.0}
    for g, b in base.items():
        common = rng.normal(0, 8, n)                                        # shared seed-level variation (paired design)
        def put(label, mean, ent, top):
            for s in range(n):
                R[(label, g, s)] = dict(label=label, regime=g, seed=s, hits=float(mean + common[s] + rng.normal(0, 3)), rounds=[float(mean / 10)] * 10, src_entropy=float(ent + rng.normal(0, .05)), top_src_share=float(top + rng.normal(0, .01)),
                                        flat_entropy=4.0, n_flat=300, cfg={})
        put("random", b * 0.35, 2.5, 0.40)
        put("greedy", b, 0.8, 0.70); put("ucb", b * 1.01, 0.8, 0.70); put("rule_phys", b * 0.95, 1.0, 0.5); put("nn_greedy", b * 0.9, 0.9, 0.6); put("fuse", b * 1.0, .9, .65); put("div", b * 1.0, 1.9, .3)
        gain = {"gain": 1.12 if g in ("B", "L") else 1.0, "null": 1.0, "A_degraded": 1.12 if g in ("B", "L") else 0.80, "no_entropy": 1.12 if g in ("B", "L") else 1.0}[scenario]
        ent, top = (0.8, 0.70) if scenario == "no_entropy" else (1.9, 0.30)
        put("prov", b * gain, ent, top)
    return R


def check(scenario, expect_prefix, s1):
    out = G.decide(fake(scenario)); v = out["VERDICT"]; assert v.startswith(expect_prefix), (scenario, v); assert out["S1_any_of_B_L"] == s1, (scenario, out["S1_by_regime"]); print(f"PASS {scenario}: {v}")


def test_ci():
    d = np.random.default_rng(1).normal(5, 3, 30); ci = G.boot_ci(d); assert ci[0] > 0, ci
    z = np.random.default_rng(2).normal(0, 3, 30); assert G.boot_ci(z)[0] < 0 < G.boot_ci(z)[1]; print("PASS bootstrap CI excludes 0 for a real shift and includes 0 for a null")


def test_select_config():
    R = {}
    cfgs = {"prov@a": dict(lam=0.0, cap_src=50, cap_flat=10 ** 9), "prov@b": dict(lam=0.5, cap_src=25, cap_flat=5), "prov@c": dict(lam=1.0, cap_src=25, cap_flat=5)}
    rel = {"prov@a": (1.00, 1.02, 1.01), "prov@b": (0.97, 1.10, 1.08), "prov@c": (0.80, 1.30, 1.30)}                  # c violates rel_A>=0.90; b is the best admissible
    for l, (ra, rb, rl) in rel.items():
        for g, r in zip("ABL", (ra, rb, rl)):
            for s in range(5):
                R[("greedy", g, 100 + s)] = dict(label="greedy", regime=g, seed=100 + s, hits=100, src_entropy=1.0, cfg={})
                R[(l, g, 100 + s)] = dict(label=l, regime=g, seed=100 + s, hits=100 * r, src_entropy=1.5, cfg=cfgs[l])
    out = G.select_config(R); assert out["selected_label"] == "prov@b" and out["constraint_rel_A_ge_0p90_met"], out["selected_label"]; print("PASS config selection honours the rel_A >= 0.90 constraint")


if __name__ == "__main__":
    test_ci(); check("gain", "SUPPORTED", True); check("null", "NULL_KILL", False); check("A_degraded", "PARTIAL", True); check("no_entropy", "PARTIAL", True); test_select_config(); print("all aggregate tests passed")
