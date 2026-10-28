"""SMILES -> monomer sequence (v4 vocabulary) for peptide macrocycles. Deterministic, RDKit only.

Residue units are found as N-Calpha-C(=O) backbone triples; peptide bonds C(=O)-N between units are cut, each unit is capped (N-H, C(=O)OH) and named by
canonical isomeric SMILES against a dictionary: L-canonical ('A'), D ('dA'), N-methyl ('meA'; 'Sar' for N-Me-Gly) and, optionally, extra ncAA tokens learned
from CycPeptMPDB (learn_ncaa_dictionary). Unmapped units -> None. A compound is `complete` only if every unit is mapped and the backbone order is unambiguous.
Cyclic backbones have no start: `rotations` returns all rotations (callers average the score)."""
import re
from rdkit import Chem, RDLogger
RDLogger.DisableLog("rdApp.*")

L_SMILES = {  # free amino acids, L (as drawn by RDKit MolFromSequence)
}
_CANON = "ACDEFGHIKLMNPQRSTVWY"


def _canon_smi(m):
    return Chem.MolToSmiles(m, isomericSmiles=True)


# tautomer drawings that differ only in H placement (stereo-preserving string alternates; RDKit's tautomer canonicaliser was tried and rejected: it strips stereo)
_ALTS = [("N=C(N)N", "NC(N)=N"), ("N=C(N)N", "NC(=N)N"), ("c1c[nH]cn1", "c1cnc[nH]1"), ("c1cnc[nH]1", "c1c[nH]cn1"), ("c1nc[nH]c1", "c1ncc[nH]1")]


def _add_tautomer_alternates(d):
    for key, tok in list(d.items()):
        for a, b in _ALTS:
            if a in key:
                m = Chem.MolFromSmiles(key.replace(a, b))
                if m is not None: d.setdefault(_canon_smi(m), tok)
    return d


def _build_base():
    d = {}
    for aa in _CANON:
        m = Chem.MolFromSequence(aa)
        d[_canon_smi(m)] = aa
        # D form: invert all tetrahedral stereocentres
        mm = Chem.Mol(m)
        for a in mm.GetAtoms():
            t = a.GetChiralTag()
            if t == Chem.ChiralType.CHI_TETRAHEDRAL_CW: a.SetChiralTag(Chem.ChiralType.CHI_TETRAHEDRAL_CCW)
            elif t == Chem.ChiralType.CHI_TETRAHEDRAL_CCW: a.SetChiralTag(Chem.ChiralType.CHI_TETRAHEDRAL_CW)
        if aa != "G": d[_canon_smi(mm)] = "d" + aa
        # N-methyl (not for proline: N already substituted by the ring)
        for src, pre in ((m, "me"), (mm, "dme")):
            if aa == "P" or (aa == "G" and pre == "dme"): continue
            patt = Chem.MolFromSmarts("[NX3;H2]-[CX4]-C(=O)O")
            hit = src.GetSubstructMatch(patt)
            if not hit: continue
            rw = Chem.RWMol(src); n = rw.AddAtom(Chem.Atom(6)); rw.AddBond(hit[0], n, Chem.BondType.SINGLE)
            try: Chem.SanitizeMol(rw)
            except Exception: continue
            name = "Sar" if aa == "G" else (pre + aa if pre == "me" else "Me_d" + aa)
            d[_canon_smi(rw)] = name
    return d


BASE = _add_tautomer_alternates(_build_base())
BACKBONE = Chem.MolFromSmarts("[NX3:1]-[CX4:2]-[CX3:3](=[O:4])")


def _units(m):
    """-> list of dict(N, CA, C, O) for backbone triples, de-duplicated by (N,C)."""
    seen = {}
    for N, CA, C, O in m.GetSubstructMatches(BACKBONE):
        seen[(N, C)] = (N, CA, C, O)
    return list(seen.values())


def _segment(smi, dictionary=None):
    """-> dict(ok, tokens(list in backbone order or None), cyclic, unmapped(list of fragment SMILES), n_units, coverage)."""
    dictionary = dictionary if dictionary is not None else BASE
    m = Chem.MolFromSmiles(smi) if isinstance(smi, str) else None
    if m is None: return dict(ok=False, why="parse")
    frags = Chem.GetMolFrags(m, asMols=False)
    if len(frags) > 1:   # keep the largest fragment
        keep = max(frags, key=len); m = Chem.RWMol(m);
        for a in sorted([i for f in frags for i in f if f is not keep], reverse=True): m.RemoveAtom(a)
        m = m.GetMol(); Chem.SanitizeMol(m)
    U = _units(m)
    if len(U) < 3: return dict(ok=False, why="few_units", n_units=len(U))
    Nof = {u[0]: i for i, u in enumerate(U)}; Cof = {u[2]: i for i, u in enumerate(U)}
    # peptide bonds: carbonyl C of unit i bonded to N of unit j
    link = {}; cut = []   # note: cut may contain duplicates on branched topologies; deduplicated below
    for i, u in enumerate(U):
        for nb in m.GetAtomWithIdx(u[2]).GetNeighbors():
            if nb.GetIdx() in Nof and nb.GetIdx() != u[0]:
                j = Nof[nb.GetIdx()]; link[i] = j; cut.append(m.GetBondBetweenAtoms(u[2], nb.GetIdx()).GetIdx())
    cut = sorted(set(cut))
    if not cut: return dict(ok=False, why="no_peptide_bonds", n_units=len(U))
    fm = Chem.FragmentOnBonds(m, cut, addDummies=True)
    comps = Chem.GetMolFrags(fm, asMols=False, sanitizeFrags=False)
    atom2comp = {a: ci for ci, c in enumerate(comps) for a in c}
    # each component must contain exactly one unit CA
    comp_units = {}
    for i, u in enumerate(U): comp_units.setdefault(atom2comp[u[1]], []).append(i)
    names = [None] * len(U); unmapped = []
    for ci, uis in comp_units.items():
        if len(uis) != 1:
            for i in uis: unmapped.append("<merged>")
            continue
        i = uis[0]; atoms = set(comps[ci])
        rw = Chem.RWMol(fm)
        drop = [a for a in range(rw.GetNumAtoms()) if a not in atoms]
        # convert dummies: next to N -> remove (H); next to carbonyl C -> O (OH)
        for a in sorted(atoms):
            at = rw.GetAtomWithIdx(a)
            if at.GetAtomicNum() == 0:
                nbr = at.GetNeighbors()[0]
                if nbr.GetSymbol() == "C": at.SetAtomicNum(8); at.SetIsotope(0); at.SetNoImplicit(False)
                else: drop.append(a)
        for a in sorted(set(drop), reverse=True): rw.RemoveAtom(a)
        try:
            Chem.SanitizeMol(rw); s = _canon_smi(rw)
        except Exception:
            names[i] = None; unmapped.append("<sanitize>"); continue
        tok = dictionary.get(s)
        names[i] = tok
        if tok is None: unmapped.append(s)
    # backbone order
    starts = [i for i in range(len(U)) if i not in set(link.values())]
    cyc = len(starts) == 0
    order = None
    if cyc:
        i0 = 0; order = [i0]; j = link.get(i0)
        while j is not None and j != i0 and len(order) <= len(U): order.append(j); j = link.get(j)
        if len(order) != len(U) or j != i0: order = None
    elif len(starts) == 1:
        order = [starts[0]]; j = link.get(order[0])
        while j is not None and len(order) <= len(U): order.append(j); j = link.get(j)
        if len(order) != len(U): order = None
    if order is None: return dict(ok=False, why="ambiguous_backbone", n_units=len(U), unmapped=unmapped)
    toks = [names[i] for i in order]
    mapped = sum(t is not None for t in toks)
    return dict(ok=True, tokens=toks, cyclic=cyc, n_units=len(U), coverage=mapped / len(U), complete=(mapped == len(U)), unmapped=unmapped)


def rotations(tokens):
    return [tokens[i:] + tokens[:i] for i in range(len(tokens))]


def canonical_rotation(tokens):
    return min(rotations(tokens))


def learn_ncaa_dictionary(rows):
    """rows: iterable of (smiles, monomer_list). For peptides with exactly one unmapped unit and exactly one monomer token not explained by the base dictionary
    (multiset difference), learn fragment-SMILES -> token. Returns (dictionary, conflicts)."""
    from collections import Counter, defaultdict
    cand = defaultdict(Counter)
    for smi, mons in rows:
        r = segment(smi)
        if not r.get("ok") or len(r.get("unmapped", [])) != 1: continue
        mapped = Counter(t for t in r["tokens"] if t is not None)
        diff = Counter(mons) - mapped
        if sum(diff.values()) == 1 and not (mapped - Counter(mons)):
            cand[r["unmapped"][0]][next(iter(diff))] += 1
    d = dict(BASE); conflicts = {}
    for frag, c in cand.items():
        tok, n = c.most_common(1)[0]
        if len(c) > 1: conflicts[frag] = dict(c)
        if n >= 2 and tok not in d.values(): d[frag] = tok
    return d, conflicts


def learn_ncaa_dictionary_iter(rows, rounds=4, min_count=2):
    """Iterative variant: after each round learned tokens turn 2-unmapped peptides into 1-unmapped ones, so more fragments can be named.
    rows: iterable of (smiles, monomer_list) with ground-truth monomer lists (CycPeptMPDB). Returns (dictionary, per-round dictionary sizes)."""
    from collections import Counter, defaultdict
    rows = list(rows); d = dict(BASE); sizes = [len(d)]
    for _ in range(rounds):
        cand = defaultdict(Counter)
        for smi, mons in rows:
            r = segment(smi, d)
            if not r.get("ok") or len(r.get("unmapped", [])) != 1: continue
            mapped = Counter(t for t in r["tokens"] if t is not None)
            diff = Counter(mons) - mapped
            if sum(diff.values()) == 1 and not (mapped - Counter(mons)):
                cand[r["unmapped"][0]][next(iter(diff))] += 1
        new = 0
        for frag, c in cand.items():
            tok, n = c.most_common(1)[0]
            if n >= min_count and frag not in d and tok not in d.values(): d[frag] = tok; new += 1
        sizes.append(len(d))
        if not new: break
    return d, sizes


def segment(smi, dictionary=None):
    """Exception-safe wrapper: any RDKit failure (seen on branched/isopeptide topologies) -> ok=False, why='exception' (counted as unscored, never silently dropped)."""
    try: return _segment(smi, dictionary)
    except Exception as e: return dict(ok=False, why="exception:" + type(e).__name__)
