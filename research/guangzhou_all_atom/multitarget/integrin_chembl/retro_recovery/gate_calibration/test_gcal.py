import numpy as np, pytest
import gcal_lib as L

def mk(shift=0.0, F=26, typ="M", seed=0, inflate=1.0, item=False):
    r = np.random.default_rng(seed)
    def ctl(level, off=0.0):
        s = 0.012 * inflate * (26 / F) ** 0.5; p = 0.5 + off + r.normal(0, s); z = L.zcrit(level)
        return dict(point=float(p), lo=float(p - z * s), hi=float(p + z * s), n_families=F)
    rec = dict(status="NOT_VALID_BIASED", primary={k: ({x: v for x, v in ctl(L.PRIM_LEVEL, shift if k == "C1_atomlm_typicality" else 0.0).items()} | {"lo90": 0, "hi90": 0}) for k in L.PRIMARY},
               secondary={k: ctl(L.L18) for k in L.SEC18})
    if item:
        for k in L.ITEM: rec["secondary"][k] = ctl(L.L22)
    return rec

def null_set(n, **kw): return [mk(seed=i, **kw) for i in range(n)]

def test_zvals_se_roundtrip():
    rec = mk(seed=1); z, se = L.zvals(rec)
    k = "heavy"; c = rec["secondary"][k]; assert abs(se[k] - (c["hi"] - c["lo"]) / (2 * L.zcrit(L.L18))) < 1e-12
    assert set(z) == set(L.PRIMARY) | set(L.SEC18)

def test_degenerate_and_small_n_excluded():
    rec = mk(seed=2); rec["secondary"]["heavy"]["hi"] = rec["secondary"]["heavy"]["lo"]; rec["secondary"]["tpsa"]["n_families"] = 5
    z, _ = L.zvals(rec); assert "heavy" not in z and "tpsa" not in z

def test_fit_and_false_alarm_rate_near_alpha():
    cal = L.fit({"M": null_set(600)}); fresh = null_set(600, seed=0) if False else [mk(seed=10_000 + i) for i in range(600)]
    fa = np.mean([L.assess(r, cal)["status"] == "BIASED" for r in fresh]); assert 0.02 < fa < 0.10, fa

def test_detects_shifted_control_and_equivalence_logic():
    cal = L.fit({"M": null_set(600)})
    assert L.assess(mk(shift=0.06, seed=7), cal)["status"] == "BIASED"
    ok = L.assess(mk(seed=8, F=26), cal); assert ok["status"] in ("VALID", "NOT_EQUIVALENT")
    assert L.delta(26) == pytest.approx(0.0553, abs=5e-4) and L.delta(14) == pytest.approx(0.0754, abs=5e-4) and L.delta(47) == pytest.approx(0.0411, abs=5e-4)

def test_inflated_intervals_are_corrected():
    # records whose intervals are anti-conservative (SE underestimated 2x): kappa ~ 2 restores the false-alarm rate
    cal = L.fit({"M": [dict(mk(seed=i)) for i in range(600)]})
    def anti(i):
        rec = mk(seed=20_000 + i)
        for v in list(rec["primary"].values()) + list(rec["secondary"].values()):
            m = (v["lo"] + v["hi"]) / 2; h = (v["hi"] - v["lo"]) / 2 / 2; v["lo"], v["hi"] = m - h, m + h
        return rec
    naive = np.mean([L.assess(anti(i), cal)["status"] == "BIASED" for i in range(300)])
    cal2 = L.fit({"M": [anti(i) for i in range(600)]}); fresh = np.mean([L.assess(anti(1000 + i), cal2)["status"] == "BIASED" for i in range(300)])
    assert naive > 0.5 and fresh < 0.12, (naive, fresh)

def test_cp_ci_known_values():
    lo, hi = L.cp_ci(0, 400); assert lo == 0 and abs(hi - 0.00916) < 2e-4
    lo, hi = L.cp_ci(20, 400); assert 0.031 < lo < 0.033 and 0.076 < hi < 0.078

def test_item_type_detected():
    assert L.rec_type(mk(item=True, seed=3)) == "I" and L.rec_type(mk(seed=3)) == "M"

def test_secondary_list_matches_gate():
    try:
        import sys, os; sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
        import validity_gate as G
    except Exception as e: pytest.skip(f"gate not importable: {e}")
    assert list(G.SECONDARY) == L.SEC18
