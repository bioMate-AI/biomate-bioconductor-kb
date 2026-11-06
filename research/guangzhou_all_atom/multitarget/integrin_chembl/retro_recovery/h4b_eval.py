"""H4b plug-in evaluation (PREREG A8): `run_s3.py --name X --k K --scores f.csv` where f.csv = (target_key, compound_id, score[, seed]) over the remaining items of
data/h4b_reveals.csv.gz for that k (and seed). Per-target AUROC/EF5/top-10 precision on the same remaining items as the baselines (revealed compounds and their flat siblings
removed; only eligible (target,k,seed) cells), mean over seeds, family mean, family-cluster bootstrap; compared with the baseline arms at the same k
(results/h4b_per_target.csv) and with the arm's own k=0 value if a k=0 file is supplied separately (--k 0). Contamination-controlled subset reported side by side."""
import json, os, sys
import numpy as np, pandas as pd
HERE = os.path.dirname(os.path.abspath(__file__)); DATA = f"{HERE}/data"; RES = f"{HERE}/results"; sys.path.insert(0, HERE)
import harness as H


def main(a):
    sc = pd.read_csv(a.scores); T = pd.read_csv(f"{DATA}/targets.csv"); tf = T[["target_key", "family"]]; I = pd.read_csv(f"{DATA}/items_I.csv.gz"); C = pd.read_csv(f"{DATA}/compounds.csv.gz").set_index("compound_id")
    R = pd.read_csv(f"{DATA}/h4b_reveals.csv.gz"); E = pd.read_csv(f"{DATA}/h4b_eligible.csv"); cf = pd.read_csv(f"{DATA}/contamination_flags.csv.gz").set_index("compound_id")
    seeds = sorted(sc.seed.unique()) if "seed" in sc.columns else (range(5) if a.k else [0]); rows = {"all": [], "ctrl": []}
    for t, g in I.groupby("target_key"):
        for s in (seeds if a.k else [0]):
            if a.k:
                if not E[(E.target_key == t) & (E.k == a.k) & (E.seed == s)].eligible.iloc[0]: continue
                rv = R[(R.target_key == t) & (R.k == a.k) & (R.seed == s)]; fl = set(rv.compound_id.map(C.flat_key)); rest = g[~g.compound_id.isin(rv.compound_id) & ~g.compound_id.map(C.flat_key).isin(fl)]
            else: rest = g
            m = rest.merge((sc[sc.seed == s] if "seed" in sc.columns else sc)[["target_key", "compound_id", "score"]], on=["target_key", "compound_id"], how="inner")
            for tag, d in (("all", m), ("ctrl", m[~m.compound_id.map(cf.in_atomlm_pretrain_corpus).fillna(False) & ~m.compound_id.map(cf.in_cycpeptmpdb).fillna(False)])):
                if d.label.nunique() == 2 and len(d) >= 20:
                    o = np.argsort(-d.score.values, kind="stable"); v = d.score.values[o]; yy = d.label.values[o]; cut = v[9]; ab = v > cut; ti = v == cut
                    p10 = (yy[ab].sum() + (yy[ti].sum() * (10 - ab.sum()) / ti.sum() if ti.sum() else 0)) / 10
                    rows[tag].append(dict(target_key=t, seed=s, auc=H.tie_aware_auc(d.label.values, d.score.values), ef5=H.tie_aware_ef(d.label.values, d.score.values), p10=float(p10), cov=len(d) / len(rest)))
    out = dict(name=a.name, k=a.k, scores_file=os.path.basename(a.scores)); base = pd.read_csv(f"{RES}/h4b_per_target.csv"); base = base[base.k == a.k]
    for tag in ("all", "ctrl"):
        if not rows[tag]: out[tag] = "no evaluable targets"; continue
        pt = pd.DataFrame(rows[tag]).groupby("target_key")[["auc", "ef5", "p10", "cov"]].mean().reset_index(); fm = {m: pt.merge(tf, on="target_key").groupby("family")[m].mean() for m in ("auc", "ef5", "p10")}
        r = dict(targets=int(len(pt)), families=int(len(fm["auc"])), coverage_mean=round(float(pt["cov"].mean()), 3), **{m: H.boot_mean(fm[m], B=2000) for m in ("auc", "ef5", "p10")}, vs_baselines={})
        for arm, bg in base.groupby("arm"):
            b = bg[bg.target_key.isin(pt.target_key)].groupby("target_key")[["auc"]].mean().reset_index().merge(tf, on="target_key").groupby("family").auc.mean()
            if len(b) >= 2: r["vs_baselines"][arm] = H.boot_diff(fm["auc"], b, B=2000)
        out[tag] = r
    fn = f"{RES}/h4b_{a.name}_k{a.k}.json"; json.dump(out, open(fn, "w"), indent=1); print(json.dumps(out, indent=1)[:2500]); print("wrote", fn)
