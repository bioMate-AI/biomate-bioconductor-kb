"""Step 1: audit + conservative cleaning of CycPeptMPDB. Writes data/clean.csv, results/data_report.json.
No model fitting. Every filter is counted in the report."""
import json, numpy as np, pandas as pd
from rdkit import Chem, RDLogger
from rdkit.Chem.Scaffolds import MurckoScaffold
from common import *
RDLogger.DisableLog("rdApp.*")

d = pd.read_csv(RAW, low_memory=False)
rep = {"raw_rows": len(d), "versions": d.Version.value_counts().to_dict(), "n_sources": int(d.Source.nunique())}
rep["rows_per_assay_any"] = {a: int(d[a].notna().sum()) for a in ASSAY_ORDER}
rep["rows_with_2_assays"] = int((d[ASSAY_ORDER].notna().sum(axis=1) == 2).sum())
rep["raw_label_describe"] = d.Permeability.describe().round(3).to_dict()
# --- assay assignment: first non-null in PAMPA > Caco2 > RRCK > MDCK
def assay_of(r):
    for a in ASSAY_ORDER:
        if pd.notna(r[a]): return a
    return None
d["assay"] = d.apply(assay_of, axis=1)
d["y"] = d.apply(lambda r: r[r["assay"]] if r["assay"] else np.nan, axis=1)
rep["assay_value_equals_Permeability_col"] = float((np.isclose(d.y, d.Permeability)).mean())
# --- SMILES validity
mols = [Chem.MolFromSmiles(s) if isinstance(s, str) else None for s in d.SMILES]
d["valid"] = [m is not None for m in mols]
rep["smiles_invalid"] = int((~d.valid).sum())
# --- HELM
def okhelm(h):
    try: parse_helm_monomers(h); return True
    except Exception: return False
d["helm_ok"] = d.HELM.map(lambda h: okhelm(h) if isinstance(h, str) else False)
rep["helm_unparsable"] = int((~d.helm_ok).sum())
# --- filters (counted sequentially)
filt = {}
keep = d.valid & d.helm_ok & d.y.notna()
filt["drop_invalid_smiles_helm_or_nolabel"] = int((~keep).sum())
cens = d.Detection_Limit_1.notna() | d.Detection_Limit_2.notna() | (d.y <= -10.0)
filt["drop_censored_detection_limit_or_sentinel_-10"] = int((keep & cens).sum())
keep &= ~cens
rep["filters"] = filt
c = d[keep].copy().reset_index(drop=True)
cm = [Chem.MolFromSmiles(s) for s in c.SMILES]
c["can"] = [Chem.MolToSmiles(m) for m in cm]
c["pid"] = c.can.map(lambda s: hashlib.md5(s.encode()).hexdigest()[:12])      # peptide identity = canonical isomeric SMILES
def gen_scaf(m):
    try:
        sc = MurckoScaffold.GetScaffoldForMol(m)
        return Chem.MolToSmiles(MurckoScaffold.MakeScaffoldGeneric(sc))
    except Exception: return "NOSCAF"
c["scaf"] = [gen_scaf(m) for m in cm]
nme = Chem.MolFromSmarts("[CH3][NX3;H0]([#6])C=O")
c["n_nme_smiles"] = [len(m.GetSubstructMatches(nme)) for m in cm]
c["monomers"] = c.HELM.map(lambda h: "|".join(parse_helm_monomers(h)))
c["n_nme_helm"] = c.monomers.map(lambda s: sum(is_nmethyl_monomer(x) for x in s.split("|")))
c["n_dres"] = c.monomers.map(lambda s: sum(bool(re.match(r"^(d[A-Z]|Me_d|d[a-z])", x)) for x in s.split("|")))
c["ring_atoms"] = [max((len(r) for r in m.GetRingInfo().AtomRings()), default=0) for m in cm]
c["ring_res"] = c.Monomer_Length_in_Main_Chain
c["n_heavy"] = [m.GetNumHeavyAtoms() for m in cm]
c["source"] = c.Source
out = c[["ID","source","Year","Version","assay","y","pid","can","scaf","HELM","monomers","ring_res","ring_atoms","n_nme_smiles","n_nme_helm","n_dres","n_heavy","Molecule_Shape","CHCl3_3DPSA","H2O_3DPSA"]]
out = out.rename(columns={"Year":"year","Version":"version","HELM":"helm","Molecule_Shape":"shape"})
out.to_csv(CLEAN, index=False)
# --- report on cleaned set
rep["clean_rows"] = len(out); rep["clean_unique_peptides"] = int(out.pid.nunique())
rep["clean_rows_per_assay"] = out.assay.value_counts().to_dict()
rep["clean_unique_peptides_per_assay"] = out.groupby("assay").pid.nunique().to_dict()
rep["clean_rows_per_source"] = out.source.value_counts().to_dict()
rep["clean_label"] = out.y.describe().round(3).to_dict()
rep["label_by_assay"] = out.groupby("assay").y.describe().round(3).to_dict("index")
dup = out.groupby("pid").size()
rep["duplicates"] = {"peptides_with_>1_row": int((dup > 1).sum()), "rows_in_duplicated_peptides": int(dup[dup > 1].sum()),
                     "peptides_in_>1_source": int((out.groupby("pid").source.nunique() > 1).sum())}
rep["n_generic_scaffolds"] = int(out.scaf.nunique())
rep["ring_res_counts"] = out.ring_res.value_counts().sort_index().to_dict()
rep["n_methyl_smiles_counts"] = out.n_nme_smiles.value_counts().sort_index().to_dict()
rep["nme_helm_vs_smiles_agree_frac"] = float((out.n_nme_helm == out.n_nme_smiles).mean())
rep["shape"] = out["shape"].value_counts().to_dict()
rep["n_distinct_monomers"] = len(set(m for s in out.monomers for m in s.split("|")))
rep["has_3DPSA_db_cols"] = int(out.CHCl3_3DPSA.notna().sum())
json.dump(rep, open(os.path.join(HERE, "results/data_report.json"), "w"), indent=1, default=str)
print(json.dumps({k: v for k, v in rep.items() if k not in ("clean_rows_per_source","ring_res_counts","n_methyl_smiles_counts","label_by_assay")}, indent=1, default=str))
