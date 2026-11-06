"""Cross-property and other-data analyses (Part A7). usage: python3 cross_property.py CycPeptMPDB.csv
Outputs data/xprop_*.csv and data/xprop_summary.json. Binding table is read-only (data/raw/binding_affinity/binding_affinity_v1.csv)."""
import sys, os, json, collections
import numpy as np, pandas as pd
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common as C, stats as S
from rdkit import Chem, RDLogger
from scipy.stats import spearmanr
RDLogger.DisableLog("rdApp.*")
ROOT = os.path.abspath(os.path.join(C.HERE, "..", ".."))
summary = {}
ann = pd.read_csv(os.path.join(C.HERE, "data", "annotations.csv.gz"), index_col=0)

# (1) permeability across assays on the same structures
rows = []
for other in ("caco2", "rrck", "mdck"):
    sub = ann[ann.pampa.notna() & ann[other].notna()]
    if len(sub) < 8: rows.append(dict(pair=f"pampa-{other}", n=int(len(sub)))); continue
    rho = spearmanr(sub.pampa, sub[other])[0]
    zs = []; vs = []
    for s, g in sub.groupby("Source"):
        if len(g) >= 8 and g.pampa.std() > 0 and g[other].std() > 0:
            r = spearmanr(g.pampa, g[other])[0]; zs.append(np.arctanh(np.clip(r, -0.999, 0.999))); vs.append(1 / (len(g) - 3))
    m = S.dl_meta(zs, vs)
    rows.append(dict(pair=f"pampa-{other}", n=int(len(sub)), n_sources=int(sub.Source.nunique()), spearman_pooled=float(rho), within_source_k=m["k"], within_source_rho=float(np.tanh(m["pooled"])) if m["k"] else np.nan))
pd.DataFrame(rows).to_csv(os.path.join(C.HERE, "data", "xprop_assay_agreement.csv"), index=False)
print(pd.DataFrame(rows).round(3).to_string(index=False), flush=True)
# transformation-effect sign agreement across assays
eff = {a: pd.read_csv(os.path.join(C.HERE, "data", f"mmp_effects_{a}.csv")).set_index("transformation") for a in ("pampa", "caco2", "rrck") if os.path.exists(os.path.join(C.HERE, "data", f"mmp_effects_{a}.csv"))}
ag = []
for a in ("caco2", "rrck"):
    if a not in eff: continue
    for tr in eff["pampa"].index.intersection(eff[a].index):
        e1, e2 = eff["pampa"].loc[tr], eff[a].loc[tr]
        if e1.directed and e1.n_pairs >= 10 and e2.n_pairs >= 10:
            ag.append(dict(assay=a, transformation=tr, pampa_pair_mean=e1.pair_mean, other_pair_mean=e2.pair_mean, n_pampa=int(e1.n_pairs), n_other=int(e2.n_pairs), same_sign=bool(np.sign(e1.pair_mean) == np.sign(e2.pair_mean))))
pd.DataFrame(ag).to_csv(os.path.join(C.HERE, "data", "xprop_effect_sign_agreement.csv"), index=False)

# (2) binding: peptide-like macrocycles, SMILES-computable transformations and SMARTS panel within target x assay type
b = pd.read_csv(os.path.join(ROOT, "data", "raw", "binding_affinity", "binding_affinity_v1.csv"), low_memory=False)
b = b[b.cyclic_bool.astype(str).str.lower().isin(["true", "1"]) & b.affinity_nM.notna() & (b.affinity_nM > 0) & (b.relation == "=") & b.affinity_type.isin(["IC50", "Ki", "Kd"])].copy()
ok_smiles = b.smiles.drop_duplicates()
BB = Chem.MolFromSmarts("[CX4;$(C[NX3])][CX3](=O)[NX3]"); NME = Chem.MolFromSmarts("[CX3](=O)[NX3]([CH3])[#6]")
info = {}
for s in ok_smiles:
    m = Chem.MolFromSmiles(s)
    if m is None: continue
    mac = max([len(r) for r in m.GetRingInfo().AtomRings()] or [0])
    info[s] = (mac >= 9 and len(m.GetSubstructMatches(BB)) >= 3, Chem.MolToSmiles(m, isomericSmiles=False), Chem.MolToSmiles(m))
b = b[b.smiles.map(lambda s: info.get(s, (False,))[0])].copy()
b["flat"] = b.smiles.map(lambda s: info[s][1]); b["canon"] = b.smiles.map(lambda s: info[s][2]); b["pAff"] = 9 - np.log10(b.affinity_nM)
g = b.groupby(["target_uniprot", "affinity_type", "canon"]).agg(pAff=("pAff", "mean"), flat=("flat", "first"), smiles=("smiles", "first")).reset_index()
summary["binding"] = dict(rows_peptide_like_exact=int(len(b)), compounds=int(g.canon.nunique()), targets=int(g.target_uniprot.nunique()), units_target_type=int(g.groupby(["target_uniprot", "affinity_type"]).ngroups))
# stereo-flip pairs: same target x type, same flat structure, different stereo
rows = []
for (t, ty, fl), sub in g.groupby(["target_uniprot", "affinity_type", "flat"]):
    if len(sub) >= 2:
        v = sub.pAff.values
        for i in range(len(v)):
            for j in range(i + 1, len(v)): rows.append(dict(target=t, type=ty, abs_delta=abs(v[i] - v[j])))
sf = pd.DataFrame(rows)
# random same-target pairs for reference
rng = np.random.default_rng(0); ref = []
for (t, ty), sub in g.groupby(["target_uniprot", "affinity_type"]):
    if len(sub) >= 5:
        v = sub.pAff.values
        for _ in range(min(50, len(v))): i, j = rng.choice(len(v), 2, replace=False); ref.append(abs(v[i] - v[j]))
summary["binding_stereo_flip"] = dict(n_pairs=int(len(sf)), n_targets=int(sf.target.nunique()) if len(sf) else 0, mean_abs_delta_pAff=float(sf.abs_delta.mean()) if len(sf) else None, frac_gt_1=float((sf.abs_delta > 1).mean()) if len(sf) else None,
                                      random_same_target_mean_abs_delta=float(np.mean(ref)), random_frac_gt_1=float(np.mean(np.array(ref) > 1)))
# N-methyl added: single demethylation of A equals B
lookup = {(t, ty): dict(zip(sub.canon, sub.pAff)) for (t, ty), sub in g.groupby(["target_uniprot", "affinity_type"])}
rows = []
for (t, ty), d_ in lookup.items():
    for smi, pa in d_.items():
        m = Chem.MolFromSmiles(smi)
        for mt in {x[2] for x in m.GetSubstructMatches(NME)}:
            em = Chem.RWMol(m); nme_atom = [n.GetIdx() for n in m.GetAtomWithIdx(mt).GetNeighbors() if n.GetSymbol() == "C" and n.GetTotalNumHs() == 3 and n.GetDegree() == 1]
            if not nme_atom: continue
            em.RemoveAtom(nme_atom[0])
            try: Chem.SanitizeMol(em); dem = Chem.MolToSmiles(em)
            except Exception: continue
            if dem in d_: rows.append(dict(target=t, type=ty, delta=pa - d_[dem]))
nm = pd.DataFrame(rows)
if len(nm):
    per = [(g_.delta.mean(), g_.delta.var(ddof=1) / len(g_) if g_.delta.var(ddof=1) > 0 else np.nan) for _, g_ in nm.groupby("target") if len(g_) >= 3]
    mm = S.dl_meta([p[0] for p in per], [p[1] for p in per]); summary["binding_N_methyl_added"] = dict(n_pairs=int(len(nm)), n_targets=int(nm.target.nunique()), mean_delta_pAff=float(nm.delta.mean()), meta=mm)
else: summary["binding_N_methyl_added"] = dict(n_pairs=0)
# SMARTS panel within target x type (within-unit z of pAff)
PANEL = {"N-methyl amide": "[CX3](=O)[NX3]([CH3])[#6]", "aromatic ring": "a1aaaaa1", "basic amine": "[NX3;!$(NC=[O,S,N]);!$(N-a);!$(N#*)]([#6])", "carboxylic acid": "[CX3](=O)[OX2H1]", "halogen": "[F,Cl,Br,I]", "guanidine/amidine": "[NX3]C(=[NX2])[NX3]"}
g["z"] = g.groupby(["target_uniprot", "affinity_type"]).pAff.transform(lambda v: (v - v.mean()) / (v.std() if v.std() > 0 else 1))
uniq = g.drop_duplicates("canon")[["canon"]].copy()
for name, sm in PANEL.items():
    p = Chem.MolFromSmarts(sm); uniq[name] = [Chem.MolFromSmiles(s).HasSubstructMatch(p) for s in uniq.canon]
g = g.merge(uniq, on="canon"); res = []
for name in PANEL:
    E = []; V = []
    for (t, ty), sub in g.groupby(["target_uniprot", "affinity_type"]):
        if len(sub) >= 12:
            e, v = S.smd_within_source(sub.z.values, sub[name].values, 5)
            if np.isfinite(e): E.append(e); V.append(v)
    m = S.dl_meta(E, V); res.append(dict(feature=name, n_units=m["k"], effect_z=m["pooled"], lo=m["lo"], hi=m["hi"], I2=m["I2"], frac_units_positive=float(np.mean(np.array(E) > 0)) if E else np.nan))
pd.DataFrame(res).to_csv(os.path.join(C.HERE, "data", "xprop_binding_smarts.csv"), index=False); print(pd.DataFrame(res).round(3).to_string(index=False), flush=True)

# (3) stability (PepMSND): SMARTS panel odds ratios, cyclic subset counts
st = pd.read_csv(os.path.join(ROOT, "data", "processed", "pepmsnd_stability_folds.csv"))
st = st[~st.label_conflict].copy(); mols = [Chem.MolFromSmiles(s) for s in st.canonical_smiles]; st = st[[m is not None for m in mols]].copy(); mols = [m for m in mols if m is not None]
st["macro"] = [max([len(r) for r in m.GetRingInfo().AtomRings()] or [0]) >= 9 for m in mols]
summary["stability"] = dict(n=int(len(st)), n_stable=int(st.label.sum()), n_macrocyclic=int(st.macro.sum()), n_macrocyclic_stable=int(st[st.macro].label.sum()))
import statsmodels.api as sm
rows = []
for name, sm_ in PANEL.items():
    p = Chem.MolFromSmarts(sm_); f = np.array([m.HasSubstructMatch(p) for m in mols]).astype(float)
    if f.sum() < 10 or (1 - f).sum() < 10: continue
    X = sm.add_constant(np.c_[f]); 
    try:
        r = sm.Logit(st.label.values, X).fit(disp=0, cov_type="cluster", cov_kwds={"groups": st.source_clusters.fillna("-1").astype(str).str.split(";").str[0].astype(int).values})
        rows.append(dict(feature=name, n_present=int(f.sum()), odds_ratio=float(np.exp(r.params[1])), lo=float(np.exp(r.conf_int()[1][0])), hi=float(np.exp(r.conf_int()[1][1]))))
    except Exception as e: rows.append(dict(feature=name, n_present=int(f.sum()), error=str(e)[:60]))
def _stab_or(mask, tag):
    out = []
    for name, sm_ in PANEL.items():
        p = Chem.MolFromSmarts(sm_); f = np.array([m.HasSubstructMatch(p) for m in mols]).astype(float)[mask]
        if f.sum() < 10 or (1 - f).sum() < 10: out.append(dict(subset=tag, feature=name, n_present=int(f.sum()), note="n<10 per side; not analysed")); continue
        X = sm.add_constant(np.c_[f]); grp = st.source_clusters.fillna("-1").astype(str).str.split(";").str[0].astype(int).values[mask]
        try:
            r = sm.Logit(st.label.values[mask], X).fit(disp=0, cov_type="cluster", cov_kwds={"groups": grp})
            out.append(dict(subset=tag, feature=name, n=int(mask.sum()), n_present=int(f.sum()), odds_ratio=float(np.exp(r.params[1])), lo=float(np.exp(r.conf_int()[1][0])), hi=float(np.exp(r.conf_int()[1][1]))))
        except Exception as e: out.append(dict(subset=tag, feature=name, n_present=int(f.sum()), note="fit failed: " + str(e)[:50]))
    return out
rows = _stab_or(np.ones(len(st), bool), "all") + _stab_or(st.macro.values, "macrocyclic")
pd.DataFrame(rows).to_csv(os.path.join(C.HERE, "data", "xprop_stability_or.csv"), index=False); print(pd.DataFrame(rows).round(3).to_string(index=False), flush=True)

# (4) cross-table overlap by exact canonical SMILES
cpm = set(Chem.MolToSmiles(Chem.MolFromSmiles(s)) for s in ann.SMILES.dropna().unique() if Chem.MolFromSmiles(s))
aff = set(g.canon); stab = set(Chem.MolToSmiles(m) for m in mols)
summary["overlap_exact_canonical_smiles"] = dict(cycpeptmpdb_x_binding=len(cpm & aff), cycpeptmpdb_x_stability=len(cpm & stab), binding_x_stability=len(aff & stab), sizes=dict(cpm=len(cpm), binding=len(aff), stability=len(stab)))
ov = ann.assign(canon=[Chem.MolToSmiles(Chem.MolFromSmiles(s)) if isinstance(s, str) else None for s in ann.SMILES]).dropna(subset=["canon"])
ov = ov[ov.pampa.notna()].merge(C.load_labelled()[["y"]], left_index=True, right_index=True).merge(g[["canon", "target_uniprot", "z"]], on="canon")
summary["tradeoff_permeability_vs_binding_exact_overlap"] = dict(n_structure_target_pairs=int(len(ov)), n_structures=int(ov.canon.nunique()), n_targets=int(ov.target_uniprot.nunique()),
        spearman_perm_z_vs_binding_z=(float(spearmanr(ov.y, ov.z)[0]) if len(ov) >= 10 else None), note="descriptive only; permeability z is within source, binding z within target x assay type; claimed only if n>=30 structures")
# (5) profiles: renal and macroconf
rj = [json.loads(l) for l in open(os.path.join(ROOT, "renal", "renal_seed_corpus.jsonl"))]
nn = collections.Counter(k for r in rj for k, v in r.items() if v not in (None, "", []))
summary["renal"] = dict(n=len(rj), non_null_counts={k: nn[k] for k in ("kidney_pid_g_1h", "kidney_pid_g_4h", "kidney_pid_g_24h", "tumour_pid_g", "tk_ratio", "kidney_gy_per_gbq", "net_charge_pH74", "logD_pH74")})
mc = pd.read_csv(os.path.join(ROOT, "data", "raw", "macroconf", "1fa6a74345334bae2235b3775180f209a1c923ed", "data", "dataset.csv"))
summary["macroconf"] = dict(n=int(len(mc)), natural=int(mc["is natural cyclic peptide"].astype(str).str.lower().isin(["true", "1", "yes"]).sum()), unnatural=int(mc["is unnatural cyclic peptide"].astype(str).str.lower().isin(["true", "1", "yes"]).sum()))
summary["solubility"] = "no cyclic-peptide solubility data in the repo; not analysed"
json.dump(summary, open(os.path.join(C.HERE, "data", "xprop_summary.json"), "w"), indent=1, default=str); print(json.dumps(summary, indent=1, default=str)[:3000])
