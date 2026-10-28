"""KN-2 simulated-assay scorer (PREREG_KN2.md): mechanism ENGAGEMENT of a co-folded cyclic peptide with the metal-complete aVb6 headpiece.
E = 1 iff ligand-ipTM >= 0.80 AND min distance (either carboxylate O of the RGD Asp -> MIDAS Mn) <= 2.6 A. 
MIDAS Mn is identified by RULE (not by ion order): the Mn nearest to a beta6 (chain B) serine OG, i.e. the ion coordinated by the beta6 MIDAS serine; in the validated control complexes this is the only Mn with beta6 coordination.
Peptide chain = chain 'P' if present else the last chain. Peptides without an Arg-Gly-Asp triplet have asp_found = False and E = 0 by definition."""
import gemmi

IPTM_MIN, DIST_MAX = 0.80, 2.6


def _peptide_chain(model):
    for c in model:
        if c.name == "P": return c
    return model[len(model) - 1]


def _rgd_asp(chain):
    for i in range(2, len(chain)):
        if chain[i].name == "ASP" and chain[i - 1].name == "GLY" and chain[i - 2].name == "ARG": return chain[i]
    return None


def _midas_mn(model):
    mns = [(c.name, r[0].pos) for c in model for r in c if r.name == "MN"]
    sers = [a.pos for c in model if c.name == "B" for r in c if r.name == "SER" for a in r if a.name == "OG"]
    if not mns or not sers: return None
    return min(mns, key=lambda m: min(m[1].dist(s) for s in sers))


def engagement(cif_path, ligand_iptm):
    st = gemmi.read_structure(cif_path); m = st[0]; out = dict(asp_found=False, engaged=False, d_asp_midas_mn=None, midas_mn_chain=None, ligand_iptm=float(ligand_iptm))
    asp = _rgd_asp(_peptide_chain(m)); mid = _midas_mn(m)
    if mid: out["midas_mn_chain"] = mid[0]
    if asp is None or mid is None: return out
    out["asp_found"] = True; ds = [asp[a][0].pos.dist(mid[1]) for a in ("OD1", "OD2") if asp.find_atom(a, "*")]
    if not ds: return out
    out["d_asp_midas_mn"] = round(min(ds), 3); out["engaged"] = bool(ligand_iptm >= IPTM_MIN and min(ds) <= DIST_MAX); return out
