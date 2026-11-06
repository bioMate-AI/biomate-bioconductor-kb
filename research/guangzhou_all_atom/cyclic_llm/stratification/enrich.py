"""Substructure/monomer enrichment with source adjustment (Part A6). usage: python3 enrich.py CycPeptMPDB.csv"""
import sys, os, json, hashlib, collections
import numpy as np, pandas as pd
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common as C, mmp as M, stats as S, tokens as T
from rdkit import Chem

SMARTS = {"tertiary_amide_NMe": "[CX3](=O)[NX3]([CH3])[#6]", "basic_aliphatic_amine": "[NX3;!$(NC=[O,S,N]);!$(N-a);!$(N#*);!$(N-[SX4])]([#6])",
          "carboxylic_acid": "[CX3](=O)[OX2H1]", "ester": "[CX3](=O)[OX2][#6]", "halogen": "[F,Cl,Br,I]", "aromatic_ring": "a1aaaaa1", "hydroxyl": "[OX2H][CX4]"}


def feature_table(d, items, smiles, min_count=30):
    F = {}
    cnt_base = collections.Counter(); cnt_nme = collections.Counter(); cnt_d = collections.Counter()
    for pid in d.index:
        its = items[pid]; seen_b = set(); seen_n = set(); seen_d = set()
        for it in its:
            if it[5] != "residue": continue
            seen_b.add(it[0]);
            if it[2]: seen_n.add(it[0])
            if it[1]: seen_d.add(it[0])
        cnt_base.update(seen_b); cnt_nme.update(seen_n); cnt_d.update(seen_d)
    for b, c in cnt_base.items():
        if c >= min_count: F["has_base:" + b] = np.array([any(it[0] == b and it[5] == "residue" for it in items[p]) for p in d.index])
    for b, c in cnt_nme.items():
        if c >= min_count: F["has_Nme_base:" + b] = np.array([any(it[0] == b and it[2] for it in items[p]) for p in d.index])
    for b, c in cnt_d.items():
        if c >= min_count: F["has_D_base:" + b] = np.array([any(it[0] == b and it[1] for it in items[p]) for p in d.index])
    for name, col in (("has_peptoid", "n_peptoid"), ("has_unknown_monomer", "n_unknown"), ("has_ext_backbone", "n_ext"), ("has_backbone_mod", "n_backbone_mod"), ("has_alpha_disub", "n_alpha_disub"),
                      ("has_proline", "n_pro"), ("has_dpro", "n_dpro"), ("has_glycine", "n_gly"), ("has_cap_n", "n_cap_n"), ("has_cap_c", "n_cap_c"), ("has_nalkyl_nonmethyl", "n_nalkyl"),
                      ("has_sidechain_mod", "n_sidechain_mod"), ("has_D_and_Nme_same_residue", "n_D_and_nme")):
        F[name] = (d[col] > 0).values
    F["motif_Nme_adjacent_Pro"] = (d.nme_adj_pro > 0).values; F["motif_Nme_adjacent_D"] = (d.nme_adj_D > 0).values
    F["motif_consecutive_Nme"] = (d.nme_adj > 0).values; F["motif_alternating_Nme"] = (d.nme_alt > 0).values; F["motif_consecutive_D"] = (d.d_adj > 0).values
    for k in (1, 2, 3, 5): F[f"n_Nme>={k}"] = (d.n_nme_final >= k).values
    for k in (1, 2, 3): F[f"n_D>={k}"] = (d.n_D >= k).values
    for name, sm in SMARTS.items():
        p = Chem.MolFromSmarts(sm); F["smarts:" + name] = np.array([Chem.MolFromSmiles(s).HasSubstructMatch(p) for s in smiles])
    F["arom_fraction>=0.3"] = (d.frac_aromatic >= 0.3).values
    return pd.DataFrame(F, index=d.index)


def enrich(z, source, X, min_side=5, min_present=10):
    rows = []
    srcs = np.asarray(source); us = np.unique(srcs)
    idx = {s: np.where(srcs == s)[0] for s in us}
    for f in X.columns:
        flag = X[f].values.astype(bool)
        if flag.sum() < min_present or (~flag).sum() < min_present: continue
        E = []; V = []
        for s, ii in idx.items():
            e, v = S.smd_within_source(z[ii], flag[ii], min_side)
            if np.isfinite(e): E.append(e); V.append(v)
        m = S.dl_meta(E, V)
        if m["k"] < 3: continue
        pi = 1.96 * np.sqrt(m["tau2"] + m["se"] ** 2)
        rows.append(dict(feature=f, n_present=int(flag.sum()), n_sources=m["k"], effect=m["pooled"], lo=m["lo"], hi=m["hi"], I2=m["I2"], tau=float(np.sqrt(m["tau2"])), pred_lo=m["pooled"] - pi, pred_hi=m["pooled"] + pi,
                         frac_sources_positive=float(np.mean(np.array(E) > 0)), p=S.p_from_ci(m["pooled"], m["se"])))
    R = pd.DataFrame(rows)
    if len(R): R["q"], R["sig"] = S.bh_fdr(R["p"].values, 0.10)
    return R


def half(source_names):
    return {s: int(hashlib.sha256(s.encode()).hexdigest(), 16) % 2 for s in source_names}


if __name__ == "__main__":
    raw = pd.read_csv(sys.argv[1], low_memory=False).sort_values("Structurally_Unique_ID").drop_duplicates("Structurally_Unique_ID").set_index("Structurally_Unique_ID")
    d = C.load_labelled(); items = {pid: M.items_from_helm(raw.loc[pid, "HELM"]) for pid in d.index}
    X = feature_table(d, items, d.SMILES.values); z = d.y.values; src = d.Source.values
    print("features:", X.shape, flush=True)
    R = enrich(z, src, X); R.sort_values("p").to_csv(os.path.join(C.HERE, "data", "enrich_all.csv"), index=False)
    print("tested", len(R), "significant (BH 10%)", int(R.sig.sum()), flush=True)
    # leak-safe replication across source halves
    h = half(sorted(set(src))); hv = np.array([h[s] for s in src]); rep = []
    for mine, test in ((0, 1), (1, 0)):
        A_ = enrich(z[hv == mine], src[hv == mine], X[hv == mine]); B_ = enrich(z[hv == test], src[hv == test], X[hv == test])
        sig = A_[A_.sig].merge(B_, on="feature", suffixes=("_mine", "_test"))
        same = (np.sign(sig.effect_mine) == np.sign(sig.effect_test)); ok = same & ((sig.lo_test > 0) | (sig.hi_test < 0))
        rep.append(dict(mined_on_half=mine, n_mined_sig=int(A_.sig.sum()), n_testable=int(len(sig)), n_sign_agree=int(same.sum()), n_replicated=int(ok.sum()), replication_rate=float(ok.mean()) if len(sig) else np.nan,
                        median_effect_ratio_test_over_mine=float(np.median(sig.effect_test / sig.effect_mine)) if len(sig) else np.nan))
        sig.assign(replicated=ok).to_csv(os.path.join(C.HERE, "data", f"enrich_replication_mined{mine}.csv"), index=False)
    json.dump(rep, open(os.path.join(C.HERE, "data", "enrich_replication.json"), "w"), indent=1); print(rep, flush=True)
    # negative control: labels permuted within source
    rng = np.random.default_rng(0); nulls = []
    for rep_i in range(5):
        zp = z.copy()
        for s in np.unique(src):
            ii = np.where(src == s)[0]; zp[ii] = rng.permutation(z[ii])
        Rp = enrich(zp, src, X); nulls.append(dict(rep=rep_i, tested=int(len(Rp)), n_sig=int(Rp.sig.sum()), min_q=float(Rp.q.min())))
    json.dump(nulls, open(os.path.join(C.HERE, "data", "enrich_null_control.json"), "w"), indent=1); print("null control:", nulls, flush=True)
    # planted-effect control: add delta=0.3 SD to a random mid-frequency feature within all sources
    Xr = pd.DataFrame({"random_feature": np.random.default_rng(5).random(len(z)) < 0.3}, index=X.index); zp = z + 0.4 * Xr["random_feature"].values      # planted shift on a random feature, all sources
    Rpl = enrich(zp, src, Xr); print("planted random feature delta=0.4 ->", Rpl[["effect", "lo", "hi"]].round(3).to_dict("records"), flush=True)
    json.dump(dict(feature="random_feature", delta=0.4, recovered=Rpl[["effect", "lo", "hi"]].to_dict("records")), open(os.path.join(C.HERE, "data", "enrich_planted_control.json"), "w"), indent=1)
