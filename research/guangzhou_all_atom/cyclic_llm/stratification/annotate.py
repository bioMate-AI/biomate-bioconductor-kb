"""Per-peptide structural annotation for CycPeptMPDB (HELM + Sequence + SMILES). See docs/20261029_CYCLIC_PEPTIDE_STRATIFICATION_ANALYSIS.md Part A (A1)."""
import ast, re, sys, os
import numpy as np, pandas as pd
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import tokens as T
from rdkit import Chem, RDLogger
from rdkit.Chem import Descriptors, Crippen, rdMolDescriptors
from rdkit.Chem.Scaffolds import MurckoScaffold
RDLogger.DisableLog("rdApp.*")

CONN_RE = re.compile(r"PEPTIDE\d+,PEPTIDE\d+,(\d+):(R\d)-(\d+):(R\d)")
NME_AMIDE = Chem.MolFromSmarts("[CX3](=O)[NX3]([CH3])[#6]")
AMIDE_BB = Chem.MolFromSmarts("[CX4;$(C[NX3])][CX3](=O)[NX3]")   # backbone amide: carbonyl attached to an N-bearing (alpha) carbon
AMIDE_CAP = Chem.MolFromSmarts("[CH3][CX3](=O)[NX3]")              # N-acetyl cap
ALPHA_H = Chem.MolFromSmarts("[NX3][CX4;H1]([#6])[CX3](=O)[#7,#8]")
COMPS = ("aliphatic", "aromatic", "polar", "positive", "negative", "proline")


def parse_helm(helm):
    toks = [t.strip("[]") for t in re.search(r"\{(.*?)\}", helm).group(1).split(".")]
    m = CONN_RE.search(helm)
    conn = (int(m.group(1)), m.group(2), int(m.group(3)), m.group(4)) if m else None
    return toks, conn


def topology_from_conn(conn, n):
    """-> (class, ring_start, ring_end) with 1-based inclusive residue positions in the HELM list."""
    if conn is None: return "none", None, None
    a, ra, b, rb = conn
    pair = {ra, rb}
    if pair == {"R1", "R2"}: return "head_to_tail", 1, n
    if pair == {"R3", "R2"}:
        i = a if ra == "R3" else b; return "lariat_sc_cterm", i, n
    if pair == {"R1", "R3"}:
        j = a if ra == "R3" else b; return "lariat_nterm_sc", 1, j
    if pair == {"R3"}: return "sc_sc", min(a, b), max(a, b)
    return "other", None, None


def _runs(flags):
    best = cur = 0
    for f in flags:
        cur = cur + 1 if f else 0; best = max(best, cur)
    return best


def pattern_feats(flags, cyclic):
    """adjacent pairs, (i, i+2) 'alternating' triples flag-nonflag-flag, and longest run; wrap-around only for head-to-tail rings."""
    f = list(flags); n = len(f)
    if n == 0: return dict(adj=0, alt=0, run=0)
    wrap = cyclic and n > 2
    if wrap:
        adj = sum(1 for i in range(n) if f[i] and f[(i + 1) % n])
        alt = sum(1 for i in range(n) if f[i] and (not f[(i + 1) % n]) and f[(i + 2) % n]) if n > 3 else 0
        run = min(_runs(f + f), n)
    else:
        adj = sum(1 for i in range(n - 1) if f[i] and f[i + 1])
        alt = sum(1 for i in range(n - 2) if f[i] and (not f[i + 1]) and f[i + 2])
        run = _runs(f)
    return dict(adj=int(adj), alt=int(alt), run=int(run))


def annotate_one(helm, smiles):
    toks, conn = parse_helm(helm)
    cls = [T.classify(t) for t in toks]
    n = len(toks)
    topo, rs, re_ = topology_from_conn(conn, n)
    main = [(i, c) for i, c in enumerate(cls, 1) if c["kind"] in ("residue", "unknown")]
    res = [c for _, c in main]
    nres = len(res)
    cyc = topo == "head_to_tail"
    nme = [c["is_nme"] for c in res]; D = [c["is_D"] for c in res]; pro = [c["is_pro_like"] for c in res]
    pf_n = pattern_feats(nme, cyc); pf_d = pattern_feats(D, cyc)
    a = dict(helm_topology=topo, n_monomers=n, n_residues=nres,
             ring_res=(None if rs is None else re_ - rs + 1), tail_res=(None if rs is None else n - (re_ - rs + 1)),
             n_cap_n=sum(c["is_cap_n"] for c in cls), n_cap_c=sum(c["is_cap_c"] for c in cls),
             n_nme=sum(nme), nme_frac=(sum(nme) / nres if nres else 0), nme_adj=pf_n["adj"], nme_alt=pf_n["alt"], nme_run=pf_n["run"],
             n_D=sum(D), d_frac=(sum(D) / nres if nres else 0), d_adj=pf_d["adj"], d_alt=pf_d["alt"], d_run=pf_d["run"],
             n_D_and_nme=sum(1 for c in res if c["is_D"] and c["is_nme"]),
             n_pro=sum(pro), n_dpro=sum(1 for c in res if c["is_D"] and c["is_pro_like"]),
             n_gly=sum(1 for c in res if c["base"] in ("G", "Gly") and not c["is_nme"] and not c["is_peptoid"]),
             n_peptoid=sum(c["is_peptoid"] for c in res), n_nalkyl=sum(c["is_nalkyl"] for c in res),
             n_ext=sum(c["is_ext_backbone"] for c in res), n_alpha_disub=sum(c["is_alpha_disub"] for c in res),
             n_backbone_mod=sum(c["is_backbone_mod"] for c in res), n_unknown=sum(c["is_unknown"] for c in res),
             n_sidechain_mod=sum(c["is_sidechain_mod"] for c in res),
             n_nonstd_base=sum(1 for c in res if (c["base"] not in T.STD_SET) and not c["is_unknown"]),
             nme_adj_pro=sum(1 for i in range(nres) if nme[i] and ((i > 0 and pro[i - 1]) or (i < nres - 1 and pro[i + 1]) or (cyc and (pro[i - 1] or pro[(i + 1) % nres])))) if nres else 0,
             nme_adj_D=sum(1 for i in range(nres) if nme[i] and ((i > 0 and D[i - 1]) or (i < nres - 1 and D[i + 1]) or (cyc and (D[i - 1] or D[(i + 1) % nres])))) if nres else 0,
             nme_pos=[i + 1 for i, f in enumerate(nme) if f], d_pos=[i + 1 for i, f in enumerate(D) if f],
             cap_n_tok=next((c["tok"] for c in cls if c["is_cap_n"]), ""), cap_c_tok=next((c["tok"] for c in cls if c["is_cap_c"]), ""))
    for k in COMPS: a["frac_" + k] = (sum(1 for c in res if c["comp"] == k) / nres) if nres else 0
    a["frac_unknown"] = a["n_unknown"] / nres if nres else 0
    a["frac_other"] = (sum(1 for c in res if c["comp"] == "other" and not c["is_unknown"]) / nres) if nres else 0
    # RDKit
    m = Chem.MolFromSmiles(smiles) if isinstance(smiles, str) else None
    if m is None:
        a["rdkit_ok"] = False; return a
    a["rdkit_ok"] = True
    ri = m.GetRingInfo(); rings = ri.AtomRings()
    a["ring_atoms_max"] = max([len(r) for r in rings] or [0]); a["n_rings"] = len(rings)
    flat = Chem.MolToSmiles(m, isomericSmiles=False); a["flat_smiles"] = flat
    try:
        sc = MurckoScaffold.GetScaffoldForMol(Chem.MolFromSmiles(flat)); a["flat_scaffold"] = Chem.MolToSmiles(sc, isomericSmiles=False)
    except Exception: a["flat_scaffold"] = ""
    a["mw"] = Descriptors.MolWt(m); a["tpsa"] = rdMolDescriptors.CalcTPSA(m); a["logp"] = Crippen.MolLogP(m)
    a["hbd"] = rdMolDescriptors.CalcNumHBD(m); a["hba"] = rdMolDescriptors.CalcNumHBA(m); a["rotb"] = rdMolDescriptors.CalcNumRotatableBonds(m)
    a["arom_rings"] = rdMolDescriptors.CalcNumAromaticRings(m); a["heavy"] = m.GetNumHeavyAtoms(); a["fsp3"] = rdMolDescriptors.CalcFractionCSP3(m)
    a["nme_smarts"] = len({mt[2] for mt in m.GetSubstructMatches(NME_AMIDE)})
    a["n_nme_final"] = a["nme_smarts"]            # SMILES-derived count is authoritative (anonymous Mono tokens can hide N-methyl); token n_nme is a lower bound when n_unknown > 0
    a["rdkit_topology"] = rdkit_topology(m)
    return a


def rdkit_topology(m):
    """SMILES-only topology rule T2: head_to_tail if every backbone amide (and N-acetyl cap) has both atoms in the largest ring, else lariat.
    Known limitation: rings closed through an Asp/Glu side chain with an alpha-carboxyl cap (e.g. Asp_piperidide) are called lariat."""
    ri = m.GetRingInfo(); rings = ri.AtomRings()
    if not rings: return "acyclic"
    big = max(rings, key=len)
    if len(big) < 9: return "no_macrocycle"
    bs = set(big)
    ams = list(m.GetSubstructMatches(AMIDE_BB)) + list(m.GetSubstructMatches(AMIDE_CAP))      # (C, C=O, O, N)
    return "head_to_tail" if all(mt[1] in bs and mt[3] in bs for mt in ams) else "lariat"


def cip_backbone_counts(m):
    """(n_R, n_S, n_alpha): CIP labels at backbone alpha carbons carrying one H, a carbon side chain and a carbonyl (new CIP labeller)."""
    from rdkit.Chem import rdCIPLabeler
    rdCIPLabeler.AssignCIPLabels(m)
    al = {mt[1] for mt in m.GetSubstructMatches(ALPHA_H)}
    lab = [m.GetAtomWithIdx(a).GetProp("_CIPCode") if m.GetAtomWithIdx(a).HasProp("_CIPCode") else "?" for a in al]
    return lab.count("R"), lab.count("S"), len(al)
