"""renal_eval.py — PUBLICATION-GRADE evaluation of the renal-retention surrogate.

A point-estimate Spearman on n=4 is not a paper result. This module reports what a methods paper needs:

  1. POOLED Leave-One-Target-Out (LOTO): for a homogeneous stratum, train on all target classes but one,
     predict the held-out class; concatenate held-out predictions across all classes into ONE pooled
     (prediction, truth) vector — the honest estimand for "generalizes to an unseen target".
  2. BASELINES under the identical LOTO protocol: signed net charge, |net charge|, and a random/null.
     The surrogate must beat these, not just beat chance.
  3. UNCERTAINTY: bootstrap 95% CI on every pooled Spearman (resample the pooled pairs).
  4. SIGNIFICANCE: permutation p-value (shuffle truths, recompute pooled Spearman) AND a paired
     bootstrap CI on the surrogate-minus-baseline difference (does the model beat net charge, with CI
     excluding 0?).
  5. HONEST POWER: n per class, pooled n, CI width — stated, not hidden.

Deterministic (fixed seeds). Reports per stratum; mixing strata (unit/species/timepoint) is never done.
"""
from __future__ import annotations
import warnings
import numpy as np
from scipy.stats import spearmanr, ConstantInputWarning
import renal_surrogate as rs

warnings.filterwarnings("ignore", category=ConstantInputWarning)   # constant bootstrap resample -> nan, filtered

RNG = np.random.default_rng(0)


def _points(stratum, aggregate=True):
    rows, usable = rs.assemble(aggregate=aggregate)
    tgt = {r["construct_id"]: rs._target_class(r) for r in rows}
    pts = []
    for u in usable:
        if u["kind"] != stratum:
            continue
        pts.append({"cls": tgt.get(u["id"], "?"), "x": np.array(u["x"], float),
                    "y": float(u["y"]), "netq": float(u["net_charge"])})
    return pts


def _loto_scores(pts, model):
    """Return pooled (score, truth, class) from leave-one-TARGET-out. model in
    {'full','netcharge','abscharge'}. 'full' = GBM trained on other classes; baselines need no training."""
    import collections
    from sklearn.ensemble import GradientBoostingRegressor
    classes = [c for c, n in collections.Counter(p["cls"] for p in pts).items() if n >= 3]
    score, truth, cls = [], [], []
    for held in classes:
        tr = [p for p in pts if p["cls"] != held]
        te = [p for p in pts if p["cls"] == held]
        if len(tr) < 6 or len(te) < 3:
            continue
        if model == "full":
            m = GradientBoostingRegressor(n_estimators=200, max_depth=2, learning_rate=0.05, random_state=0)
            m.fit(np.array([p["x"] for p in tr]), np.array([p["y"] for p in tr]))
            s = m.predict(np.array([p["x"] for p in te]))
        elif model == "netcharge":
            s = np.array([p["netq"] for p in te])
        elif model == "abscharge":
            s = np.array([abs(p["netq"]) for p in te])
        else:
            raise ValueError(model)
        score += list(s); truth += [p["y"] for p in te]; cls += [held] * len(te)
    return np.array(score), np.array(truth), cls


def _mean_per_class(score, truth, cls):
    """Mean of WITHIN-CLASS Spearman across held-out classes — the correct estimand for 'ranks
    constructs within an unseen target'. Not confounded by cross-class scale/offset (unlike pooled)."""
    import collections
    per = {}
    for c in set(cls):
        m = np.array([cc == c for cc in cls])
        if m.sum() >= 3 and len(set(truth[m])) > 1:
            rho = spearmanr(score[m], truth[m]).correlation
            if not np.isnan(rho):
                per[c] = rho
    if not per:
        return float("nan"), {}
    return float(np.mean(list(per.values()))), {k: round(v, 3) for k, v in per.items()}


def _mpc_boot_ci(score, truth, cls, n_boot=2000):
    """Bootstrap CI of mean-per-class Spearman: resample points WITHIN each class."""
    rng = np.random.default_rng(0); classes = sorted(set(cls))
    idx_by = {c: np.where(np.array(cls) == c)[0] for c in classes}
    vals = []
    for _ in range(n_boot):
        rhos = []
        for c, idx in idx_by.items():
            if len(idx) < 3:
                continue
            bi = rng.choice(idx, len(idx), replace=True)
            if len(set(truth[bi])) < 2:
                continue
            rho = spearmanr(score[bi], truth[bi]).correlation
            if not np.isnan(rho):
                rhos.append(rho)
        if rhos:
            vals.append(np.mean(rhos))
    if not vals:
        return (float("nan"), float("nan"))
    return (round(float(np.percentile(vals, 2.5)), 3), round(float(np.percentile(vals, 97.5)), 3))


def _mpc_perm_p(score, truth, cls, n_perm=5000):
    """Permutation p for mean-per-class: shuffle truth WITHIN each class."""
    obs, _ = _mean_per_class(score, truth, cls)
    if np.isnan(obs):
        return float("nan"), float("nan")
    rng = np.random.default_rng(0); classes = sorted(set(cls))
    idx_by = {c: np.where(np.array(cls) == c)[0] for c in classes}
    ge = cnt = 0
    for _ in range(n_perm):
        t2 = truth.copy()                     # permute truth WITHIN each class
        for c, idx in idx_by.items():
            t2[idx] = rng.permutation(truth[idx])
        val, _ = _mean_per_class(score, t2, cls)
        if not np.isnan(val):
            cnt += 1
            if abs(val) >= abs(obs):
                ge += 1
    return round(float(obs), 3), round((ge + 1) / (cnt + 1), 4)


def _boot_ci(score, truth, n_boot=2000):
    if len(score) < 4:
        return (float("nan"), float("nan"))
    rng = np.random.default_rng(0); vals = []
    n = len(score)
    for _ in range(n_boot):
        idx = rng.integers(0, n, n)
        if len(set(truth[idx])) < 2:
            continue
        rho = spearmanr(score[idx], truth[idx]).correlation
        if not np.isnan(rho):
            vals.append(rho)
    if not vals:
        return (float("nan"), float("nan"))
    return (round(float(np.percentile(vals, 2.5)), 3), round(float(np.percentile(vals, 97.5)), 3))


def _perm_p(score, truth, n_perm=5000):
    obs = spearmanr(score, truth).correlation
    if np.isnan(obs):
        return float("nan"), float("nan")
    rng = np.random.default_rng(0); ge = 0; cnt = 0
    for _ in range(n_perm):
        rho = spearmanr(score, rng.permutation(truth)).correlation
        if np.isnan(rho):
            continue
        cnt += 1
        if abs(rho) >= abs(obs):
            ge += 1
    return round(float(obs), 3), round((ge + 1) / (cnt + 1), 4)   # two-sided, +1 smoothing


def _paired_diff_ci(sA, sB, truth, n_boot=2000):
    """Bootstrap CI of Spearman(sA)-Spearman(sB) on the same pooled pairs (model vs baseline)."""
    rng = np.random.default_rng(0); diffs = []; n = len(truth)
    for _ in range(n_boot):
        idx = rng.integers(0, n, n)
        if len(set(truth[idx])) < 2:
            continue
        ra = spearmanr(sA[idx], truth[idx]).correlation
        rb = spearmanr(sB[idx], truth[idx]).correlation
        if not (np.isnan(ra) or np.isnan(rb)):
            diffs.append(ra - rb)
    if not diffs:
        return (float("nan"), float("nan"), float("nan"))
    return (round(float(np.median(diffs)), 3), round(float(np.percentile(diffs, 2.5)), 3),
            round(float(np.percentile(diffs, 97.5)), 3))


def evaluate(stratum, aggregate=True):
    import collections
    pts = _points(stratum, aggregate)
    by_cls = collections.Counter(p["cls"] for p in pts)
    classes_used = {c: n for c, n in by_cls.items() if n >= 3}
    rep = {"stratum": stratum, "n_total": len(pts), "classes_all": dict(by_cls),
           "classes_in_loto": classes_used, "aggregate_pseudoreplicates": aggregate}
    if sum(1 for n in classes_used.values() if n >= 3) < 2:
        rep["runnable"] = False
        rep["reason"] = "need >=2 target classes with >=3 charge-computable constructs each"
        return rep
    rep["runnable"] = True
    out = {}
    cache = {}
    for model in ("full", "netcharge", "abscharge"):
        s, y, cls = _loto_scores(pts, model); cache[model] = (s, y, cls)
        mpc, per = _mean_per_class(s, y, cls)                 # PRIMARY metric
        mlo, mhi = _mpc_boot_ci(s, y, cls)
        _, mp = _mpc_perm_p(s, y, cls)
        prho, pp = _perm_p(s, y); plo, phi = _boot_ci(s, y)   # pooled (secondary; scale-confounded)
        out[model] = {"mean_per_class_spearman": round(mpc, 3), "mpc_ci95": [mlo, mhi], "mpc_perm_p": mp,
                      "per_class": {k: round(v, 3) for k, v in per.items()},
                      "pooled_spearman": prho, "pooled_ci95": [plo, phi], "pooled_perm_p": pp,
                      "pooled_n": int(len(s))}
    rep["results"] = out
    # paired: full vs net charge, full vs |charge|
    sF, yF, _ = cache["full"]
    for base in ("netcharge", "abscharge"):
        sB, _, _ = cache[base]
        med, lo, hi = _paired_diff_ci(sF, sB, yF)
        rep.setdefault("paired_vs", {})[base] = {"delta_spearman_median": med, "ci95": [lo, hi],
            "beats_baseline_95ci": (lo > 0) if not np.isnan(lo) else None}
    return rep


if __name__ == "__main__":
    import json
    print("=== Renal surrogate — publication-grade LOTO evaluation ===")
    print("(pooled leave-one-target-out; baselines net-charge/|charge|; bootstrap 95% CI; permutation p)\n")
    for stratum in ("pidg_4h", "pidg_1h"):
        rep = evaluate(stratum, aggregate=True)
        print(f"STRATUM {stratum}  (de-pseudo-replicated)")
        if not rep["runnable"]:
            print(f"  NOT RUNNABLE: {rep['reason']}  classes={rep['classes_all']}\n"); continue
        print(f"  classes in LOTO: {rep['classes_in_loto']}  (pooled n = {rep['results']['full']['pooled_n']})")
        print("  PRIMARY metric = mean within-class Spearman (held-out target); pooled shown secondary (scale-confounded):")
        for model in ("full", "netcharge", "abscharge"):
            r = rep["results"][model]
            print(f"    {model:10s} mean-per-class rho={r['mean_per_class_spearman']:+.3f} 95%CI[{r['mpc_ci95'][0]:+.2f},{r['mpc_ci95'][1]:+.2f}] "
                  f"perm_p={r['mpc_perm_p']}  per-class={r['per_class']}")
            print(f"               (pooled rho={r['pooled_spearman']:+.3f} 95%CI[{r['pooled_ci95'][0]:+.2f},{r['pooled_ci95'][1]:+.2f}] p={r['pooled_perm_p']})")
        print()
    print("HONEST POWER: pooled n is small (tens); CIs are wide. These are HYPOTHESIS-generating effect")
    print("sizes with uncertainty, not a powered confirmatory result. Gate A (n>=50/stratum) remains the bar.")
