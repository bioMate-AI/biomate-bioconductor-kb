"""Run peptide MMP analyses on CycPeptMPDB (Part A5, A7(1)). usage: python3 run_mmp.py CycPeptMPDB.csv  -> data/mmp_*.csv, data/mmp_summary.json"""
import sys, os, json
import numpy as np, pandas as pd
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common as C, mmp as M, annotate as A

raw = pd.read_csv(sys.argv[1], low_memory=False).sort_values("Structurally_Unique_ID").drop_duplicates("Structurally_Unique_ID").set_index("Structurally_Unique_ID")
ann = pd.read_csv(os.path.join(C.HERE, "data", "annotations.csv.gz"), index_col=0)
ann["items"] = [M.items_from_helm(raw.loc[i, "HELM"]) for i in ann.index]
ann["ring_res"] = ann["ring_res"].fillna(-1)
lab = C.load_labelled()
ann = ann.join(lab[["y", "flat_id"]].rename(columns={"y": "z_pampa"}), how="left")
ann["flat_id"] = ann["flat_id"].fillna(-1)
summary = {}
for assay in ("pampa", "caco2", "rrck", "mdck"):
    sub = ann[ann[assay].notna()].copy()
    if len(sub) < 30: continue
    P = M.find_single_pairs(sub)
    parts = [P, M.find_nme_shift(sub), M.find_indel(sub)]
    P = pd.concat([p for p in parts if len(p)], ignore_index=True) if any(len(p) for p in parts) else pd.DataFrame()
    if P.empty: continue
    P["y_a"] = sub.loc[P.id_a, assay].values; P["y_b"] = sub.loc[P.id_b, assay].values
    P["flat_a"] = sub.loc[P.id_a, "flat_id"].values if "flat_id" in sub else P.id_a.values
    if assay == "pampa":
        P["z_a"] = sub.loc[P.id_a, "z_pampa"].values; P["z_b"] = sub.loc[P.id_b, "z_pampa"].values
        P["dz"] = P["sign"] * (P["z_b"] - P["z_a"])
    E = M.effects(P, "y_a", "y_b")
    E.to_csv(os.path.join(C.HERE, "data", f"mmp_effects_{assay}.csv"), index=False)
    P.drop(columns=["flat_a"]).to_csv(os.path.join(C.HERE, "data", f"mmp_pairs_{assay}.csv.gz"), index=False)
    summary[assay] = dict(n_peptides=int(len(sub)), n_pairs=int(len(P)), n_transformations=int(len(E)))
    print(assay, summary[assay], flush=True)
json.dump(summary, open(os.path.join(C.HERE, "data", "mmp_summary.json"), "w"), indent=1)
