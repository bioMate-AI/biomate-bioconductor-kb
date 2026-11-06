"""P1 — structure/learned-representation permeability oracle (2026-10-23).

The sequence/2D ceiling: best prior permeability oracle = ECFP + chameleon-3D, scaffold R2 ~0.30 (SOTA
CycPeptMP = 0.77). The ChemBERTa learned embedding was computed only for the DESIGN pool (canonical overlap
with CycPeptMPDB ~0.3%), so it was never tested on the permeability benchmark. This computes ChemBERTa-77M
embeddings for the CycPeptMPDB peptides directly and asks the decisive P1 question: does a learned molecular
representation (alone and fused with the RDKit 2D descriptors) clear the 2D ceiling toward SOTA on a leakage-
safe Bemis-Murcko SCAFFOLD split?

CPU; rdkit + transformers + sklearn. Honest: scaffold split (not random), fixed seed, R2 + Pearson + Spearman.
"""
import os, sys, csv, json, numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)                                   # guangzhou_all_atom
CSV = os.path.join(ROOT, "data/raw/CycPeptMPDB_Peptide_All.csv")
EMB_CACHE = os.path.join(ROOT, "results/chemberta_emb_cycpept_perm.npz")
OUT = os.path.join(ROOT, "results/perm_oracle_chemberta.json")
MODEL_ID = "DeepChem/ChemBERTa-77M-MLM"


def load_perm():
    """Return (smiles, y=logPapp, D2=RDKit 2D descriptor matrix, desc_names)."""
    sm, y, rows = [], [], []
    with open(CSV) as f:
        rd = csv.DictReader(f)
        hdr = rd.fieldnames
        # RDKit descriptor columns = numeric columns that are not id/label/assay/meta
        skip = {"ID", "﻿ID", "SMILES", "Permeability", "PAMPA", "Caco2", "R_Caco2", "T_PAMPA",
                "Structurally_Unique_ID", "Same_Peptides_ID", "Same_Peptides_Source",
                "Same_Peptides_Permeability", "Same_Peptides_Assay", "Sequence_LogP", "Sequence",
                "Monomer_Length", "Monomer_Length_in_Main_Chain", "HELM", "Name", "Year", "Source", "Assay"}
        for row in rd:
            s = (row.get("SMILES") or "").strip()
            p = (row.get("Permeability") or "").strip()
            if not s or p in ("", "nan", "NaN"):
                continue
            try:
                yv = float(p)
            except ValueError:
                continue
            sm.append(s); y.append(yv); rows.append(row)
        # descriptor columns: those parseable as float on most rows
        cand = [h for h in hdr if h not in skip]
        desc_names = []
        for h in cand:
            vals = [rows[i].get(h, "") for i in range(min(200, len(rows)))]
            ok = sum(1 for v in vals if _isfloat(v))
            if ok >= 0.9 * len(vals):
                desc_names.append(h)
    D2 = np.array([[_f(r.get(h, "")) for h in desc_names] for r in rows], dtype="float32")
    D2 = np.nan_to_num(D2, nan=0.0, posinf=0.0, neginf=0.0)
    return sm, np.array(y, "float32"), D2, desc_names


def _isfloat(v):
    try:
        float(v); return True
    except (TypeError, ValueError):
        return False


def _f(v):
    try:
        return float(v)
    except (TypeError, ValueError):
        return 0.0


def chemberta_embed(smiles):
    """Mean-pooled ChemBERTa-77M last-hidden embedding per SMILES [N, 384]. Cached to EMB_CACHE."""
    if os.path.exists(EMB_CACHE):
        z = np.load(EMB_CACHE, allow_pickle=True)
        if list(z["smiles"]) == list(smiles):
            print(f"[emb] cache hit {EMB_CACHE}")
            return z["emb"]
    import torch
    from transformers import AutoTokenizer, AutoModel
    print(f"[emb] computing ChemBERTa for {len(smiles)} SMILES on CPU …")
    tok = AutoTokenizer.from_pretrained(MODEL_ID)
    mdl = AutoModel.from_pretrained(MODEL_ID).eval()
    embs = []
    with torch.no_grad():
        for i in range(0, len(smiles), 64):
            batch = list(smiles[i:i + 64])
            enc = tok(batch, padding=True, truncation=True, max_length=512, return_tensors="pt")
            out = mdl(**enc).last_hidden_state                 # [B, L, H]
            mask = enc["attention_mask"].unsqueeze(-1).float()
            pooled = (out * mask).sum(1) / mask.sum(1).clamp(min=1)
            embs.append(pooled.cpu().numpy().astype("float32"))
            if (i // 64) % 20 == 0:
                print(f"  {i}/{len(smiles)}")
    emb = np.concatenate(embs)
    np.savez_compressed(EMB_CACHE, emb=emb, smiles=np.array(smiles, dtype=object))
    print(f"[emb] saved {emb.shape} -> {EMB_CACHE}")
    return emb


def murcko_scaffold_split(smiles, frac_test=0.2, seed=0):
    """Bemis-Murcko scaffold split: whole scaffolds go train OR test (no leakage)."""
    from rdkit import Chem
    from rdkit.Chem.Scaffolds import MurckoScaffold
    scaf = {}
    for i, s in enumerate(smiles):
        m = Chem.MolFromSmiles(s)
        key = MurckoScaffold.MurckoScaffoldSmiles(mol=m) if m else f"_bad{i}"
        scaf.setdefault(key, []).append(i)
    groups = sorted(scaf.values(), key=len, reverse=True)       # big scaffolds first -> train
    n_test_target = int(frac_test * len(smiles))
    rng = np.random.RandomState(seed)
    # put the largest groups in train, fill test from the rest (deterministic, leakage-free)
    test, train = [], []
    for g in groups:
        if len(test) < n_test_target and len(g) <= max(5, n_test_target // 10):
            test += g
        else:
            train += g
    rng.shuffle(train); rng.shuffle(test)
    return np.array(train), np.array(test), len(scaf)


def evaluate(X, y, tr, te, name):
    from sklearn.ensemble import HistGradientBoostingRegressor
    from scipy.stats import pearsonr, spearmanr
    m = HistGradientBoostingRegressor(max_iter=400, learning_rate=0.06, max_depth=None,
                                      l2_regularization=1.0, random_state=0)
    m.fit(X[tr], y[tr])
    p = m.predict(X[te])
    ss_res = float(((y[te] - p) ** 2).sum()); ss_tot = float(((y[te] - y[te].mean()) ** 2).sum())
    r2 = 1 - ss_res / ss_tot if ss_tot > 0 else float("nan")
    return {"model": name, "n_feat": int(X.shape[1]), "scaffold_R2": round(r2, 4),
            "Pearson": round(float(pearsonr(y[te], p)[0]), 4),
            "Spearman": round(float(spearmanr(y[te], p)[0]), 4)}


def main():
    sm, y, D2, dnames = load_perm()
    print(f"perm: n={len(sm)} | 2D descriptors={D2.shape[1]}")
    emb = chemberta_embed(sm)
    tr, te, nscaf = murcko_scaffold_split(sm)
    print(f"scaffold split: n_scaffolds={nscaf} | train={len(tr)} test={len(te)}")
    # standardize 2D for fusion
    from sklearn.preprocessing import StandardScaler
    D2s = StandardScaler().fit(D2[tr]).transform(D2)
    embs = StandardScaler().fit(emb[tr]).transform(emb)
    arms = {
        "2D_descriptors (baseline)": D2s,
        "ChemBERTa (learned, NEW)": embs,
        "ChemBERTa + 2D (fusion)": np.concatenate([embs, D2s], 1),
    }
    res = {"dataset": "CycPeptMPDB", "n": len(sm), "n_scaffolds": nscaf,
           "split": "Bemis-Murcko scaffold (leakage-safe)", "SOTA_CycPeptMP_scaffold_R2": 0.77,
           "prior_best_ECFP_chameleon_R2": 0.301, "arms": []}
    for name, X in arms.items():
        r = evaluate(X, y, tr, te, name)
        print(f"  {name:32s} scaffold R2={r['scaffold_R2']:.3f}  Pearson={r['Pearson']:.3f}  Spearman={r['Spearman']:.3f}")
        res["arms"].append(r)
    best = max(res["arms"], key=lambda a: a["scaffold_R2"])
    res["best_arm"] = best["model"]; res["best_R2"] = best["scaffold_R2"]
    res["clears_2D_ceiling"] = bool(best["scaffold_R2"] > 0.35)
    res["verdict"] = ("ChemBERTa clears the 2D ceiling" if best["scaffold_R2"] > 0.35
                      else "learned rep does NOT clear the 2D ceiling — ceiling is deeper than representation")
    json.dump(res, open(OUT, "w"), indent=2)
    print(f"\nBEST: {best['model']} R2={best['R2'] if 'R2' in best else best['scaffold_R2']}  -> {OUT}")


if __name__ == "__main__":
    main()
