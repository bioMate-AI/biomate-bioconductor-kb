"""Chemistry helpers for the retrospective recovery study. Pure RDKit, deterministic.
Strata (heuristic, documented in the prereg amendment A2):
  non_peptide_macrocycle : ring >= 9 and >= 3 backbone amides but < 4 alpha-amino-acid units
  ncaa_peptide           : >= 4 alpha-amino-acid units and any of: non-canonical side chain, D-residue (incl. D-Pro), N-substituted backbone amide
                           (N-methyl, peptoid N-alkyl; Pro excluded), alpha,alpha-disubstituted residue, non-natural cross-link (anything other than
                           Cys-Cys disulfide), or a backbone that is not purely alpha-amino-acid (amide N count != alpha-carbon count, e.g. beta-amino acids)
  peptide                : >= 4 alpha-amino-acid units, all canonical L side chains, no N-methyl, only disulfide cross-links
"""
from rdkit import Chem, RDLogger
from rdkit.Chem import rdMolDescriptors
RDLogger.DisableLog("rdApp.*")

AMIDE = Chem.MolFromSmarts("C(=O)N[CX4]")                       # same definition as the prereg audit
ALPHA = Chem.MolFromSmarts("[CX4;$([CX4]([NX3])[CX3]=O)]")     # alpha carbon: bonded to N and to a carbonyl carbon
NME = Chem.MolFromSmarts("[CX3](=O)[NX3]([CH3])[CX4]")
GUAN = Chem.MolFromSmarts("[NX3;!$(NC=O)]C(=[NX2,NX3+])[NX3;!$(NC=O)]")
AMINE = Chem.MolFromSmarts("[NX3;H2,H1;!$(N-C=[O,N,S]);!$(N-S(=O)=O);!$(Na);!$(N-C=C)][CX4]")
ACID = Chem.MolFromSmarts("[CX3](=O)[OX2H1,OX1-]")
RGD = Chem.MolFromSmarts("[NX3;!$(NC=O)]C(=[NX2,NX3+])[NX3]CCC[CX4]([NX3])C(=O)[NX3][CH2]C(=O)[NX3][CX4]CC(=O)[OX2H1,OX1-]")  # Arg-Gly-Asp, free Asp acid
CANON = "ACDEFGHIKLMNPQRSTVWY"
_cache = {}


def largest_fragment(m):
    frags = Chem.GetMolFrags(m, asMols=True)
    return max(frags, key=lambda x: x.GetNumHeavyAtoms()) if len(frags) > 1 else m


def parse(smi):
    m = Chem.MolFromSmiles(smi) if isinstance(smi, str) else None
    return largest_fragment(m) if m is not None else None


def keys(m):
    return Chem.MolToSmiles(m), Chem.MolToSmiles(m, isomericSmiles=False)


def max_ring(m):
    return max([len(r) for r in m.GetRingInfo().AtomRings()] or [0])


def _side_fragments(m):
    """-> list of (alpha_idx, side_chain_smiles(no stereo) or None for Gly/Pro-handled, n_sub) via cutting alpha-C -- side-chain bonds."""
    alphas = [a[0] for a in m.GetSubstructMatches(ALPHA)]
    cuts, meta = [], {}
    for ai in alphas:
        a = m.GetAtomWithIdx(ai)
        bb = set()
        for nb in a.GetNeighbors():
            if nb.GetSymbol() == "N" or (nb.GetSymbol() == "C" and any(b.GetBondType() == Chem.BondType.DOUBLE and b.GetOtherAtom(nb).GetSymbol() == "O" for b in nb.GetBonds())):
                bb.add(nb.GetIdx())
        sides = [nb.GetIdx() for nb in a.GetNeighbors() if nb.GetIdx() not in bb and nb.GetAtomicNum() > 1]
        meta[ai] = sides
        for s in sides:
            cuts.append(m.GetBondBetweenAtoms(ai, s).GetIdx())
    return alphas, meta, cuts


def _frag_smiles(m, alphas, meta, cuts):
    if not cuts:
        return {}
    fm = Chem.FragmentOnBonds(m, sorted(set(cuts)), addDummies=True, dummyLabels=[(0, 0)] * len(set(cuts)))
    out = {}
    pieces = Chem.GetMolFrags(fm, asMols=False, sanitizeFrags=False)
    frag_of = {a: i for i, p in enumerate(pieces) for a in p}
    for ai in alphas:
        for s in meta[ai]:
            fi = frag_of[s]
            sub = Chem.PathToSubmol  # placeholder to keep linter quiet
            atoms = set(pieces[fi])
            em = Chem.RWMol(fm)
            for idx in sorted([x.GetIdx() for x in fm.GetAtoms() if x.GetIdx() not in atoms], reverse=True):
                em.RemoveAtom(idx)
            mol = em.GetMol()
            try:
                Chem.SanitizeMol(mol)
            except Exception:
                pass
            out[(ai, s)] = Chem.MolToSmiles(mol, isomericSmiles=False)
    return out


def _canonical_sidechains():
    if "sc" in _cache:
        return _cache["sc"]
    sc = {}
    for aa in CANON:
        m = Chem.MolFromSequence("G" + aa + "G")
        alphas, meta, cuts = _side_fragments(m)
        fr = _frag_smiles(m, alphas, meta, cuts)
        # the middle residue is the second alpha carbon
        mid = sorted(alphas)[1]
        for (ai, s), smi in fr.items():
            if ai == mid:
                sc.setdefault(aa, set()).add(smi)
    _cache["sc"] = sc
    return sc


def _is_pro_like(m, ai, sides):
    """Pro: alpha carbon's side chain returns to the backbone N through a 5-ring."""
    a = m.GetAtomWithIdx(ai)
    ring = m.GetRingInfo()
    for nb in a.GetNeighbors():
        if nb.GetSymbol() == "N":
            for r in ring.AtomRings():
                if ai in r and nb.GetIdx() in r and len(r) == 5:
                    return True
    return False


def classify(m):
    """-> dict(stratum, n_alpha, n_nme, n_noncanon, n_d, n_disub, n_other_bridge)."""
    alphas, meta, cuts = _side_fragments(m)
    n_alpha = len(alphas)
    nme = len(m.GetSubstructMatches(NME))
    # N-substituted backbone amide N (N-Me, peptoid), excluding proline-type ring N
    nsub = 0
    for ai in alphas:
        a = m.GetAtomWithIdx(ai)
        for nb in a.GetNeighbors():
            if nb.GetSymbol() == "N" and nb.GetDegree() >= 3 and not any(ai in r and nb.GetIdx() in r and len(r) <= 6 for r in m.GetRingInfo().AtomRings()):   # ring N of Pro/Pip excluded; macrocycle ring does not count
                nsub += 1
    amideN = {mt[2] for mt in m.GetSubstructMatches(AMIDE)}
    res = dict(n_alpha=n_alpha, n_nme=nme, n_nsub=nsub, n_amideN=len(amideN), n_noncanon=0, n_d=0, n_disub=0, n_bridge_noncanon=0, n_backbone_mismatch=0)
    if n_alpha < 4:
        res["stratum"] = "non_peptide_macrocycle"
        return res
    canon = _canonical_sidechains()
    allowed = {smi for v in canon.values() for smi in v}
    cip = dict(Chem.FindMolChiralCenters(m, includeUnassigned=True, useLegacyImplementation=False))
    # side-chain fragments; those that bridge two residues (disulfide) appear identically for both attachment points
    frs = {}
    if cuts:
        fm = Chem.FragmentOnBonds(m, sorted(set(cuts)), addDummies=True, dummyLabels=[(0, 0)] * len(set(cuts)))
        pieces = Chem.GetMolFrags(fm, asMols=False, sanitizeFrags=False)
        frag_of = {a: i for i, p in enumerate(pieces) for a in p}
        for ai in alphas:
            for s in meta[ai]:
                frs[(ai, s)] = frag_of[s]
        by_piece = {}
        for (ai, s), fi in frs.items():
            by_piece.setdefault(fi, []).append((ai, s))
        sm = _frag_smiles(m, alphas, meta, cuts)
    for ai in alphas:
        sides = meta[ai]
        if len(sides) == 0:
            continue                     # Gly
        if len(sides) >= 2 and not _is_pro_like(m, ai, sides):
            res["n_disub"] += 1
            continue
        if _is_pro_like(m, ai, sides):
            tag = cip.get(ai)
            if tag == "R":               # L-Pro is S; R = D-Pro
                res["n_d"] += 1
            continue                     # Pro / ring-closed to N: canonical proline chemistry (4-substituted prolines are not resolved here)
        s = sides[0]
        piece = frs[(ai, s)]
        members = by_piece[piece]
        if len(members) == 2:             # bridging side chains (e.g. disulfide) -> canonical only if S-S between two Cys-like CH2
            smi = sm[(ai, s)]
            if "SS" in smi.replace("[", "").replace("]", "") and smi.count("*") == 2:
                pass
            else:
                res["n_bridge_noncanon"] += 1
            tag = cip.get(ai)
            continue
        if len(members) > 2:
            res["n_bridge_noncanon"] += 1
            continue
        smi = sm[(ai, s)]
        if smi not in allowed:
            res["n_noncanon"] += 1
        else:
            tag = cip.get(ai)
            is_cys = smi in canon["C"]
            if tag is not None and ((tag == "R") != is_cys):   # L-amino acids are S (Cys is R)
                res["n_d"] += 1
    res["n_backbone_mismatch"] = int(abs(len(amideN) - n_alpha) >= 1)
    ncaa = res["n_nsub"] + res["n_noncanon"] + res["n_d"] + res["n_disub"] + res["n_bridge_noncanon"] + res["n_backbone_mismatch"] > 0
    res["stratum"] = "ncaa_peptide" if ncaa else "peptide"
    return res


def approx_charge(m):
    return len(m.GetSubstructMatches(GUAN)) + len(m.GetSubstructMatches(AMINE)) - len(m.GetSubstructMatches(ACID))


def has_rgd(m):
    return m.HasSubstructMatch(RGD)


def descriptors(m):
    return dict(heavy=m.GetNumHeavyAtoms(), ring=max_ring(m), amide=len(m.GetSubstructMatches(AMIDE)), charge=approx_charge(m),
                n_arom=rdMolDescriptors.CalcNumAromaticRings(m), rgd=bool(has_rgd(m)))
