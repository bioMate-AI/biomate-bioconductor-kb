#!/usr/bin/env python3
"""Aggregate the frozen aware-vs-blind experiment per docs/20261031_FROZEN_AWARE_VS_BLIND_PREREG.md. Every rule below is the pre-registered one.
usage: aggregate_frozen_ab.py OUT.json --real DIR --committed DIR [--controls DIR]
  DIR/real/{aware,blind,phys}/<prefix>_<regime>_<seed>.json  (prefix gbm for aware/blind, gbm_physchem for phys)
  DIR/committed/{aware,blind,phys}/...  (the res7f_* task files behind the committed l7_aggregate.json, seeds 0-9)
  DIR/controls/{chiral,flat}_{aware,blind}/gbm_<regime>_<seed>.json
Intervals are TYPED in the output: t_mean (t-interval of the mean over paired seeds), boot_mean (percentile bootstrap of the mean over seeds, B=10000, deterministic), cluster_source (bootstrap over picked-from sources of the summed per-source difference)."""
import os, sys, json, glob, math, zlib, argparse, collections
import numpy as np
from scipy import stats
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))      # loop_retro (run_loop, run_loop_prior, run_l7a)

MARGIN = 10.0                    # hits, fixed before any new seed (prereg 4)
B_BOOT = 10000
PREFIX = {"aware": "gbm", "blind": "gbm", "phys": "gbm_physchem"}
ENDPOINT = {"L": "frozen", "A": "frozen_sub", "B": "frozen_sub"}     # committed headline arm per regime
OTHER = {"L": "frozen_sub", "A": "frozen", "B": "frozen"}


def _rng(v, tag):
    return np.random.default_rng(zlib.crc32(repr((tag, len(v), tuple(round(float(x), 6) for x in v))).encode()))


def t_interval(d, level=0.95):
    d = np.asarray(d, float); n = len(d)
    if n < 2: return None
    se = d.std(ddof=1) / math.sqrt(n); h = stats.t.ppf(0.5 + level / 2, n - 1) * se
    return [float(d.mean() - h), float(d.mean() + h)]


def boot_interval(d, level=0.95):
    d = np.asarray(d, float)
    if len(d) < 2: return None
    r = _rng(d, "boot"); bs = np.array([d[r.integers(0, len(d), len(d))].mean() for _ in range(B_BOOT)]); a = (1 - level) / 2 * 100
    return [float(np.percentile(bs, a)), float(np.percentile(bs, 100 - a))]


def paired_p(d):
    d = np.asarray(d, float)
    if len(d) < 2 or d.std(ddof=1) == 0: return None
    return float(stats.ttest_1samp(d, 0.0).pvalue)


def holm(ps):
    """Holm step-down adjusted p-values for a dict name->p (None stays None)."""
    items = sorted(((p, k) for k, p in ps.items() if p is not None)); m = len(items); out = {k: None for k in ps}; run = 0.0
    for i, (p, k) in enumerate(items):
        run = max(run, min(1.0, (m - i) * p)); out[k] = run
    return out


def decide(d, p_adj, margin=MARGIN):
    """Pre-registered decision rule (prereg 5)."""
    t95, b95, t90, b90 = t_interval(d, .95), boot_interval(d, .95), t_interval(d, .90), boot_interval(d, .90)
    if None in (t95, b95, t90, b90) or p_adj is None: return "INCONCLUSIVE", dict(t95=t95, b95=b95, t90=t90, b90=b90)
    different = p_adj < 0.05 and (b95[0] > 0 or b95[1] < 0) and (t95[0] > 0 or t95[1] < 0)
    equiv = (-margin < t90[0] and t90[1] < margin) and (-margin < b90[0] and b90[1] < margin)
    lab = ("DIFFERENT_BUT_WITHIN_MARGIN" if equiv else "DIFFERENT") if different else ("EQUIVALENT" if equiv else "INCONCLUSIVE")
    return lab, dict(t95=t95, b95=b95, t90=t90, b90=b90)


def load_dir(d, learner, regime, seeds):
    out = {}
    for s in seeds:
        f = f"{d}/{PREFIX[learner]}_{regime}_{s}.json"
        if os.path.exists(f): out[s] = json.load(open(f))
    return out


def hits(rec, arm): return sum(rec[arm]["hits"]) if arm in rec else None


def contrast(a, b, arm, seeds, key=None):
    """paired a-b over seeds present in both with the arm"""
    key = key or (lambda r: hits(r, arm)); ss = [s for s in seeds if s in a and s in b and key(a[s]) is not None and key(b[s]) is not None]
    return ss, np.array([key(a[s]) - key(b[s]) for s in ss], float)


def regression(new, committed, learner, regime):
    """seeds 0-9: every arm present in BOTH files must have identical per-round hits, picks and final held-out scores."""
    n_cmp = n_same = 0; bad = []
    for s, c in committed.items():
        if s not in new: bad.append((learner, regime, s, "missing new file")); continue
        for arm in ("frozen", "frozen_sub"):
            if arm in c and arm in new[s]:
                n_cmp += 1
                same = c[arm]["hits"] == new[s][arm]["hits"] and c[arm]["picks"] == new[s][arm]["picks"] and c[arm].get("E_scores_final") == new[s][arm].get("E_scores_final")
                n_same += bool(same)
                if not same: bad.append((learner, regime, s, arm))
        if new[s]["E"] != c["E"] or new[s]["init"] != c["init"]: bad.append((learner, regime, s, "split differs"))
    return dict(compared=n_cmp, identical=n_same, mismatches=bad)


def source_cluster(recs_a, recs_b, arm, seeds, y, thr, srcs):
    """summed per-source difference in hits (picks with y>=thr, grouped by the pick's source), seeds averaged within source; bootstrap over sources"""
    def per_source(rec):
        c = collections.Counter()
        for rd in rec[arm]["picks"]:
            for i in rd:
                if y[i] >= thr: c[srcs[i]] += 1
        return c
    ss = [s for s in seeds if s in recs_a and s in recs_b and arm in recs_a[s] and arm in recs_b[s]]
    if not ss: return None
    tot = collections.defaultdict(float)
    for s in ss:
        ca, cb = per_source(recs_a[s]), per_source(recs_b[s])
        for k in set(ca) | set(cb): tot[k] += (ca[k] - cb[k]) / len(ss)
    names = sorted(tot); v = np.array([tot[k] for k in names]); r = _rng(v, "cluster"); bs = np.array([v[r.integers(0, len(v), len(v))].sum() for _ in range(B_BOOT)])
    top = sorted(zip(names, v), key=lambda t: -abs(t[1]))[:3]
    return dict(statistic="sum over sources of the seed-averaged hit difference", total=float(v.sum()), n_sources=len(v), ci95=[float(np.percentile(bs, 2.5)), float(np.percentile(bs, 97.5))],
                top3_sources=[(k, round(float(x), 2)) for k, x in top], interval_type="cluster_source")


def held_out_sets(csv, seeds):
    import run_loop as R, run_loop_prior as K, run_l7a as L
    recs = R.load(csv); srcs = [r["source"] for r in recs]; out = {}
    for s in seeds: out[s] = L.setup_L(s, srcs, 100)[3]
    return out


def lab_jackknife(diffs_by_seed, held):
    labs = sorted({l for h in held.values() for l in h}); res = {}
    for lab in labs:
        keep = [s for s in diffs_by_seed if lab not in held[s]]
        if len(keep) >= 10: res[lab] = dict(n_seeds=len(keep), mean=round(float(np.mean([diffs_by_seed[s] for s in keep])), 2))
    return res


def real_y(csv):
    import run_loop as R, run_loop_prior as K
    recs = R.load(csv); srcs = [r["source"] for r in recs]; y = K.source_normalize(np.array([r["y"] for r in recs]), srcs); return y, float(np.quantile(y, 0.9)), srcs


def summarize(name, ss, d, p_adj):
    lab, ivs = decide(d, p_adj)
    return dict(contrast=name, n_seeds=len(ss), mean=round(float(np.mean(d)), 3), sd=round(float(np.std(d, ddof=1)), 3) if len(d) > 1 else None, p_t=paired_p(d), p_holm=p_adj,
                intervals={"t_mean_95": ivs["t95"], "boot_mean_95": ivs["b95"], "t_mean_90": ivs["t90"], "boot_mean_90": ivs["b90"]}, outcome=lab)


def main():
    ap = argparse.ArgumentParser(); ap.add_argument("out"); ap.add_argument("--base", required=True); ap.add_argument("--csv", required=True); ap.add_argument("--seeds", default="0-39"); ap.add_argument("--no-extras", action="store_true")
    a = ap.parse_args(); lo, hi = map(int, a.seeds.split("-")); seeds = list(range(lo, hi + 1)); res = dict(prereg="docs/20261031_FROZEN_AWARE_VS_BLIND_PREREG.md", margin_hits=MARGIN, seeds=[lo, hi])
    R = {(l, g): load_dir(f"{a.base}/real/{l}", l, g, seeds) for l in PREFIX for g in "ABL"}
    C = {(l, g): load_dir(f"{a.base}/committed/{l}", l, g, range(10)) for l in PREFIX for g in "ABL"}
    res["regression"] = {f"{l}|{g}": regression(R[(l, g)], C[(l, g)], l, g) for l in PREFIX for g in "ABL"}
    res["regression_ok"] = all(not v["mismatches"] and v["compared"] > 0 for v in res["regression"].values())
    # pairing check: identical initial sets and held-out slices across learners
    bad = []
    for g in "ABL":
        for s in seeds:
            recs = [R[(l, g)].get(s) for l in PREFIX]
            if all(recs) and any(r["E"] != recs[0]["E"] or r["init"] != recs[0]["init"] for r in recs): bad.append((g, s))
    res["pairing_violations"] = bad
    prim = {}
    for g in "ABL":
        ss, d = contrast(R[("aware", g)], R[("blind", g)], ENDPOINT[g], seeds); prim[g] = (ss, d)
    ph = holm({g: paired_p(prim[g][1]) for g in "ABL"})
    res["primary"] = {g: summarize(f"aware - blind, regime {g}, {ENDPOINT[g]}", prim[g][0], prim[g][1], ph[g]) for g in "ABL"}
    rep = {}
    for g in "ABL":
        ss, d = prim[g]; old_ = np.array([x for s_, x in zip(ss, d) if s_ <= 9]); new_ = np.array([x for s_, x in zip(ss, d) if s_ >= 10])
        rep[g] = dict(n_seeds_0_9=len(old_), n_seeds_10_39=len(new_), mean_0_9=round(float(old_.mean()), 3) if len(old_) else None, mean_10_39=round(float(new_.mean()), 3) if len(new_) else None,
                      t_mean_95_10_39=t_interval(new_) if len(new_) > 1 else None, same_sign=bool(len(old_) and len(new_) and np.sign(old_.mean()) == np.sign(new_.mean())))
    res["replication_seeds_10_39"] = rep
    sec = {}
    for g in "ABL":
        for nm, (x, z) in {"phys-aware": ("phys", "aware"), "phys-blind": ("phys", "blind")}.items():
            sec[(nm, g)] = contrast(R[(x, g)], R[(z, g)], ENDPOINT[g], seeds)
    sh = holm({f"{k[0]}|{k[1]}": paired_p(v[1]) for k, v in sec.items()})
    res["secondary_physchem"] = {f"{k[0]}|{k[1]}": summarize(f"{k[0]}, regime {k[1]}, {ENDPOINT[k[1]]}", v[0], v[1], sh[f"{k[0]}|{k[1]}"]) for k, v in sec.items()}
    res["descriptive_other_arm"] = {}
    for g in "ABL":
        ss, d = contrast(R[("aware", g)], R[("blind", g)], OTHER[g], seeds)
        res["descriptive_other_arm"][g] = dict(arm=OTHER[g], n_seeds=len(ss), mean=round(float(d.mean()), 3) if len(d) else None, t_mean_95=t_interval(d) if len(d) > 1 else None)
        ss, d = contrast(R[("aware", g)], R[("blind", g)], None, seeds, key=lambda r: r.get("auroc_E0"))
        res["descriptive_other_arm"][g]["E_auroc0_aware_minus_blind"] = dict(n_seeds=len(ss), mean=round(float(d.mean()), 4) if len(d) else None, t_mean_95=t_interval(d) if len(d) > 1 else None)
    res["level"] = {f"{l}|{g}": dict(arm=ENDPOINT[g], n=len(R[(l, g)]), mean=round(float(np.mean([hits(r, ENDPOINT[g]) for r in R[(l, g)].values() if hits(r, ENDPOINT[g]) is not None])), 2)) for l in PREFIX for g in "ABL"}
    if not a.no_extras:
        y, thr, srcs = real_y(a.csv)
        res["cluster_source"] = {g: source_cluster(R[("aware", g)], R[("blind", g)], ENDPOINT[g], seeds, y, thr, srcs) for g in "ABL"}
        held = held_out_sets(a.csv, seeds); dl = dict(zip(*[(prim["L"][0]), list(prim["L"][1])]))
        res["regime_L_lab_structure"] = dict(distinct_heldout_sets=len({tuple(h) for h in held.values()}), lab_frequency={k: v for k, v in sorted(collections.Counter(l for h in held.values() for l in h).items(), key=lambda t: -t[1])[:8]},
                                             jackknife_aware_minus_blind=lab_jackknife(dl, held))
    ctl = {}
    for kind in ("chiral", "flat"):
        for g in "AL":
            A_ = load_dir(f"{a.base}/controls/{kind}_aware", "aware", g, range(10)); B_ = load_dir(f"{a.base}/controls/{kind}_blind", "blind", g, range(10)); ss, d = contrast(A_, B_, ENDPOINT[g], range(10))
            if len(d) < 2: ctl[f"{kind}|{g}"] = dict(n_seeds=len(d), outcome="MISSING"); continue
            t95, t90 = t_interval(d, .95), t_interval(d, .90)
            ok = (t95[0] > 0) if kind == "chiral" else (-MARGIN < t90[0] and t90[1] < MARGIN)
            ctl[f"{kind}|{g}"] = dict(n_seeds=len(d), mean=round(float(d.mean()), 2), t_mean_95=t95, t_mean_90=t90, rule=("aware-blind lower 95% bound > 0" if kind == "chiral" else "90% t-interval inside +-10 hits"), passes=bool(ok),
                                      E_auroc0_aware_minus_blind=round(float(np.mean([A_[s]["auroc_E0"] - B_[s]["auroc_E0"] for s in ss])), 4))
    res["planted_controls"] = ctl; res["controls_valid"] = bool(ctl) and all(v.get("passes") for v in ctl.values())
    json.dump(res, open(a.out, "w"), indent=1, default=str); print(json.dumps({k: res[k] for k in ("regression_ok", "pairing_violations", "controls_valid")}), flush=True)


if __name__ == "__main__":
    main()
