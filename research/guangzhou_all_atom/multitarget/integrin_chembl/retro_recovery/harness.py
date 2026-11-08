"""Generic evaluation harness for the multi-target retrospective recovery study (PREREG §5, §9, A2/A3).

A scorer is anything that yields (compound_id, score) -- optionally (target_key, compound_id, score) for target-conditioned scorers.
  python harness.py --items M --scores my_scores.csv --name atom_lm_v1      # workstream-1 plug-in (S3)
Metrics per target: AUROC (tie-aware) and EF at top 5 % (tie-aware, expected value under random tie-breaking).
Aggregation: mean over targets within a family, then mean over families (each family counts once); 95 % family-cluster bootstrap (B=2000).
Decision (PREREG §5): arm is 'supported' only if the lower 95 % bound of (arm - strongest baseline) > 0 on the pooled analysis
(strongest baseline = highest point estimate among all baselines, chosen on the same data = conservative).
"""
import argparse, json, math, os
import numpy as np, pandas as pd

HERE = os.path.dirname(os.path.abspath(__file__)); DATA = f"{HERE}/data"
B = 2000


def tie_aware_auc(y, s):
    y = np.asarray(y, int); s = np.asarray(s, float)
    n1 = y.sum(); n0 = len(y) - n1
    if n1 == 0 or n0 == 0:
        return float("nan")
    r = pd.Series(s).rank(method="average").values
    return float((r[y == 1].sum() - n1 * (n1 + 1) / 2) / (n1 * n0))


def tie_aware_ef(y, s, frac=0.05):
    """EF = (expected positives in top ceil(frac*n)) / (n1 * k/n) where ties straddling the cut contribute proportionally."""
    y = np.asarray(y, int); s = np.asarray(s, float); n = len(y); n1 = y.sum()
    if n1 == 0 or n1 == n:
        return float("nan")
    k = max(1, int(math.ceil(frac * n)))
    order = np.argsort(-s, kind="stable"); ss = s[order]; yy = y[order]
    cut = ss[k - 1]
    above = ss > cut; tie = ss == cut
    pos_above = yy[above].sum(); n_above = above.sum()
    need = k - n_above; pos_tie = yy[tie].sum(); n_tie = tie.sum()
    exp_pos = pos_above + (pos_tie * need / n_tie if n_tie else 0)
    return float((exp_pos / k) / (n1 / n))


def per_target(items, scores):
    """items: DataFrame(target_key, compound_id, label); scores: DataFrame(compound_id[, target_key], score) -> DataFrame per target."""
    if "target_key" in scores.columns:
        m = items.merge(scores[["target_key", "compound_id", "score"]], on=["target_key", "compound_id"], how="left")
    else:
        m = items.merge(scores[["compound_id", "score"]].drop_duplicates("compound_id"), on="compound_id", how="left")
    cov = float(m.score.notna().mean())
    m["score"] = m.score.fillna(m.score.min() - 1 if m.score.notna().any() else 0.0)   # unscored items rank last (reported via coverage)
    rows = []
    for t, g in m.groupby("target_key", sort=True):
        rows.append(dict(target_key=t, auc=tie_aware_auc(g.label.values, g.score.values), ef5=tie_aware_ef(g.label.values, g.score.values), n=len(g), n_pos=int(g.label.sum())))
    return pd.DataFrame(rows), cov


def family_means(pt, tfam, metric):
    d = pt.merge(tfam, on="target_key"); d = d[d[metric].notna()]
    return d.groupby("family")[metric].mean()


def boot_diff(fm_a, fm_b, B=B, seed=11):
    fams = sorted(set(fm_a.index) & set(fm_b.index)); a = fm_a.loc[fams].values; b = fm_b.loc[fams].values
    rng = np.random.default_rng(seed); n = len(fams)
    idx = rng.integers(0, n, (B, n))
    d = (a[idx].mean(1) - b[idx].mean(1))
    return dict(point=float(a.mean() - b.mean()), lo=float(np.percentile(d, 2.5)), hi=float(np.percentile(d, 97.5)), n_families=n)


def boot_mean(fm, B=B, seed=11):
    v = fm.values; rng = np.random.default_rng(seed); idx = rng.integers(0, len(v), (B, len(v))); m = v[idx].mean(1)
    return dict(point=float(v.mean()), lo=float(np.percentile(m, 2.5)), hi=float(np.percentile(m, 97.5)), n_families=len(v))


def load(which):
    items = pd.read_csv(f"{DATA}/items_{which}.csv.gz"); T = pd.read_csv(f"{DATA}/targets.csv")
    return items, T[["target_key", "family", "genes"]]


def evaluate(items, tfam, arm_scores: dict, baseline_names, primary="auc", subset=None):
    """arm_scores: name -> scores DataFrame. Returns dict name -> metrics, plus decision vs strongest baseline."""
    if subset is not None:
        items = items[items.target_key.isin(subset)]
        tfam = tfam[tfam.target_key.isin(subset)]
    res = {}; fms = {}
    for name, sc in arm_scores.items():
        pt, cov = per_target(items, sc); fms[(name, "auc")] = family_means(pt, tfam, "auc"); fms[(name, "ef5")] = family_means(pt, tfam, "ef5")
        res[name] = dict(coverage=cov, auc=boot_mean(fms[(name, "auc")]), ef5=boot_mean(fms[(name, "ef5")]), n_targets=int(pt.target_key.nunique()))
    base = [b for b in baseline_names if b in arm_scores]
    out = dict(arms=res)
    for metric in ("auc", "ef5"):
        strongest = max(base, key=lambda b: res[b][metric]["point"])
        out[f"strongest_baseline_{metric}"] = strongest
        for name in arm_scores:
            if name in base:
                continue
            d = boot_diff(fms[(name, metric)], fms[(strongest, metric)])
            d["verdict"] = "SUPPORTED" if d["lo"] > 0 else ("NOT_SUPPORTED" if d["hi"] <= 0 else "INCONCLUSIVE")
            out.setdefault(f"vs_strongest_{metric}", {})[name] = d
    return out


if __name__ == "__main__":
    ap = argparse.ArgumentParser(); ap.add_argument("--items", choices=["M", "I"], required=True); ap.add_argument("--scores", required=True); ap.add_argument("--name", default="plugin")
    ap.add_argument("--baselines", default=f"{DATA}/baseline_scores_{{items}}.csv.gz"); ap.add_argument("--out", default=None)
    a = ap.parse_args()
    items, tfam = load(a.items)
    sc = pd.read_csv(a.scores); arms = {a.name: sc}
    bl = pd.read_csv(a.baselines.format(items=a.items)); names = []
    for n, g in bl.groupby("arm"):
        arms[n] = g[[c for c in ("target_key", "compound_id", "score") if c in g.columns]]; names.append(n)
    out = evaluate(items, tfam, arms, names)
    print(json.dumps(out, indent=1))
    if a.out: json.dump(out, open(a.out, "w"), indent=1)
