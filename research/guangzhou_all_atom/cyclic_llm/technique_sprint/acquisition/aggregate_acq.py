#!/usr/bin/env python3
"""Aggregation and pre-registered decision rules for T2 (docs/20261030_TECHNIQUE_T2_ACQUISITION.md sections 1.6-1.9 and amendment A2).
usage: aggregate_acq.py OUT.json DIR [DIR ...]                  -> decision analysis (inputs from one or more result directories; duplicates are detected, never silently merged)
       aggregate_acq.py --select-config OUT.json DIR [DIR ...]   -> development-seed selection of (lam, cap_src, cap_flat)
Amendment A2 changes: (i) 'every input accounted once' check and duplicate-key detection (review finding on aggregate_l7.load_small); (ii) decision intervals are the CONSERVATIVE union of the
percentile-bootstrap interval and the t interval (n seeds - 1 d.f.), with a sign-flip permutation p reported; (iii) S1 is tested in B, B2 and L with a Bonferroni-adjusted level (1 - 0.01/3);
(iv) regimes A, B, B2, L are primary; C2 is a sensitivity analysis."""
import os, sys, json, glob, collections
import numpy as np
from scipy import stats

BOOT_B, BOOT_SEED, SIGN_SEED = 10000, 20261030, 20261031
BASELINES = ("greedy", "ucb", "rule_phys")
PRIMARY = ("A", "B", "B2", "L")
SHIFT = ("B", "B2", "L")


class AccountingError(RuntimeError):
    pass


def load(dirs):
    """-> (R, manifest). R[(label, regime, seed)] = result. Same key in two files with different content raises; identical content is counted once and recorded as a duplicate."""
    if isinstance(dirs, str): dirs = [dirs]
    R, src, dup = {}, {}, []; found = 0
    for d in dirs:
        for f in sorted(glob.glob(os.path.join(d, "*.json"))):
            found += 1; r = json.load(open(f)); k = (r["label"], r["regime"], r["seed"])
            if k in R:
                if json.dumps(R[k], sort_keys=True) != json.dumps(r, sort_keys=True): raise AccountingError(f"duplicate key {k} with DIFFERENT content: {src[k]} vs {f}")
                dup.append(f); continue
            R[k] = r; src[k] = f
    man = dict(files_found=found, results_used=len(R), identical_duplicates_ignored=len(dup), dirs=list(dirs))
    if found != len(R) + len(dup): raise AccountingError(f"accounting mismatch: {found} files, {len(R)} used, {len(dup)} duplicates")
    return R, man


def arr(R, label, regime, metric, seeds=None):
    """Seeds and values of `metric` for (label, regime); seeds whose result lacks the metric (or has None) are skipped, never silently zero-filled."""
    ss = sorted(s for (l, g, s) in R if l == label and g == regime and R[(l, g, s)].get(metric) is not None) if seeds is None else seeds
    return ss, np.array([R[(label, regime, s)][metric] for s in ss], float)


def boot_ci(d, level=0.99, B=BOOT_B, seed=BOOT_SEED):
    d = np.asarray(d, float); rng = np.random.default_rng(seed); n = len(d); m = d[rng.integers(0, n, (B, n))].mean(1); a = (1 - level) / 2 * 100
    return [float(np.percentile(m, a)), float(np.percentile(m, 100 - a))]


def t_ci(d, level=0.99):
    d = np.asarray(d, float); n = len(d); se = d.std(ddof=1) / np.sqrt(n); q = stats.t.ppf(1 - (1 - level) / 2, n - 1); return [float(d.mean() - q * se), float(d.mean() + q * se)]


def signflip_p(d, B=100000, seed=SIGN_SEED):
    d = np.asarray(d, float); n = len(d); obs = abs(d.mean()); rng = np.random.default_rng(seed)
    if n <= 16:
        import itertools; signs = np.array(list(itertools.product((-1, 1), repeat=n))); return float((np.abs((signs * d).mean(1)) >= obs - 1e-12).mean())
    s = rng.choice((-1, 1), size=(B, n)); return float(((np.abs((s * d).mean(1)) >= obs - 1e-12).sum() + 1) / (B + 1))


def interval(d, level):
    pct, tt = boot_ci(d, level), t_ci(d, level); return dict(level=level, pct=pct, t=tt, conservative=[min(pct[0], tt[0]), max(pct[1], tt[1])], signflip_p=signflip_p(d))


def paired(R, a, b, regime, metric):
    sa, va = arr(R, a, regime, metric); sb, vb = arr(R, b, regime, metric); common = sorted(set(sa) & set(sb)); ia = {s: i for i, s in enumerate(sa)}; ib = {s: i for i, s in enumerate(sb)}
    return common, np.array([va[ia[s]] - vb[ib[s]] for s in common]), (len(sa), len(sb))


def contrast(R, a, b, regime, metric, level=0.99):
    c, d, ns = paired(R, a, b, regime, metric)
    if len(d) < 3: return None
    out = dict(n_paired=len(d), n_a_n_b=list(ns), unpaired_seeds=bool(ns[0] != len(d) or ns[1] != len(d)), mean=float(d.mean()), spread99=[float(np.percentile(d, .5)), float(np.percentile(d, 99.5))])
    out.update(interval(d, level)); return out


def labels_to_x(R, label, regime, X):
    ss, _ = arr(R, label, regime, "hits"); out = []
    for s in ss:
        cum = np.cumsum(R[(label, regime, s)]["rounds"]); k = np.where(cum >= X)[0]
        if len(k): out.append(int((k[0] + 1) * 50))
    return dict(X=X, frac_reached=len(out) / max(len(ss), 1), mean_labels=(float(np.mean(out)) if out else None))


def decide(R, prov="prov", regimes=PRIMARY):
    res = {}; best = {}; lvl_shift = 1 - 0.01 / len(SHIFT)
    for g in regimes:
        means = {b: float(arr(R, b, g, "hits")[1].mean()) for b in BASELINES if arr(R, b, g, "hits")[0]}
        if not means or not arr(R, prov, g, "hits")[0]: continue
        bb = max(means, key=means.get); best[g] = bb
        lvl = lvl_shift if g in SHIFT else 0.99
        c = contrast(R, prov, bb, g, "hits", lvl); c["best_baseline"] = bb; c["best_baseline_mean"] = means[bb]; c["rel_gain"] = c["mean"] / means[bb]; c["rel_ci_conservative"] = [x / means[bb] for x in c["conservative"]]
        res[g] = dict(yield_vs_best=c)
        res[g]["yield_vs_each"] = {b: contrast(R, prov, b, g, "hits", lvl) for b in ("random",) + BASELINES + ("nn_greedy", "fuse", "div") if arr(R, b, g, "hits")[0]}
        res[g]["entropy_vs_greedy"] = contrast(R, prov, "greedy", g, "src_entropy"); res[g]["top_share_vs_greedy"] = contrast(R, prov, "greedy", g, "top_src_share")
        res[g]["flat_entropy_vs_greedy"] = contrast(R, prov, "greedy", g, "flat_entropy"); res[g]["n_flat_vs_greedy"] = contrast(R, prov, "greedy", g, "n_flat")
        if all(("hits_g" in R[(l, g, s)]) for l in (prov, bb) for s in arr(R, l, g, "hits")[0]): res[g]["yield_vs_best_def2"] = contrast(R, prov, bb, g, "hits_g", lvl)
        res[g]["ablations"] = {nm: contrast(R, prov, b, g, "hits") for nm, b in (("prov-fuse", "fuse"), ("prov-div", "div"), ("prov-ucb", "ucb")) if arr(R, b, g, "hits")[0]}
        res[g]["mean_hits"] = {l: float(arr(R, l, g, "hits")[1].mean()) for l in ("random", "greedy", "ucb", "rule_phys", "nn_greedy", "fuse", "div", prov) if arr(R, l, g, "hits")[0]}
        res[g]["labels_to_X"] = {l: [labels_to_x(R, l, g, X) for X in (50, 100, 150)] for l in ("random", "greedy", prov) if arr(R, l, g, "hits")[0]}
        if g == "L" and arr(R, prov, g, "transfer_pooled")[0]:
            res[g]["transfer_pooled_vs_greedy"] = contrast(R, prov, "greedy", g, "transfer_pooled"); res[g]["transfer_per_source_vs_greedy"] = contrast(R, prov, "greedy", g, "transfer_per_source")
    S1 = {g: bool(res[g]["yield_vs_best"]["rel_gain"] >= 0.05 and res[g]["yield_vs_best"]["conservative"][0] > 0) for g in SHIFT if g in res}
    S2 = bool("A" in res and res["A"]["yield_vs_best"]["conservative"][0] >= -0.10 * res["A"]["yield_vs_best"]["best_baseline_mean"])
    S3 = {g: bool(res[g]["entropy_vs_greedy"]["conservative"][0] > 0 and res[g]["top_share_vs_greedy"]["conservative"][1] < 0) for g in regimes if g in res}
    s1 = any(S1.values()); s3 = bool(S3) and all(S3.values())
    verdict = "SUPPORTED" if (s1 and S2 and s3) else ("NULL_KILL (S1 fails in B, B2 and L)" if not s1 else "PARTIAL (S1 holds; " + ", ".join(n for n, ok in (("S2", S2), ("S3", s3)) if not ok) + " fails)")
    return dict(per_regime=res, best_baseline=best, S1_by_regime=S1, S1_any_of_B_B2_L=s1, S1_bonferroni_level=lvl_shift, S2_nonInferior_A=S2, S3_by_regime=S3, S3_all=s3, VERDICT=verdict)


def select_config(R, regimes=("A", "B", "L")):
    """Pre-registered selection (1.6): maximise mean(rel_B, rel_L) subject to rel_A >= 0.90 (rel = mean over dev seeds of hits_prov / hits_greedy); ties by higher mean source entropy."""
    labels = sorted({l for (l, g, s) in R if l.startswith("prov@")}); table = []
    for l in labels:
        row = dict(label=l, cfg=next(r["cfg"] for (ll, g, s), r in R.items() if ll == l))
        for g in regimes:
            seeds = sorted(s for (ll, gg, s) in R if ll == l and gg == g and ("greedy", g, s) in R)
            if not seeds: continue
            row[f"rel_{g}"] = float(np.mean([R[(l, g, s)]["hits"] / max(R[("greedy", g, s)]["hits"], 1) for s in seeds])); row[f"entropy_{g}"] = float(np.mean([R[(l, g, s)]["src_entropy"] for s in seeds])); row["n_seeds"] = len(seeds)
        table.append(row)
    ok = [r for r in table if r.get("rel_A", 0) >= 0.90]; constraint_met = bool(ok); pool = ok if ok else sorted(table, key=lambda r: -r.get("rel_A", 0))[:1]
    key = (lambda r: (np.mean([r["rel_B"], r["rel_L"]]), np.mean([r[f"entropy_{g}"] for g in regimes]))) if ok else (lambda r: (r.get("rel_A", 0), 0))
    best = max(pool, key=key)
    return dict(config=best["cfg"], constraint_rel_A_ge_0p90_met=constraint_met, selected_label=best["label"], dev_table=table)


if __name__ == "__main__":
    if sys.argv[1] == "--select-config": R, man = load(sys.argv[3:]); out = select_config(R); out["accounting"] = man; json.dump(out, open(sys.argv[2], "w"), indent=1)
    else: R, man = load(sys.argv[2:]); out = decide(R); out["accounting"] = man; json.dump(out, open(sys.argv[1], "w"), indent=1)
    print(json.dumps({k: v for k, v in out.items() if k not in ("per_regime", "dev_table")}, indent=1))
