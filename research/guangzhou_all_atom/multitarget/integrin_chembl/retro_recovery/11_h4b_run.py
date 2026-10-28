"""H4b step 2 (PREREG A8): baselines R, NN, FP-k, PT, PT+k on the frozen reveal sets; metrics per target -> family mean -> family-cluster bootstrap.
Writes results/h4b_baselines.json and data/h4b_scores_baselines.csv.gz (target,k,seed,arm,compound_id,score) so LLM score files can be compared on identical items."""
import os, sys, json, copy, multiprocessing as mp
import numpy as np, pandas as pd
from rdkit import Chem, RDLogger
from rdkit.Chem import AllChem
from sklearn.linear_model import LogisticRegression
RDLogger.DisableLog("rdApp.*")
HERE = os.path.dirname(os.path.abspath(__file__)); DATA = f"{HERE}/data"; RES = f"{HERE}/results"; sys.path.insert(0, HERE)
import harness as H
KS = [0, 5, 10, 25]; SEEDS = range(5); SMOKE = os.environ.get("RETRO_SMOKE") == "1"
C = pd.read_csv(f"{DATA}/compounds.csv.gz").set_index("compound_id"); P = pd.read_csv(f"{DATA}/pair_labels.csv.gz"); T = pd.read_csv(f"{DATA}/targets.csv"); fam = dict(zip(T.target_key, T.family))
fo = pd.read_csv(f"{DATA}/folds_v1.csv"); fold = dict(zip(fo.family, fo.fold)); I = pd.read_csv(f"{DATA}/items_I.csv.gz"); R = pd.read_csv(f"{DATA}/h4b_reveals.csv.gz"); E = pd.read_csv(f"{DATA}/h4b_eligible.csv")
if SMOKE: I = I[I.target_key.isin(sorted(I.target_key.unique())[:4])]
ids = sorted(set(P.compound_id) | set(I.compound_id)); gen_b = AllChem.GetMorganGenerator(radius=2, fpSize=2048, includeChirality=True); gen_c = AllChem.GetMorganGenerator(radius=2, fpSize=1024, includeChirality=True)
mols = {c: Chem.MolFromSmiles(C.loc[c, "iso_smiles"]) for c in ids}
BIT = {c: gen_b.GetFingerprintAsNumPy(m).astype(np.float32) for c, m in mols.items()}; CNT = {c: np.log1p(gen_c.GetCountFingerprintAsNumPy(m).astype(np.float32)) for c, m in mols.items()}
bitm = {c: i for i, c in enumerate(ids)}; BM = np.stack([BIT[c] for c in ids]); bs = BM.sum(1)
flat = C.flat_key.to_dict(); lab = P.assign(fold=P.target_key.map(fam).map(fold), y=(P.label == "pos").astype(int))
PT = {}                                                      # per fold pretrained model on OTHER-fold labelled pairs, flat-identical-to-held-out compounds removed (blind rule)
for f in sorted(set(I.target_key.map(fam).map(fold))):
    held = set(flat[c] for c in lab[lab.fold == f].compound_id); tr = lab[(lab.fold != f) & ~lab.compound_id.map(flat).isin(held)]
    X = np.stack([CNT[c] for c in tr.compound_id]); lr = LogisticRegression(C=0.05, max_iter=300).fit(X, tr.y.values); PT[f] = (lr, X, tr.y.values)


def tan(ia, ib): inter = BM[ia] @ BM[ib].T; return inter / (bs[ia][:, None] + bs[ib][None, :] - inter + 1e-9)


def one_target(t):
    g = I[I.target_key == t]; f = fold[fam[t]]; out = []; lr0, Xtr, ytr = PT[f]
    for k in KS:
        for s in (SEEDS if k else [0]):
            if k:
                rv = R[(R.target_key == t) & (R.k == k) & (R.seed == s)]; fl = set(flat[c] for c in rv.compound_id)
                rest = g[~g.compound_id.isin(rv.compound_id) & ~g.compound_id.map(flat).isin(fl)]
                e = E[(E.target_key == t) & (E.k == k) & (E.seed == s)].eligible.iloc[0]
                if not e: continue
            else:
                rv = R.iloc[:0]; rest = g
            cid = rest.compound_id.values; Xr = np.stack([CNT[c] for c in cid]); sc = {}
            rng = np.random.default_rng(1000 * k + s + len(t)); sc["R"] = rng.random(len(cid))
            sc["PT"] = lr0.decision_function(Xr)
            if k:
                rp = [c for c, l in zip(rv.compound_id, rv.label) if l == 1]; rn = [c for c, l in zip(rv.compound_id, rv.label) if l == 0]; ii = np.array([bitm[c] for c in cid])
                sp = tan(ii, np.array([bitm[c] for c in rp])).max(1) if rp else np.zeros(len(cid)); sn = tan(ii, np.array([bitm[c] for c in rn])).max(1) if rn else np.zeros(len(cid)); sc["NN"] = sp - sn
                if len(rp) and len(rn) and k >= 5:
                    lk = LogisticRegression(C=0.5, max_iter=300).fit(np.stack([CNT[c] for c in rv.compound_id]), rv.label.values); sc["FP-k"] = lk.decision_function(Xr)
                else: sc["FP-k"] = np.zeros(len(cid))
                m = copy.deepcopy(lr0); m.set_params(warm_start=True, max_iter=2000)
                m.fit(np.vstack([Xtr, np.stack([CNT[c] for c in rv.compound_id])]), np.concatenate([ytr, rv.label.values]), sample_weight=np.concatenate([np.ones(len(ytr)), np.full(len(rv), 20.0)])); sc["PT+k"] = m.decision_function(Xr)
            y = rest.label.values
            for arm, v in sc.items():
                n = len(y); kk = 10; order = np.argsort(-v, kind="stable"); vs = v[order]; yy = y[order]; cut = vs[kk - 1]; above = vs > cut; tie = vs == cut
                p10 = (yy[above].sum() + (yy[tie].sum() * (kk - above.sum()) / tie.sum() if tie.sum() else 0)) / kk
                out.append(dict(target_key=t, k=k, seed=s, arm=arm, auc=H.tie_aware_auc(y, v), ef5=H.tie_aware_ef(y, v), p10=float(p10), n=n, n_pos=int(y.sum())))
    return out


if __name__ == "__main__":
    tg = sorted(I.target_key.unique()); ctx = mp.get_context("fork")
    with ctx.Pool(int(os.environ.get("PROCS", "4"))) as p: res = [r for x in p.imap_unordered(one_target, tg) for r in x]
    D = pd.DataFrame(res); D.to_csv(f"{RES}/h4b_per_target{'_smoke' if SMOKE else ''}.csv", index=False)
    tf = T[["target_key", "family"]]; out = {}
    for k in KS:
        d = D[D.k == k]
        if d.empty: continue
        pt = d.groupby(["arm", "target_key"])[["auc", "ef5", "p10"]].mean().reset_index(); out[str(k)] = {"targets": int(pt.target_key.nunique()), "families": int(pt.merge(tf, on="target_key").family.nunique()), "arms": {}}
        fms = {}
        for arm, g in pt.groupby("arm"):
            gm = g.merge(tf, on="target_key"); fms[arm] = {m: gm.groupby("family")[m].mean() for m in ("auc", "ef5", "p10")}
            out[str(k)]["arms"][arm] = {m: H.boot_mean(fms[arm][m], B=2000) for m in ("auc", "ef5", "p10")}
        base = [a for a in ("R", "NN") if a in fms]; strongest = max(base + [a for a in ("PT",) if a in fms], key=lambda a: out[str(k)]["arms"][a]["auc"]["point"]); out[str(k)]["strongest_control_auc"] = strongest
        for a in fms:
            if a != strongest: out[str(k)]["arms"][a]["vs_strongest_auc"] = H.boot_diff(fms[a]["auc"], fms[strongest]["auc"], B=2000)
            if k and a in ("FP-k", "PT+k", "NN") and "PT" in fms:
                zs = D[(D.k == 0) & (D.arm == "PT")].groupby("target_key").auc.mean().reset_index().merge(tf, on="target_key").groupby("family").auc.mean()
                out[str(k)]["arms"][a]["gain_vs_PT_zero_shot_auc"] = H.boot_diff(fms[a]["auc"], zs, B=2000)
    json.dump(out, open(f"{RES}/h4b_baselines{'_smoke' if SMOKE else ''}.json", "w"), indent=1)
    for k, v in out.items(): print("k", k, "targets", v["targets"], "fam", v["families"], {a: (round(x["auc"]["point"], 3), round(x["p10"]["point"], 2)) for a, x in v["arms"].items()})
