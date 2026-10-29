#!/usr/bin/env python3
"""T-LADDER aggregator (pre-registration docs/20261030_IHLM_LADDER_PREREG.md sections 6-7, amendment A2). Torch-free.
usage: aggregate_ladder.py RESULTS_DIR [--out docs/...md] [--json out.json] [--planted R1,R2,R3,R4]
Metric Y = total hits over the 10 x 50 selections; E = AUROC / EF5 on the held-out slice after the final round.
Intervals (typed): (a) percentile spread of per-seed paired differences; (b) bootstrap CI of the mean (10,000 resamples); (c) t-interval over seeds; (d) regime L, E-AUROC only: held-out-lab cluster bootstrap.
Decision interval = the WIDER of (b) and (c). Primary family (Holm, size 8): {R1-R0, R2-R1, R3-R2, R4-R3} x Y x {B, L}. Everything else is exploratory (BH reported, never confirmatory).
A module 'adds' only if ALL of: Holm-rejected positive in both B and L; its planted test passed; controls inside the equivalence margins; the same sign under the zt control (all five rungs, seeds 0-4, amendment A2)."""
import os, sys, json, glob, argparse, itertools
import numpy as np
from scipy import stats
from scipy.stats import rankdata

MODS = (("R1", "R0", "M1 knowledge prior"), ("R2", "R1", "M2 lab offset"), ("R3", "R2", "M3 symbolic analog retrieval"), ("R4", "R3", "M4 edit-space layer"))
MARGIN_Y, MARGIN_AUC = 10.0, 0.05
NBOOT = 10000


def load_dir(d):
    rows = []
    for f in sorted(glob.glob(os.path.join(d, "ladder_*.json"))):
        try: rows.append(json.load(open(f)))
        except Exception: pass
    return rows


def total_hits(rec): return int(sum(rec["hits"]))


def metric(rec, m):
    return {"Y": total_hits, "AUROC": lambda r: r["auroc_E"], "EF5": lambda r: r["ef5_E"]}[m](rec)


def table(rows):
    """{(regime, scheme, k): {arm: {seed: rec}}}"""
    t = {}
    for r in rows:
        for arm, rec in r["arms"].items(): t.setdefault((r["regime"], r["scheme"], r["k_anchor"]), {}).setdefault(arm, {})[r["seed"]] = rec
    return t


def paired(T, key, a, b, m):
    A, B = T.get(key, {}).get(a, {}), T.get(key, {}).get(b, {}); seeds = sorted(set(A) & set(B))
    d = np.array([metric(A[s], m) - metric(B[s], m) for s in seeds], float); ok = np.isfinite(d); return np.array(seeds)[ok], d[ok]


def intervals(d, rng, nboot=NBOOT):
    n = len(d)
    if n < 3: return dict(n=n, mean=float(d.mean()) if n else float("nan"), sd=float(d.std(ddof=1)) if n > 1 else float("nan"), insufficient=True)
    mean = float(d.mean()); sd = float(d.std(ddof=1)); bm = rng.choice(d, (nboot, n), replace=True).mean(1)
    tcrit = stats.t.ppf(0.975, n - 1); tci = (mean - tcrit * sd / np.sqrt(n), mean + tcrit * sd / np.sqrt(n)); bci = tuple(np.percentile(bm, [2.5, 97.5])); pct = tuple(np.percentile(d, [2.5, 97.5]))
    pt = float(stats.ttest_1samp(d, 0.0).pvalue) if sd > 0 else (1.0 if mean == 0 else 0.0)
    pb = min(1.0, 2 * min((np.sum(bm <= 0) + 1) / (nboot + 1), (np.sum(bm >= 0) + 1) / (nboot + 1)))
    wide = (min(bci[0], tci[0]), max(bci[1], tci[1])); p = max(pt, pb)           # wider interval <-> the larger p
    return dict(n=n, mean=mean, sd=sd, pct_spread=[float(x) for x in pct], boot_ci=[float(x) for x in bci], t_ci=[float(x) for x in tci], wide_ci=[float(x) for x in wide], p_t=pt, p_boot=float(pb), p=float(p),
                mdd=float(sd * 2.8 / np.sqrt(n)), insufficient=False)


def holm(ps):
    order = np.argsort(ps); m = len(ps); adj = np.empty(m); run = 0.0
    for rank, i in enumerate(order): run = max(run, min(1.0, (m - rank) * ps[i])); adj[i] = run
    return adj


def bh(ps):
    ps = np.asarray(ps, float); m = len(ps); order = np.argsort(ps); adj = np.empty(m); prev = 1.0
    for rank in range(m - 1, -1, -1): i = order[rank]; prev = min(prev, ps[i] * m / (rank + 1)); adj[i] = prev
    return adj


def auc(score, hit):
    hit = np.asarray(hit, bool); npos, nneg = int(hit.sum()), int((~hit).sum())
    if npos == 0 or nneg == 0: return float("nan")
    return float((rankdata(score)[hit].sum() - npos * (npos + 1) / 2) / (npos * nneg))


def lab_cluster_auroc(rows, a, b, rng, scheme="zc", k=5, nboot=1000):
    """(d) regime L: per seed resample the held-out labs of E with replacement (same resample for both arms), mean over seeds of AUROC(a)-AUROC(b); percentile CI."""
    use = [r for r in rows if r["regime"] == "L" and r["scheme"] == scheme and r["k_anchor"] == k and a in r["arms"] and b in r["arms"]]
    if len(use) < 3: return None
    prep = []
    for r in use:
        src = np.array(r["E_src"]); hit = np.array(r["E_hit"], bool); sa = np.array(r["arms"][a]["E_score_final"]); sb = np.array(r["arms"][b]["E_score_final"]); labs = sorted(set(src)); prep.append((src, hit, sa, sb, labs, [np.where(src == l)[0] for l in labs]))
    est = []
    for _ in range(nboot):
        ds = []
        for src, hit, sa, sb, labs, ix in prep:
            pick = rng.integers(0, len(labs), len(labs)); sel = np.concatenate([ix[j] for j in pick]); x, y_, h = sa[sel], sb[sel], hit[sel]; da = auc(x, h) - auc(y_, h)
            if np.isfinite(da): ds.append(da)
        if ds: est.append(np.mean(ds))
    return dict(n_seeds=len(use), n_labs=[len(p[4]) for p in prep], ci=[float(x) for x in np.percentile(est, [2.5, 97.5])], mean=float(np.mean([auc(p[2], p[1]) - auc(p[3], p[1]) for p in prep]))) if est else None


def run(rows, planted=None, seed=20261030):
    rng = np.random.default_rng(seed); T = table(rows); out = dict(n_files=len(rows), keys=[list(k) for k in sorted(T)], primary=[], exploratory=[], controls=[], modules=[], cluster=[])
    prim_keys = [("B", "zc", 5), ("L", "zc", 5)]
    prim = []
    for new, old, name in MODS:
        for reg in ("B", "L"):
            seeds, dd = paired(T, (reg, "zc", 5), new, old, "Y"); iv = intervals(dd, rng); prim.append(dict(contrast=f"{new}-{old}", module=name, regime=reg, metric="Y", seeds=[int(s) for s in seeds], **iv))
    ps = np.array([p["p"] if not p["insufficient"] else 1.0 for p in prim]); adj = holm(ps)
    for p, a in zip(prim, adj): p["holm_p"] = float(a); p["positive_holm"] = bool((not p["insufficient"]) and a < 0.05 and p["wide_ci"][0] > 0 * 1 and p["mean"] > 0) if not p["insufficient"] else False
    out["primary"] = prim
    expl = []
    contrasts = [(f"{n}-{o}", n, o) for n, o, _ in MODS] + [("R4-gbm_aware", "R4", "gbm_aware"), ("R4-knn", "R4", "knn"), ("R4-gp", "R4", "gp"), ("R4-random_fb", "R4", "random_fb"), ("R4-rule_kphys", "R4", "rule_kphys"), ("R1-R1_kshuf", "R1", "R1_kshuf"), ("R4-R4_shuf", "R4", "R4_shuf"), ("R4-R0", "R4", "R0"), ("R4-R4_frozen", "R4", "R4_frozen")]
    for label, a, b in contrasts:
        for reg in ("A", "B", "L"):
            for m in ("Y", "AUROC"):
                if (label.split("-")[0] + "-" + label.split("-")[1] in [f"{n}-{o}" for n, o, _ in MODS]) and reg in ("B", "L") and m == "Y": continue          # already primary
                seeds, dd = paired(T, (reg, "zc", 5), a, b, m)
                if len(dd): expl.append(dict(contrast=label, regime=reg, metric=m, seeds=[int(s) for s in seeds], **intervals(dd, rng)))
    ok = [e for e in expl if not e["insufficient"]]; q = bh([e["p"] for e in ok]) if ok else []
    for e, v in zip(ok, q): e["bh_q"] = float(v)
    out["exploratory"] = expl
    for scheme in ("gc", "zt"):
        for reg in "ABL":
            key = (reg, scheme, 5)
            if key not in T: continue
            for label, a, b in contrasts[:4] + [("R4-R0", "R4", "R0")]:
                seeds, dd = paired(T, key, a, b, "Y")
                if len(dd): out["exploratory"].append(dict(contrast=label, regime=reg, metric="Y", scheme=scheme, seeds=[int(s) for s in seeds], **intervals(dd, rng)))
    for k_ in sorted({k[2] for k in T}):
        if k_ == 5: continue
        for reg in "ABL":
            for label, a, b in (("R2-R1", "R2", "R1"),):
                seeds, dd = paired(T, (reg, "zc", k_), a, b, "Y")
                if len(dd): out["exploratory"].append(dict(contrast=label, regime=reg, metric="Y", k_anchor=k_, seeds=[int(s) for s in seeds], **intervals(dd, rng)))
    for reg in ("B", "L", "A"):
        for lab, a, b, gate in (("R4_shuf-random_fb", "R4_shuf", "random_fb", True), ("R1_kshuf-R0", "R1_kshuf", "R0", True), ("R1-R1_kshuf (K content contrast; 'no attributable content effect' if inside the margin)", "R1", "R1_kshuf", False)):
            for m, mg in (("Y", MARGIN_Y), ("AUROC", MARGIN_AUC)):
                seeds, dd = paired(T, (reg, "zc", 5), a, b, m)
                if len(dd) >= 3:
                    iv = intervals(dd, rng); lo, hi = iv["wide_ci"]; out["controls"].append(dict(control=lab, regime=reg, metric=m, margin=mg, wide_ci=iv["wide_ci"], mean=iv["mean"], n=iv["n"], within_margin=bool(lo >= -mg and hi <= mg), mdd=iv["mdd"], gate=gate))
    for a, b in (("R4", "R3"), ("R4", "R0"), ("R4", "gbm_aware"), ("R4", "knn")):
        r = lab_cluster_auroc(rows, a, b, rng)
        if r: out["cluster"].append(dict(contrast=f"{a}-{b}", regime="L", metric="AUROC", type="d: held-out-lab cluster bootstrap", **r))
    out["r4_vs_r3_identical"] = []
    for reg in "ABL":
        use = [r for r in rows if r["regime"] == reg and r["scheme"] == "zc" and r["k_anchor"] == 5 and "R3" in r["arms"] and "R4" in r["arms"]]
        if use: out["r4_vs_r3_identical"].append(dict(regime=reg, tasks=len(use), identical_picks=int(sum(("picks" in r["arms"]["R3"]) and r["arms"]["R3"]["picks"] == r["arms"]["R4"].get("picks") for r in use)), identical_hits=int(sum(r["arms"]["R3"]["hits"] == r["arms"]["R4"]["hits"] for r in use))))
    for reg in ("B", "L", "A"):
        for lab, a_, b_ in (("R4_shuf-rule_kphys (POST-HOC diagnostic: shuffled-label arm vs the label-free K rule)", "R4_shuf", "rule_kphys"), ("R4_shuf-R1_kshuf (POST-HOC diagnostic)", "R4_shuf", "R1_kshuf")):
            seeds, dd = paired(T, (reg, "zc", 5), a_, b_, "Y")
            if len(dd) >= 3: iv = intervals(dd, rng); out["controls"].append(dict(control=lab, regime=reg, metric="Y", margin=MARGIN_Y, wide_ci=iv["wide_ci"], mean=iv["mean"], n=iv["n"], within_margin=bool(iv["wide_ci"][0] >= -MARGIN_Y and iv["wide_ci"][1] <= MARGIN_Y), mdd=iv["mdd"], gate=False))
    ctrl_ok = {reg: all(c["within_margin"] for c in out["controls"] if c["regime"] == reg and c["metric"] == "Y" and c["gate"]) for reg in ("B", "L") if any(c["regime"] == reg and c["gate"] for c in out["controls"])}
    have_zt = {k[0] for k in T if k[1] == "zt"}
    for new, old, name in MODS:
        cells = {p["regime"]: p for p in prim if p["contrast"] == f"{new}-{old}"}; crit = {}
        crit["holm_positive_B_and_L"] = bool(cells["B"].get("positive_holm") and cells["L"].get("positive_holm"))
        crit["planted_test_passed"] = None if planted is None else (new in planted)
        crit["controls_inside_margin_B_and_L"] = bool(ctrl_ok.get("B") and ctrl_ok.get("L")) if ctrl_ok else None
        zt_ok = None
        if {"B", "L"} <= have_zt:                       # A2: zt control runs all five rungs on seeds 0-4; the contrast must keep its sign on THOSE seeds
            def sg(scheme, reg, seeds_only=None):
                sd_, dd_ = paired(T, (reg, scheme, 5), new, old, "Y")
                if seeds_only is not None: dd_ = dd_[np.isin(sd_, list(seeds_only))]
                return np.sign(dd_.mean()) if len(dd_) else np.nan
            zt_seeds = {r["seed"] for r in rows if r["scheme"] == "zt"}
            zt_ok = bool(all(np.isfinite(sg("zt", reg)) and sg("zt", reg) == sg("zc", reg, zt_seeds) for reg in ("B", "L")))
        crit["same_sign_under_zt"] = zt_ok
        status = "adds" if all(v is True for v in crit.values()) else ("not detected" if crit["holm_positive_B_and_L"] is False and all(v is not False for k, v in crit.items() if k != "holm_positive_B_and_L") else "not claimed")
        out["modules"].append(dict(module=name, contrast=f"{new}-{old}", criteria=crit, status=status, note="criterion None = not assessable from the files given (never counted as met)"))
    return out


def fmt_iv(e):
    if e.get("insufficient"): return f"n={e['n']} (insufficient)"
    return f"{e['mean']:+.2f} [{e['wide_ci'][0]:+.2f}, {e['wide_ci'][1]:+.2f}]"


def to_markdown(res):
    L_ = ["### Primary family (Holm, size 8; metric Y = hits of 500; causal source-standardised labels `zc`, k = 5 anchors)", "", "| contrast | module | regime | n seeds | mean paired diff [wider of (b) bootstrap, (c) t] | (a) percentile spread | MDD | Holm p | positive after Holm |", "|---|---|---|---|---|---|---|---|---|"]
    for p in res["primary"]:
        if p.get("insufficient"): L_.append(f"| {p['contrast']} | {p['module']} | {p['regime']} | {p['n']} | insufficient | | | | no |"); continue
        L_.append(f"| {p['contrast']} | {p['module']} | {p['regime']} | {p['n']} | {fmt_iv(p)} | [{p['pct_spread'][0]:+.1f}, {p['pct_spread'][1]:+.1f}] | {p['mdd']:.1f} | {p['holm_p']:.3f} | {'yes' if p['positive_holm'] else 'no'} |")
    L_ += ["", "### Module claims (all criteria must be met)", "", "| module | status | criteria |", "|---|---|---|"]
    for m in res["modules"]: L_.append(f"| {m['module']} ({m['contrast']}) | **{m['status']}** | " + "; ".join(f"{k}={v}" for k, v in m["criteria"].items()) + " |")
    L_ += ["", "### Controls (equivalence margins: shuffled-label gain within ±10 hits / ±0.05 AUROC; wider interval inside the margin = inside)", "", "| control | regime | metric | mean [wider CI] | margin | inside | MDD | gate |", "|---|---|---|---|---|---|---|---|"]
    for c in res["controls"]: L_.append(f"| {c['control']} | {c['regime']} | {c['metric']} | {c['mean']:+.3f} [{c['wide_ci'][0]:+.3f}, {c['wide_ci'][1]:+.3f}] | ±{c['margin']} | {'yes' if c['within_margin'] else 'NO'} | {c['mdd']:.2f} | {'gate' if c['gate'] else 'report'} |")
    L_ += ["", "### Exploratory contrasts (BH q within the zc/k=5 set; not confirmatory)", "", "| contrast | regime | metric | scheme / k | n | mean [wider CI] | BH q |", "|---|---|---|---|---|---|---|"]
    for e in res["exploratory"]:
        sk = e.get("scheme", "zc") + (f"/k{e['k_anchor']}" if "k_anchor" in e else "/k5"); L_.append(f"| {e['contrast']} | {e['regime']} | {e['metric']} | {sk} | {e['n']} | {fmt_iv(e)} | {e.get('bh_q', float('nan')):.3f} |")
    if res.get("r4_vs_r3_identical"):
        L_ += ["", "### How often is R4 exactly R3 on the real data? (zc, k = 5; identical = every round's 50 picks identical)", "", "| regime | tasks | identical picks | identical hit counts |", "|---|---|---|---|"]
        for x in res["r4_vs_r3_identical"]: L_.append(f"| {x['regime']} | {x['tasks']} | {x['identical_picks']} | {x['identical_hits']} |")
    if res["cluster"]:
        L_ += ["", "### (d) regime L, E-AUROC, held-out-lab cluster bootstrap (per seed resample of held-out labs; 1,000 resamples)", "", "| contrast | seeds | labs per seed | mean | 95% percentile CI |", "|---|---|---|---|---|"]
        for c in res["cluster"]: L_.append(f"| {c['contrast']} | {c['n_seeds']} | {min(c['n_labs'])}-{max(c['n_labs'])} | {c['mean']:+.3f} | [{c['ci'][0]:+.3f}, {c['ci'][1]:+.3f}] |")
    return "\n".join(L_)


def main():
    ap = argparse.ArgumentParser(); ap.add_argument("dir"); ap.add_argument("--json"); ap.add_argument("--md"); ap.add_argument("--planted", default=None); a = ap.parse_args()
    rows = load_dir(a.dir); res = run(rows, None if a.planted is None else set(a.planted.split(","))); md = to_markdown(res)
    if a.json: json.dump(res, open(a.json, "w"), indent=1, default=float)
    if a.md: open(a.md, "w").write(md + "\n")
    print(md)


if __name__ == "__main__":
    main()
