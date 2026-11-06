"""NOTE (measured vs CycPeptMPDB Molecule_Shape, n=8,466): macro-ring count (linear / one ring / multi) is reliable; the head-to-tail vs lariat split is NOT: lariat recall 0.983, head-to-tail (Circle) recall 0.642. v5 therefore takes the shape token from ground truth where it exists and uses this heuristic only elsewhere, flagged.
C6 atom-level route for v5: chirality-preserving SMILES tokens (reuses allatom/atom_lm.py tokenizer + vocabulary) + topology tokens.
Topology (RDKit, deterministic): count SSSR rings of size >= 8 ('macro rings').
  <topo_linear>   0 macro rings
  <topo_h2t>      exactly 1 macro ring and the segmenter reports a cyclic peptide backbone
  <topo_lariat>   exactly 1 macro ring and a non-cyclic backbone (side-chain/tail closure, isopeptide, disulfide, thioether, staple)
  <topo_multi>    >= 2 macro rings (bicyclic / multiply cross-linked)
  suffix flags on the same token slot: +ds (S-S bond), +stap (macro ring bridge with a C=C or >= 6 consecutive sp3 carbons and no amide in the bridge: hydrocarbon staple)
Sequence layout: <bos> <topo_*> [flags] <smiles tokens> <eos>.  Coverage/validity are reported by audit_atom_route.py."""
import os, sys, re
from rdkit import Chem, RDLogger
RDLogger.DisableLog("rdApp.*")
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "allatom"))
import smiles_to_monomers as S

TOPO_TOKENS = ["<topo_linear>", "<topo_h2t>", "<topo_lariat>", "<topo_multi>", "<flag_ds>", "<flag_stap>", "<topo_unk>"]
DS = Chem.MolFromSmarts("[SX2]-[SX2]")


def macro_rings(m, min_size=8):
    return [r for r in m.GetRingInfo().AtomRings() if len(r) >= min_size]


def _is_staple(m, ring):
    """hydrocarbon staple: >= 6 CONSECUTIVE ring atoms that are carbons with no N neighbour and no C=O (i.e. not backbone / not amide-linked side chains)."""
    def hc(a):
        at = m.GetAtomWithIdx(a)
        if at.GetSymbol() != "C": return False
        for nb in at.GetNeighbors():
            if nb.GetSymbol() == "N": return False
            if nb.GetSymbol() == "O" and m.GetBondBetweenAtoms(a, nb.GetIdx()).GetBondType() == Chem.BondType.DOUBLE: return False
        return True
    flags = [hc(a) for a in ring]; n = len(flags); best = run = 0
    for k in range(2 * n):
        if flags[k % n]: run += 1; best = max(best, min(run, n))
        else: run = 0
    return best >= 6


def _backbone_atoms(m):
    s = set()
    for N, CA, C, O in m.GetSubstructMatches(S.BACKBONE): s.update((N, CA, C))
    return s


def topology(smiles, dictionary=None):
    """Head-to-tail is decided from the graph alone (does not need a complete residue mapping): the single macro ring is >= 75 % peptide-backbone atoms (N, CA, C)."""
    m = Chem.MolFromSmiles(smiles) if isinstance(smiles, str) else None
    if m is None: return ["<topo_unk>"]
    frags = Chem.GetMolFrags(m, asMols=True)
    if len(frags) > 1: m = max(frags, key=lambda x: x.GetNumAtoms())
    mr = macro_rings(m)
    bb = _backbone_atoms(m)
    if len(mr) == 0: t = "<topo_linear>"
    elif len(mr) == 1:
        seg = S.segment(smiles, dictionary)
        if seg.get("ok"): t = "<topo_h2t>" if seg["cyclic"] else "<topo_lariat>"          # segmenter finds a start unit -> lariat
        else: t = "<topo_h2t>" if sum(a in bb for a in mr[0]) >= 0.75 * len(mr[0]) else "<topo_lariat>"
    else: t = "<topo_multi>"
    out = [t]
    if m.HasSubstructMatch(DS): out.append("<flag_ds>")
    if mr and any(_is_staple(m, r) for r in mr): out.append("<flag_stap>")
    return out


def encode(smiles, vocab, max_len=256, with_topology=True):
    """-> (ids, status). ids = [BOS] + topology + smiles tokens + [EOS]. status in {ok, tokenizer_fail, too_long}; UNK count reported by caller."""
    import atom_lm as A
    try: toks = A.tokenize(smiles)
    except AssertionError: return None, "tokenizer_fail"
    pre = topology(smiles) if with_topology else []
    ids = [A.BOS] + [vocab.stoi.get(t, A.UNK) for t in pre + toks] + [A.EOS]
    if len(ids) > max_len: return ids, "too_long"
    return ids, "ok"
