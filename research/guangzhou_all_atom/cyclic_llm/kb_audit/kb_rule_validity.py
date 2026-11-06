"""Leak-safe, source-aware validity test for knowledge-base rules about peptide properties.

Why: pooled literature data are confounded by laboratory/source (one lab holds >50 % of top hits), so a rule can
look strong pooled and be flat or reversed within laboratories. This harness scores any per-peptide feature against
within-source-standardised labels and reports: pooled rho (for contrast), median within-source rho over sources
with >= MIN_N peptides, number of sources with each sign, a source-bootstrap CI of the median, and replication in
two disjoint source halves (halves by sha256(source) so assignment is deterministic and independent of results).
A rule is VALIDATED only if the CI excludes 0 in the KB-claimed direction AND both halves agree in sign;
CONTRADICTED if the CI excludes 0 in the opposite direction; otherwise INCONCLUSIVE. Rules are never tuned here.

Reads CycPeptMPDB (path via env CYCPEP_CSV) and re-uses the monomer-token classifier of the stratification
workstream READ-ONLY (stratification/tokens.py). No labels enter feature construction.
"""
from __future__ import annotations
import ast, hashlib, importlib.util, os
import numpy as np
import pandas as pd
from scipy.stats import spearmanr

HERE = os.path.dirname(os.path.abspath(__file__))
MIN_N = 20


def _tokens():
    spec = importlib.util.spec_from_file_location("tokens", os.path.join(HERE, "..", "stratification", "tokens.py"))
    m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m); return m


def zscore_within(y, groups):
    y = np.asarray(y, float); out = np.zeros(len(y)); g = np.asarray(groups)
    for s in set(g.tolist()):
        m = g == s; sd = y[m].std(); out[m] = (y[m] - y[m].mean()) / (sd if sd > 0 else 1.0)
    return out


def within_source_stats(x, y, source, B=2000, seed=0, min_n=MIN_N):
    """x: feature, y: raw labels, source: group ids. Returns dict of within-source summary + replication."""
    x = np.asarray(x, float); y = np.asarray(y, float); src = np.asarray(source)
    rhos, names, ns = [], [], []
    for s in sorted(set(src.tolist())):
        m = src == s
        if m.sum() >= min_n and np.std(x[m]) > 0 and np.std(y[m]) > 0:
            rhos.append(spearmanr(x[m], y[m])[0]); names.append(s); ns.append(int(m.sum()))
    rhos = np.array(rhos)
    if len(rhos) < 4:
        return dict(n_sources=len(rhos), verdict_basis="too few sources")
    rng = np.random.default_rng(seed)
    boots = [np.median(rhos[rng.integers(0, len(rhos), len(rhos))]) for _ in range(B)]
    half = np.array([int(hashlib.sha256(n.encode()).hexdigest(), 16) % 2 for n in names])
    med = [float(np.median(rhos[half == h])) if (half == h).sum() >= 2 else float("nan") for h in (0, 1)]
    ok = np.isfinite(x) & np.isfinite(y)
    return dict(n_sources=len(rhos), n_peptides=int(sum(ns)), pooled_rho=float(spearmanr(x[ok], y[ok])[0]),
                median_within_rho=float(np.median(rhos)), ci95=[float(np.percentile(boots, 2.5)), float(np.percentile(boots, 97.5))],
                n_pos=int((rhos > 0).sum()), n_neg=int((rhos < 0).sum()), half_medians=med)


def verdict(st, claimed_sign):
    """claimed_sign: +1 / -1 (KB-claimed direction) or 0 (no direction claimed -> descriptive only)."""
    if "median_within_rho" not in st: return "INSUFFICIENT"
    lo, hi = st["ci95"]; h = st["half_medians"]
    if claimed_sign == 0: return "NO_CLAIM(descriptive)"
    if claimed_sign * lo > 0 and claimed_sign * hi > 0 and all(np.isfinite(h)) and all(claimed_sign * v > 0 for v in h): return "VALIDATED"
    if (-claimed_sign) * lo > 0 and (-claimed_sign) * hi > 0: return "CONTRADICTED"
    return "INCONCLUSIVE"


def build_table(csv_path):
    from rdkit import Chem, RDLogger
    from rdkit.Chem import Crippen, Descriptors, rdMolDescriptors
    RDLogger.DisableLog("rdApp.*"); T = _tokens()
    d = pd.read_csv(csv_path, low_memory=False)
    d = d[d["PAMPA"].notna() & (d["Permeability"] > -9.99)]
    g = d.groupby("Structurally_Unique_ID")
    p = g.agg(y=("PAMPA", "mean"), source=("Source", "first"), seq=("Sequence", "first"), smiles=("SMILES", "first")).reset_index()
    rows = []
    for r in p.itertuples():
        m = Chem.MolFromSmiles(r.smiles)
        if m is None: continue
        toks = [T.classify(t) for t in ast.literal_eval(r.seq)]; res = [t for t in toks if t["kind"] == "residue"]
        nres = max(len(res), 1)
        comp = lambda c: sum(t["comp"] == c for t in res) / nres
        tpsa = rdMolDescriptors.CalcTPSA(m); hbd = rdMolDescriptors.CalcNumHBD(m); hba = rdMolDescriptors.CalcNumHBA(m)
        logp = Crippen.MolLogP(m); mw = Descriptors.MolWt(m); rotb = rdMolDescriptors.CalcNumRotatableBonds(m)
        ring = max([len(x) for x in m.GetRingInfo().AtomRings()] or [0])
        rows.append(dict(sid=r.Structurally_Unique_ID, y=r.y, source=r.source, n_res=len(res),
                         n_nme=sum(t["is_nme"] for t in res), frac_nme=sum(t["is_nme"] for t in res) / nres,
                         n_D=sum(t["is_D"] for t in res), frac_D=sum(t["is_D"] for t in res) / nres,
                         frac_arom=comp("aromatic"), frac_aliph=comp("aliphatic"), frac_polar=comp("polar"),
                         n_pos=sum(t["comp"] == "positive" for t in res), n_neg=sum(t["comp"] == "negative" for t in res),
                         n_pro=sum(t["comp"] == "proline" for t in res),
                         tpsa=tpsa, hbd=hbd, hba=hba, logp=logp, mw=mw, rotb=rotb, ring=ring, heavy=m.GetNumHeavyAtoms(),
                         ro5_pass=float((mw <= 500) & (logp <= 5) & (hbd <= 5) & (hba <= 10)),
                         veber_pass=float((tpsa <= 140) & (rotb <= 10))))
    t = pd.DataFrame(rows); t["net_charge"] = t.n_pos - t.n_neg
    return t


# feature -> (KB-claimed sign for PERMEABILITY or 0 when the KB makes no permeability claim, KB source of the claim)
RULES = {
    "n_nme":       (+1, "modality: backbone N-methylation raises permeability (Biron 2008; medchem_kb MODALITY_HEURISTICS)"),
    "frac_nme":    (+1, "same, normalised by length"),
    "tpsa":        (-1, "physchem: bRo5/chameleon (Rezai 2006, Over 2016, Doak 2014): lower exposed polarity favours permeability"),
    "hbd":         (-1, "physchem: Ro5/Veber/bRo5 donor limits"),
    "logp":        (+1, "physchem: lipophilicity favours passive permeability (Ro5 family)"),
    "ro5_pass":    (+1, "physchem: Lipinski Ro5 (medchem_kb PHYSCHEM)"),
    "veber_pass":  (+1, "physchem: Veber"),
    "mw":          (-1, "physchem: Ro5 MW limit"),
    "n_D":         (0,  "modality: D-amino acids -> protease resistance / conformational control (no permeability claim)"),
    "ring":        (0,  "modality: macrocyclisation rigidifies (no size claim)"),
    "n_pos":       (0,  "knowledge_liability_flags: cationic charge raises RENAL dose (no permeability claim)"),
    "net_charge":  (0,  "same"),
    "frac_arom":   (0,  "availability model: hydrophobicity lowers cellular availability (linear SH3 peptides; no cyclic permeability claim)"),
    "n_res":       (0,  "none"),
}


def run(csv_path, B=2000):
    t = build_table(csv_path); t["yz"] = zscore_within(t.y, t.source)
    out = {}
    for f, (sign, why) in RULES.items():
        st = within_source_stats(t[f].values, t.y.values, t.source.values, B=B)
        st["claimed_sign"] = sign; st["kb_basis"] = why; st["verdict"] = verdict(st, sign); out[f] = st
    return out, t


if __name__ == "__main__":
    import json, sys
    res, t = run(os.environ["CYCPEP_CSV"])
    json.dump(res, open(os.path.join(HERE, "kb_rule_validity_result.json"), "w"), indent=1, default=float)
    print("n peptides", len(t))
    for f, st in res.items():
        if "median_within_rho" in st:
            print("%-11s claimed %+d  pooled %.3f  within-median %.3f CI [%.3f,%.3f]  src +%d/-%d  halves %s  -> %s" % (
                f, st["claimed_sign"], st["pooled_rho"], st["median_within_rho"], st["ci95"][0], st["ci95"][1], st["n_pos"], st["n_neg"],
                ["%.2f" % h for h in st["half_medians"]], st["verdict"]))
