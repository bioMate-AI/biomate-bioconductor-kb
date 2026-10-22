"""renal_mechmodel.py — mechanistic GREY-BOX renal-retention model (study innovation #2, proof-of-concept).

Not a black box. A physiology-informed, differentiable form fit across targets:

  log1p(kidney %ID/g) ~ intercept
      + w_cat * Hill(q_pos ; Kc)        # megalin/cubilin reabsorption of filtered CATIONIC peptide (saturable)
      + w_an  * Hill(q_neg ; Ka)        # distinct uptake of highly ANIONIC peptide (poly-Glu) (saturable)
      + w_res * residualizing_metal     # metal-chelate trapped in proximal tubule after reabsorption
      + w_alb * albumin_binder          # longer blood residence -> more renal delivery (esp. late t)
      + w_t   * log(timepoint_h)        # clearance / retention vs time
      + w_sm  * is_small_molecule       # small molecules clear via tubular transporters, not filtration+megalin

The TWO saturable routes (cationic + anionic) are the mechanistic crux: a single signed-charge term CANNOT
fit radiopeptide renal retention because retention is high at BOTH charge extremes (U-shaped) — megalin binds
cationic peptides, while anionic poly-glutamate ligands are retained via a separate route. This is exactly the
sign-flip our data shows, and it is why the mechanistic model transfers across targets where net charge fails.

POC goal: does the grey-box BEAT both net-charge AND a black-box GBM on cross-target Leave-One-Target-Out?
Honest about n (proof-of-concept on the current corpus; Gate A n>=50 remains the bar).
"""
from __future__ import annotations
import json, os, re, warnings
import numpy as np
from scipy.optimize import least_squares
from scipy.stats import spearmanr, ConstantInputWarning
import renal_features as rf
import renal_surrogate as rs

warnings.filterwarnings("ignore", category=ConstantInputWarning)
HERE = os.path.dirname(os.path.abspath(__file__))
_RESIDUALIZING = {"177Lu", "111In", "64Cu", "90Y", "68Ga", "52Mn", "99mTc", "225Ac", "161Tb", "212Pb", "89Zr"}  # metals trapped; 18F/halogens not
_TP = {"kidney_pid_g_1h": 1.0, "kidney_pid_g_2h": 2.0, "kidney_pid_g_4h": 4.0, "kidney_pid_g_6h": 6.0,
       "kidney_pid_g_24h": 24.0, "kidney_pid_g_48h": 48.0, "kidney_pid_g_72h": 72.0}


def build_observations():
    """Explode each corpus row into one observation PER measured %ID/g timepoint (mouse, charge-computable).
    Timepoint is a covariate -> scales n honestly without pooling incomparable magnitudes."""
    rows = [json.loads(l) for l in open(os.path.join(HERE, "renal_seed_corpus.jsonl"))]
    tgt = {r["construct_id"]: rs._target_class(r) for r in rows}
    obs = []
    for r in rows:
        if (r.get("species") or "").lower() != "mouse":
            continue
        feats = rf.features_for_row(r)
        if feats is None:
            continue
        q = feats.net_charge_with_chelate
        is_sm = 1.0 if feats.seq_len == 0 else 0.0
        residual = 1.0 if (r.get("radiometal") in _RESIDUALIZING) else 0.0
        alb = 1.0 if r.get("albumin_binder") else 0.0
        cleave = 1.0 if r.get("cleavable_motif") else 0.0
        yrs = re.findall(r"\b(19|20)(\d{2})\b", str(r.get("source", "")))
        year = int("".join(yrs[-1])) if yrs else None          # publication year for temporal split
        for field, t in _TP.items():
            v = r.get(field)
            if v is None:
                continue
            obs.append({"cls": tgt.get(r["construct_id"], "?"), "canon": rs._canonical(r["construct_id"]),
                        "q_pos": max(q, 0.0), "q_neg": max(-q, 0.0),
                        "residual": residual, "alb": alb, "cleave": cleave, "log_t": np.log(t), "is_sm": is_sm,
                        "year": year, "y": float(np.log1p(v))})
    return obs


def _design(obs, Kc, Ka):
    """Feature matrix given Hill constants Kc,Ka (saturable routes). Columns = model terms."""
    X = []
    for o in obs:
        hill_cat = o["q_pos"] / (Kc + o["q_pos"])
        hill_an = o["q_neg"] / (Ka + o["q_neg"])
        X.append([1.0, hill_cat, hill_an, o["residual"], o["alb"], o.get("cleave", 0.0), o["log_t"], o["is_sm"]])
    return np.array(X)


def _ridge(X, y, lam=0.3):
    """Ridge-regularized linear solve (don't penalize the intercept) — prevents the degenerate blow-up
    when a saturable route is weakly identified at small n."""
    p = X.shape[1]
    A = X.T @ X + lam * np.eye(p)
    A[0, 0] -= lam
    return np.linalg.solve(A, X.T @ y)


_LOGK_LO, _LOGK_HI = np.log(0.2), np.log(30.0)       # Hill constants bounded to a physical range


def fit(obs, lam=0.3):
    """Fit Hill constants (bounded) + ridge linear weights on log1p(kidney). Bounds+ridge remove the
    reparameterization degeneracy of the unconstrained fit."""
    y = np.array([o["y"] for o in obs])

    def resid(theta):
        Kc, Ka = np.exp(theta[0]), np.exp(theta[1])
        X = _design(obs, Kc, Ka)
        return X @ _ridge(X, y, lam) - y

    best = None
    for k0 in (np.log(0.5), np.log(3.0)):             # multi-start within bounds
        for a0 in (np.log(0.5), np.log(3.0)):
            r = least_squares(resid, x0=[k0, a0], method="trf",
                              bounds=([_LOGK_LO, _LOGK_LO], [_LOGK_HI, _LOGK_HI]), max_nfev=2000)
            if best is None or r.cost < best.cost:
                best = r
    Kc, Ka = np.exp(best.x[0]), np.exp(best.x[1])
    X = _design(obs, Kc, Ka)
    return {"Kc": Kc, "Ka": Ka, "w": _ridge(X, y, lam)}


def predict(params, obs):
    X = _design(obs, params["Kc"], params["Ka"])
    return X @ params["w"]


# ---- evaluation: cross-target LOTO, mechanistic vs net-charge vs GBM (mean within-class Spearman) ----
def _mpc(score, y, cls):
    per = {}
    for c in set(cls):
        m = np.array([cc == c for cc in cls])
        if m.sum() >= 3 and len(set(np.array(y)[m])) > 1:
            rho = spearmanr(np.array(score)[m], np.array(y)[m]).correlation
            if not np.isnan(rho):
                per[c] = rho
    return (float(np.mean(list(per.values()))) if per else float("nan")), {k: round(v, 3) for k, v in per.items()}


def loto_compare(min_class_n=3):
    import collections
    obs = build_observations()
    classes = [c for c, n in collections.Counter(o["cls"] for o in obs).items()
               if sum(1 for o in obs if o["cls"] == c) >= min_class_n]
    from sklearn.ensemble import GradientBoostingRegressor
    s_mech, s_nc, s_gbm, Y, CL = [], [], [], [], []
    for held in classes:
        tr = [o for o in obs if o["cls"] != held]
        te = [o for o in obs if o["cls"] == held]
        if len(tr) < 8 or len(te) < 3:
            continue
        # mechanistic grey-box
        p = fit(tr); pm = predict(p, te)
        # net-charge baseline (signed net charge = q_pos - q_neg)
        nc = [o["q_pos"] - o["q_neg"] for o in te]
        # black-box GBM on the same raw inputs
        feat = lambda o: [o["q_pos"], o["q_neg"], o["residual"], o["alb"], o.get("cleave", 0.0), o["log_t"], o["is_sm"]]
        g = GradientBoostingRegressor(n_estimators=200, max_depth=2, learning_rate=0.05, random_state=0)
        g.fit(np.array([feat(o) for o in tr]), np.array([o["y"] for o in tr]))
        gp = g.predict(np.array([feat(o) for o in te]))
        s_mech += list(pm); s_nc += nc; s_gbm += list(gp)
        Y += [o["y"] for o in te]; CL += [held] * len(te)
    out = {}
    for name, s in (("mechanistic", s_mech), ("net_charge", s_nc), ("gbm_blackbox", s_gbm)):
        _, per = _mpc(s, Y, CL)
        out[name] = {"per_class": per}
    # FAIR comparison: average each model over the COMMON set of classes ALL models can rank
    # (a class a model predicts as constant -> undefined Spearman -> excluded for everyone).
    common = set.intersection(*[set(out[n]["per_class"]) for n in out]) if out else set()
    for name in out:
        vals = [out[name]["per_class"][c] for c in common]
        out[name]["mean_per_class_common"] = round(float(np.mean(vals)), 3) if vals else float("nan")
    return {"n_obs": len(obs), "classes": classes, "n_pooled": len(Y),
            "common_classes": sorted(common), "unrankable_by_some": sorted(set(classes) - common),
            "results": out}


if __name__ == "__main__":
    obs = build_observations()
    p = fit(obs)
    print("=== Mechanistic grey-box renal model (fit on all mouse %ID/g observations) ===")
    print(f"  observations (timepoint-exploded) = {len(obs)}")
    names = ["intercept", "w_cat(megalin)", "w_an(anionic)", "w_res(residual)", "w_alb(albumin)", "w_cleave(linker)", "w_t(log t)", "w_sm(small-mol)"]
    print(f"  Hill constants: Kc(cationic)={p['Kc']:.2f}  Ka(anionic)={p['Ka']:.2f}")
    for n, w in zip(names, p["w"]):
        print(f"    {n:18s} {w:+.3f}")
    print("\n=== Cross-target LOTO: mechanistic vs net-charge vs black-box GBM (mean within-class Spearman) ===")
    r = loto_compare()
    print(f"  obs={r['n_obs']}  pooled held-out n={r['n_pooled']}")
    print(f"  common rankable classes (fair comparison): {r['common_classes']}")
    print(f"  unrankable by >=1 model (charge-invariant, structure-driven): {r['unrankable_by_some']}")
    for name in ("mechanistic", "gbm_blackbox", "net_charge"):
        res = r["results"][name]
        print(f"    {name:14s} mean-per-class(common) rho={res['mean_per_class_common']:+.3f}  per-class={res['per_class']}")
    print("\nPOC on current corpus (small n) — hypothesis-generating. The mechanistic form is the paper's")
    print("method; two saturable routes (cationic megalin + anionic) encode the charge sign-flip as mechanism.")
