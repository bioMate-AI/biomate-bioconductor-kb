"""Build data/annotations.csv.gz: one row per Structurally_Unique_ID (8,466 entries) with structure annotation and label columns.
usage: python3 build_annotations.py CycPeptMPDB_Peptide_All.csv"""
import sys, os, ast, json
import numpy as np, pandas as pd
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import annotate as A
FLOOR = -9.99

def build(csv):
    d = pd.read_csv(csv, low_memory=False)
    keep = ["Structurally_Unique_ID", "Source", "Year", "HELM", "SMILES", "Molecule_Shape", "Monomer_Length", "Monomer_Length_in_Main_Chain"]
    first = d.sort_values("Structurally_Unique_ID").drop_duplicates("Structurally_Unique_ID")[keep].set_index("Structurally_Unique_ID")
    lab = {}
    for col, name in (("PAMPA", "pampa"), ("Caco2", "caco2"), ("RRCK", "rrck"), ("MDCK", "mdck")):
        v = d[d[col].notna() & (d[col] > FLOOR)].groupby("Structurally_Unique_ID")[col].agg(["mean", "size"])
        lab[name] = v["mean"]; lab["n_" + name] = v["size"]
    ld = d[(d["Permeability"] > FLOOR) & d["PAMPA"].notna()]
    perm = ld.groupby("Structurally_Unique_ID")["Permeability"].mean()
    lab["y_loader"] = perm
    # CORRECTION 2026-10-30: for labelled peptides, Source/Year must come from the PAMPA (loader) row(s), as in loop_retro/run_loop.load (first loader row per structure),
    # not from the first row of any assay (which gave 177 peptides the wrong source, 150 of them Ohta instead of CHUGAI).
    fl = ld.groupby("Structurally_Unique_ID")[["Source", "Year"]].first()
    first.loc[fl.index, "Source"] = fl["Source"]; first.loc[fl.index, "Year"] = fl["Year"]
    nsrc = ld.groupby("Structurally_Unique_ID")["Source"].nunique()
    lab["n_pampa_sources"] = nsrc
    labdf = pd.DataFrame(lab)
    rows = []
    for sid, r in first.iterrows():
        a = A.annotate_one(r["HELM"], r["SMILES"]); a["sid"] = sid; rows.append(a)
    ann = pd.DataFrame(rows).set_index("sid")
    out = first.join(ann).join(labdf)
    out["shape_matches_helm"] = ((out["Molecule_Shape"] == "Circle") & (out["helm_topology"] == "head_to_tail")) | ((out["Molecule_Shape"] == "Lariat") & out["helm_topology"].str.startswith("lariat"))
    return out

if __name__ == "__main__":
    out = build(sys.argv[1]); os.makedirs("data", exist_ok=True)
    out.drop(columns=["HELM"]).to_csv("data/annotations.csv.gz")
    print(out.shape, "rdkit_ok", int(out["rdkit_ok"].sum()), "with pampa", int(out["pampa"].notna().sum()), "loader y", int(out["y_loader"].notna().sum()))
