"""interface_featurizer.py — the reusable CORE of the structure-grounded design (P1/P2).

Extracts a TARGET-AGNOSTIC physical interaction representation from a bound peptide-receptor complex:
the binding-interface terms that are shared across all targets (contacts, H-bonds, salt bridges, buried
hydrophobic/polar surface, metal coordination). This is the representation the cross-target claim rests on —
a novel target's cofolded interface is described by the SAME physics, so a model over these features can
transfer. Works on experimental complexes (PDB fetch by id) now; the identical extractor runs on cofolded
(Boltz-2/AF3) complexes later. gemmi only; no GPU.

featurize(cif_path | pdb_id, pep_chain, rec_chains) -> dict of interface descriptors.
"""
import os, io, json, math, urllib.request
import numpy as np
import gemmi

HB = {"N", "O"}                      # H-bond heavy atoms (coarse)
METALS = {"MG", "MN", "ZN", "CA", "FE", "CU", "NI"}
HYDRO = set("AILMFWVP")              # hydrophobic residue 1-letter
CHG_POS = set("KR"); CHG_NEG = set("DE")
_3to1 = {"ALA":"A","ARG":"R","ASN":"N","ASP":"D","CYS":"C","GLN":"Q","GLU":"E","GLY":"G","HIS":"H",
         "ILE":"I","LEU":"L","LYS":"K","MET":"M","PHE":"F","PRO":"P","SER":"S","THR":"T","TRP":"W",
         "TYR":"Y","VAL":"V"}


def _fetch(pdb_id, cache="/tmp/bc_cifs"):
    os.makedirs(cache, exist_ok=True)
    p = os.path.join(cache, f"{pdb_id.lower()}.cif")
    if not os.path.exists(p):
        data = urllib.request.urlopen(f"https://files.rcsb.org/download/{pdb_id.lower()}.cif", timeout=30).read()
        open(p, "wb").write(data)
    return p


def featurize(pdb_id, pep_chain, rec_chains, cutoff=4.5):
    """Interface interaction descriptors between pep_chain and rec_chains."""
    rec = set(rec_chains)
    st = gemmi.read_structure(_fetch(pdb_id)); m = st[0]
    ns = gemmi.NeighborSearch(m, st.cell, cutoff + 1.0).populate()
    pep = [(ch, r) for ch in m if ch.name == pep_chain for r in ch]
    if not pep:
        return None
    n_iface = 0; contacts = 0; hbonds = 0; salt = 0; hydro_c = 0; metal_c = 0
    iface_res1 = []
    for ch, r in pep:
        rn = _3to1.get(r.name, "X"); on_iface = False
        r_pos = any(_3to1.get(r.name) in CHG_POS for _ in [0]); r_neg = _3to1.get(r.name) in CHG_NEG
        for a in r:
            for mk in ns.find_atoms(a.pos, '\0', radius=cutoff):
                cra = mk.to_cra(m)
                if cra.chain.name not in rec:
                    continue
                d = a.pos.dist(cra.atom.pos)
                if d > cutoff:
                    continue
                on_iface = True; contacts += 1
                ael, bel = a.element.name.upper(), cra.atom.element.name.upper()
                if a.element.name in HB and cra.atom.element.name in HB and d < 3.5:
                    hbonds += 1
                if bel in METALS or ael in METALS:
                    metal_c += 1
                # salt bridge: charged pep residue near charged/opposite
                rrn = _3to1.get(cra.residue.name, "X")
                if (rn in CHG_POS and rrn in CHG_NEG) or (rn in CHG_NEG and rrn in CHG_POS):
                    if d < 4.0: salt += 1
                if rn in HYDRO and rrn in HYDRO:
                    hydro_c += 1
        if on_iface:
            n_iface += 1; iface_res1.append(rn)
    L = len(pep)
    return {"pdb_id": pdb_id, "pep_len": L, "n_interface_res": n_iface,
            "iface_frac": round(n_iface / max(L, 1), 3),
            "contacts": contacts, "contacts_per_res": round(contacts / max(L, 1), 2),
            "hbonds": hbonds, "salt_bridges": salt, "hydrophobic_contacts": hydro_c, "metal_contacts": metal_c,
            "iface_hydrophobic_frac": round(sum(1 for c in iface_res1 if c in HYDRO) / max(n_iface, 1), 3),
            "iface_charged_frac": round(sum(1 for c in iface_res1 if c in (CHG_POS | CHG_NEG)) / max(n_iface, 1), 3),
            "iface_aromatic_frac": round(sum(1 for c in iface_res1 if c in set("FYWH")) / max(n_iface, 1), 3)}


def feature_vector(d):
    """Fixed-order numeric vector (target-agnostic interface physics) for ML."""
    keys = ["pep_len", "n_interface_res", "iface_frac", "contacts_per_res", "hbonds", "salt_bridges",
            "hydrophobic_contacts", "metal_contacts", "iface_hydrophobic_frac", "iface_charged_frac",
            "iface_aromatic_frac"]
    return np.array([d[k] for k in keys], float), keys


if __name__ == "__main__":
    ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    mani = [json.loads(l) for l in open(os.path.join(ROOT, "data/bound_cyclic/v2/bound_cyclic_manifest.jsonl"))]
    import sys
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 6
    print(f"validating interface featurizer on {n} experimental complexes:\n")
    ok = 0
    for row in mani[:n]:
        try:
            d = featurize(row["pdb_id"], row["pep_chain"], row["rec_chains"])
            if d:
                ok += 1
                print(f"  {d['pdb_id']}: iface_res={d['n_interface_res']} (manifest {row['n_interface_residues']}) "
                      f"contacts={d['contacts']} HB={d['hbonds']} salt={d['salt_bridges']} "
                      f"metal={d['metal_contacts']} hydroφ_frac={d['iface_hydrophobic_frac']}")
        except Exception as e:
            print(f"  {row['pdb_id']}: ERR {type(e).__name__}: {str(e)[:70]}")
    print(f"\n{ok}/{n} featurized. Target-agnostic interface vector dim = {len(feature_vector(d)[1])}")
