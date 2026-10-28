"""Audit the token-based annotation against independent SMILES-derived quantities. Writes data/audit_annotation.json.
(i) N-methyl count tokens vs SMARTS; (ii) D count tokens vs CIP (rdCIPLabeler) at backbone alpha carbons; (iii) topology HELM vs Molecule_Shape vs RDKit SMILES-only rule T1."""
import sys, os, json, collections
import numpy as np, pandas as pd
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import tokens as T
from rdkit import Chem, RDLogger
from rdkit.Chem import rdCIPLabeler
RDLogger.DisableLog("rdApp.*")
ALPHA = Chem.MolFromSmarts("[NX3][CX4;H1]([#6])[CX3](=O)[#7,#8]")
CSV = sys.argv[1]
ann = pd.read_csv("data/annotations.csv.gz", index_col=0)
raw = pd.read_csv(CSV, low_memory=False).sort_values("Structurally_Unique_ID").drop_duplicates("Structurally_Unique_ID").set_index("Structurally_Unique_ID")
out = {}
# (i) N-methyl
sel = ann[(ann.cap_c_tok.fillna("") == "") & (ann.n_nalkyl == ann.n_peptoid)]
eq = (sel.n_nme == sel.nme_smarts)
out["nme"] = dict(n=int(len(sel)), exact_agreement=round(float(eq.mean()), 4), mismatch_n=int((~eq).sum()),
                  mean_signed_diff=round(float((sel.n_nme - sel.nme_smarts).mean()), 4),
                  diff_dist={int(k): int(v) for k, v in (sel.n_nme - sel.nme_smarts).value_counts().items()})
mm = sel[~eq]
out["nme_mismatch_examples"] = [(int(i), int(r.n_nme), int(r.nme_smarts), raw.loc[i, "Sequence"][:120]) for i, r in mm.head(8).iterrows()]
# (ii) D vs CIP
rows = []
for sid, r in ann.iterrows():
    if r.n_ext or r.n_unknown or r.n_backbone_mod: continue
    helm = raw.loc[sid, "HELM"]
    if any(t in raw.loc[sid, "Sequence"] for t in ("Cys", "(O->S)", "Pen", "Se", "'C'")): continue
    m = Chem.MolFromSmiles(raw.loc[sid, "SMILES"])
    if m is None: continue
    rdCIPLabeler.AssignCIPLabels(m)
    alphas = {mt[1] for mt in m.GetSubstructMatches(ALPHA)}
    nR = sum(1 for a in alphas if m.GetAtomWithIdx(a).HasProp("_CIPCode") and m.GetAtomWithIdx(a).GetProp("_CIPCode") == "R")
    nS = sum(1 for a in alphas if m.GetAtomWithIdx(a).HasProp("_CIPCode") and m.GetAtomWithIdx(a).GetProp("_CIPCode") == "S")
    rows.append((sid, int(r.n_D), nR, nS, len(alphas)))
dd = pd.DataFrame(rows, columns=["sid", "n_D_tok", "n_R", "n_S", "n_alpha"])
ok = dd.n_D_tok == dd.n_R
out["D_cip"] = dict(n=int(len(dd)), exact_agreement=round(float(ok.mean()), 4), mismatch_n=int((~ok).sum()), diff_dist={int(k): int(v) for k, v in (dd.n_D_tok - dd.n_R).value_counts().items()})
out["D_cip_mismatch_examples"] = [(int(r.sid), int(r.n_D_tok), int(r.n_R), raw.loc[int(r.sid), "Sequence"][:120]) for r in dd[~ok].head(8).itertuples()]
# (iii) topology
ct = pd.crosstab(ann.helm_topology, ann.Molecule_Shape); out["topology_helm_vs_shape"] = {a: {b: int(v) for b, v in row.items()} for a, row in ct.iterrows()}
t1 = pd.crosstab(ann.helm_topology, ann.rdkit_topology); out["topology_helm_vs_rdkitT1"] = {a: {b: int(v) for b, v in row.items()} for a, row in t1.iterrows()}
h2t = ann.helm_topology == "head_to_tail"; lar = ann.helm_topology.str.startswith("lariat")
out["T1_accuracy"] = dict(head_to_tail_recall=round(float((ann.rdkit_topology[h2t] == "head_to_tail").mean()), 4), lariat_recall=round(float((ann.rdkit_topology[lar] == "lariat").mean()), 4),
                          overall=round(float(((h2t & (ann.rdkit_topology == "head_to_tail")) | (lar & (ann.rdkit_topology == "lariat"))).sum() / (h2t | lar).sum()), 4), n=int((h2t | lar).sum()))
out["n_unique_structures"] = int(len(ann)); out["helm_topology_counts_unique"] = {k: int(v) for k, v in ann.helm_topology.value_counts().items()}
json.dump(out, open("data/audit_annotation.json", "w"), indent=1); print(json.dumps(out, indent=1))
