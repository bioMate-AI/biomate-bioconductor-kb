"""Pilot 2 data prep + verification (no model numbers). Builds data/pairs_{nme,dflip}.csv from the committed post-fix pair table.
Edited peptide = the one carrying the feature (N-Me / D); parent = the other; effect = z_edited - z_parent (within-source standardised label)."""
import os, sys, json, hashlib, numpy as np, pandas as pd
HERE = os.path.dirname(os.path.abspath(__file__)); ST = os.path.join(HERE, "..", "stratification", "data")
os.makedirs(os.path.join(HERE, "data"), exist_ok=True)
P = pd.read_csv(os.path.join(ST, "mmp_pairs_pampa.csv.gz")); A = pd.read_csv(os.path.join(ST, "annotations.csv.gz"), index_col=0)
rep = {}
LAB = {"nme": "N-Me added (with minus without)", "dflip": "D flip (D minus L)"}
src_of = A["Source"].to_dict(); flat_of = A["flat_smiles"].to_dict(); smi_of = A["SMILES"].to_dict()
def half(s): return int(hashlib.sha256(s.encode()).hexdigest(), 16) % 2          # 0 = development half, 1 = test half
for k, lab in LAB.items():
    d = P[P.label == lab].copy()
    rep[k] = dict(n_pairs=int(len(d)), n_sources=int(d.source.nunique()))
    # pairs never straddle sources
    rep[k]["pairs_straddling_sources"] = int(((d.id_a.map(src_of) != d.source) | (d.id_b.map(src_of) != d.source)).sum())
    # stored effect equals sign*(z_b - z_a)
    rep[k]["max_abs_dz_recompute_err"] = float((d.dz - d.sign * (d.z_b - d.z_a)).abs().max())
    # orientation: sign=+1 => id_b carries the feature
    d["edited"] = np.where(d.sign == 1, d.id_b, d.id_a); d["parent"] = np.where(d.sign == 1, d.id_a, d.id_b)
    d["z_edit"] = np.where(d.sign == 1, d.z_b, d.z_a); d["z_par"] = np.where(d.sign == 1, d.z_a, d.z_b)
    rep[k]["max_abs_effect_err"] = float((d.z_edit - d.z_par - d.dz).abs().max())
    # feature check from the annotated residue strings (N-Me: exact_b has |Me; D flip: exact has |D)
    fe = np.where(d.sign == 1, d.exact_b, d.exact_a); fp = np.where(d.sign == 1, d.exact_a, d.exact_b)
    tag = "|Me" if k == "nme" else "|D"
    rep[k]["edited_has_feature_frac"] = float(np.mean([tag in x for x in fe])); rep[k]["parent_has_feature_frac"] = float(np.mean([tag in x for x in fp]))
    d["smi_parent"] = d.parent.map(smi_of); d["smi_edit"] = d.edited.map(smi_of); d["flat_parent"] = d.parent.map(flat_of); d["flat_edit"] = d.edited.map(flat_of)
    d["half"] = d.source.map(half)
    rep[k]["rdkit_missing_smiles"] = int(d.smi_parent.isna().sum() + d.smi_edit.isna().sum())
    rep[k]["sources_per_half"] = {int(h): int(d[d.half == h].source.nunique()) for h in (0, 1)}
    rep[k]["pairs_per_half"] = {int(h): int((d.half == h).sum()) for h in (0, 1)}
    rep[k]["per_source_n"] = d.groupby("source").size().to_dict()
    # same-flat parent/edit (D flip should be same flat structure; N-Me should differ)
    rep[k]["same_flat_parent_edit_frac"] = float((d.flat_parent == d.flat_edit).mean())
    d[["source", "half", "parent", "edited", "smi_parent", "smi_edit", "flat_parent", "flat_edit", "exact_a", "exact_b", "sign", "z_par", "z_edit", "dz"]].to_csv(os.path.join(HERE, "data", f"pairs_{k}.csv"), index=False)
# label scale: within-source standardisation on ALL labelled peptides (not pairs)
L = A[A.pampa.notna()]
import importlib; sys.path.insert(0, os.path.join(HERE, "..", "stratification")); import common as C
lab = C.load_labelled(); g = lab.groupby("Source")["y"].agg(["mean", "std", "size"])
rep["label_scale"] = dict(n_sources=int(len(g)), max_abs_source_mean=float(g["mean"].abs().max()), sd_range=[float(g["std"].min()), float(g["std"].max())], note="sd 0 or nan sources have <2 labels")
json.dump(rep, open(os.path.join(HERE, "data", "verify_pairs.json"), "w"), indent=1, default=str)
print(json.dumps({k: {a: b for a, b in v.items() if a != "per_source_n"} for k, v in rep.items()}, indent=1, default=str))
