"""Step 4: structures for the external test set (previous agent's Kapp 2017 matrix). Tier A = registry-retrieved (PubChem CID / ChEMBL id),
tier B = built here from the sequence/name convention (rule recorded). Everything else is listed as UNRESOLVED (never guessed)."""
import pandas as pd, json
from rdkit import Chem
from common import standardize_smiles
prev = pd.read_csv("../integrin_selectivity/ligands.csv"); mat = pd.read_csv("../integrin_selectivity/matrix.csv")
K = mat[mat.source == "kapp2017"]; ligs = list(dict.fromkeys(K.ligand_id))
# ---- peptide builder (validated against registry structures below) ----
def res(sc, D=False, NMe=False, first=False, last=False, pro=None):
    st = "[C@H]" if D else "[C@@H]"
    if pro: n = pro["n"]; return f"N{n}CCC[C@{'@' if D else ''}H]{n}C(=O)"  # unused
    nn = "N" + ("1" if first else "") + ("(C)" if NMe else "")
    return f"{nn}{st}({sc})" + ("C1=O" if last else "C(=O)")
SC = dict(F="Cc2ccccc2", R="CCCNC(=N)N", D="CC(=O)O", L="CC(C)C", A="C", K="CCCCN", V="C(C)C", C="CS", Y="Cc2ccc(O)cc2", G=None)
def cyc(seq):
    """seq: list of (aa, flags) head-to-tail cyclic; flags subset of {'D','NMe','Pro'}"""
    s = ""
    for i, (aa, fl) in enumerate(seq):
        first, last = i == 0, i == len(seq) - 1
        if aa == "G": s += "N" + ("1" if first else "") + "CC" + ("1=O" if last else "(=O)")  # Gly: N-CH2-C(=O); closes at last
        elif "Pro" in fl: s += "N3CCC[C@" + ("@" if "D" in fl else "") + "H]3" + ("C1=O" if last else "C(=O)")
        else: s += res(SC[aa], "D" in fl, "NMe" in fl, first, last)
    return s
RULE = {}
BUILT = {
 "c(RGDfC)": (cyc([("R", ""), ("G", ""), ("D", ""), ("F", "D"), ("C", "")]), "head-to-tail cyclic pentapeptide Arg-Gly-Asp-D-Phe-Cys, free Cys thiol; same convention as the registry c(RGDfK)"),
 "c(FRGDLAFp(NMe)K)": (cyc([("F", ""), ("R", ""), ("G", ""), ("D", ""), ("L", ""), ("A", ""), ("F", ""), ("P", "Pro,D"), ("K", "NMe")]), "head-to-tail cyclic nonapeptide Phe-Arg-Gly-Asp-Leu-Ala-Phe-D-Pro-(N-Me)Lys; lowercase p = D-Pro, (NMe)K = N-methyl-L-Lys as in the name; Lys side-chain free"),
}
# pre-check: builder reproduces the registry c(RGDfK) (tier A, PubChem CID 10196873) and c(RGDyK)
chk = {}
for nm, seq in {"c(RGDfK)": [("R", ""), ("G", ""), ("D", ""), ("F", "D"), ("K", "")], "c(RGDyK)": [("R", ""), ("G", ""), ("D", ""), ("Y", "D"), ("K", "")]}.items():
    mine = standardize_smiles(cyc(seq))[3]; ref = standardize_smiles(prev[prev.ligand_id == nm].smiles.iloc[0])[3]
    chk[nm] = dict(builder_matches_registry_fullkey=bool(mine == ref and mine is not None))
assert all(v["builder_matches_registry_fullkey"] for v in chk.values()), chk
SEQ = {"A20FMDV2": ("NAVPNLRGDLQVLAQKVART", "linear 20-mer from sequence, L-amino acids, free termini (RDKit MolFromSequence); termini/modifications of the Kapp sample not stated"),
       "RTDLDSLRT": ("RTDLDSLRT", "linear 9-mer from sequence, L-aa, free termini; flat InChIKey identical to ChEMBL CHEMBL2332369")}
rows = []
for l in ligs:
    p = prev[(prev.ligand_id == l) & (prev.source == "kapp2017")].iloc[0]; smi, tier, rule = (p.smiles if isinstance(p.smiles, str) else None), (p.tier if isinstance(p.tier, str) else None), str(p.provenance)
    if smi is None and l in BUILT: smi, rule = BUILT[l]; tier = "B"
    if smi is None and l in SEQ: smi = Chem.MolToSmiles(Chem.MolFromSequence(SEQ[l][0])); rule = SEQ[l][1]; tier = "B"
    m, cs, flat, full = standardize_smiles(smi)
    rows.append(dict(ligand_id=l, smiles=cs, tier=tier if cs else None, flat_key=flat, full_key=full, rule=rule if cs else "UNRESOLVED: no unambiguous structure available"))
E = pd.DataFrame(rows); E.to_csv("data/external_ligands.csv", index=False)
res_ = E[E.smiles.notna()]; un = E[E.smiles.isna()].ligand_id.tolist()
cells = K[["ligand_id", "integrin", "ic50_nM", "censor", "pIC50"]].rename(columns={"integrin": "target", "pIC50": "pact"})
cells = cells.merge(E[["ligand_id", "flat_key", "smiles"]], on="ligand_id"); cells = cells[cells.smiles.notna()]
cells.to_csv("data/external_cells.csv", index=False)
out = dict(n_kapp_ligands=len(ligs), n_resolved=len(res_), n_tierA=int((res_.tier == "A").sum()), n_tierB=int((res_.tier == "B").sum()), unresolved=un, builder_validation=chk,
           n_cells_resolved=len(cells), n_cells_uncensored=int((cells.censor == "=").sum()))
json.dump(out, open("data/external_set_summary.json", "w"), indent=1); print(json.dumps(out, indent=1))
