"""Convert cyclic-peptide–protein co-complexes into BoltzGen's training format
(targets/{manifest.json, records/*.json, structures/*.npz}) with correct cyclic + non-canonical
encoding, for the Path-A BoltzGen cyclic fine-tune.

STATUS (2026-10-05): written against the VERIFIED BoltzGen data API + VERIFIED structured-array schema
(confirmed on a live install; CCD mols resolved; Structure.dump/load round-trips on 5/5 sample cyclic
complexes incl. ncAA — see docs/20261005_BOLTZGEN_CYCLIC_CONVERTER.md). The cyclic_period / closing-bond /
ncAA encoding below uses the verified field names. The round-trip of an *appended* bond + the encoding
on the peptide chain identified by res_num is the one assertion still to be exercised on an instance
(the earlier run's chain match was vacuous because BoltzGen renames chains to 'A1'…).

VERIFIED API:
  boltzgen.data.parse.mmcif.parse_mmcif(path, mols=None, moldir=None, use_assembly=True,
      use_original_res_idx=False) -> ParsedStructure        # the Structure is ParsedStructure.data
  boltzgen.data.data.Structure{atoms,bonds,residues,chains,interfaces,mask,coords,ensemble}
      .dump(Path)/.load(Path)
  Record{id,structure,chains,interfaces,templates}; Manifest{records}

VERIFIED Structure schema (numpy structured arrays):
  chains  : name, mol_type, entity_id, sym_id, asym_id, atom_idx, atom_num, res_idx, res_num, cyclic_period
  residues: name, res_type, res_idx, atom_idx, atom_num, atom_center, atom_disto, is_standard, is_present
  atoms   : name, coords, is_present, bfactor, plddt          # addressed per-residue via residue.atom_idx/atom_num
  bonds   : chain_1, chain_2, res_1, res_2, atom_1, atom_2, type

Encoding (from bound_cyclic_v1 manifest: pep_chain, peptide_seq with X=ncAA, seq_len, cyclization_type):
  head-to-tail  -> chains['cyclic_period'][pep] = seq_len  AND append bond
                   (chain_1=chain_2=pep, res_1=last res, res_2=first res, atom_1=C(last), atom_2=N(first), type=1)
  disulfide/sidechain -> cyclic_period=0; the cyclizing bond is parsed from the CIF (already in bonds)
  non-canonical (ncAA/N-methyl/D-AA) -> represented as CCD residues: residues['is_standard']==False;
                   chirality (D vs L) is carried by the residue CCD name (e.g. DAL), which round-trips.

CCD mols dir REQUIRED by parse_mmcif: mols.zip from hf datasets/boltzgen/inference-data (45k pkls).
"""
from __future__ import annotations

import argparse
import importlib
import json
from pathlib import Path
from typing import Optional

# ---- verified field names (pinned from the live schema dump) --------------------------------------
F_CHAIN_NAME = "name"
F_CHAIN_CYCLIC = "cyclic_period"
F_CHAIN_RESIDX = "res_idx"
F_CHAIN_RESNUM = "res_num"
F_RES_NAME = "name"
F_RES_ATOMIDX = "atom_idx"
F_RES_ATOMNUM = "atom_num"
F_RES_ISSTD = "is_standard"
F_ATOM_NAME = "name"
BOND_FIELDS = ("chain_1", "chain_2", "res_1", "res_2", "atom_1", "atom_2", "type")
BOND_COVALENT_TYPE = 1  # intra-structure covalent bond type seen in parsed bonds (row0 type=1)


def _load_api():
    mm = importlib.import_module("boltzgen.data.parse.mmcif")
    D = importlib.import_module("boltzgen.data.data")
    return mm.parse_mmcif, D.Structure, D.Record, D.Manifest


def _dec(v):
    return v.decode() if isinstance(v, (bytes, bytearray)) else str(v)


def parse_structure(cif: str, moldir: str):
    parse_mmcif, *_ = _load_api()
    ps = parse_mmcif(cif, moldir=moldir)
    st = getattr(ps, "data", None)          # verified: Structure is ParsedStructure.data
    if st is None or not hasattr(st, "chains"):
        for a in dir(ps):                   # defensive fallback
            v = getattr(ps, a, None)
            if hasattr(v, "chains") and hasattr(v, "dump"):
                st = v; break
    if st is None:
        raise RuntimeError(f"no Structure in ParsedStructure (type={type(ps)})")
    return st


def peptide_chain_index(struct, seq_len: int) -> Optional[int]:
    """Identify the peptide chain. BoltzGen renames chains ('A1'…), so match by residue count
    (== manifest seq_len); fall back to the shortest chain."""
    chains = struct.chains
    exact = [i for i in range(len(chains)) if int(chains[F_CHAIN_RESNUM][i]) == int(seq_len)]
    if exact:
        return exact[0]
    if len(chains):
        return int(min(range(len(chains)), key=lambda i: int(chains[F_CHAIN_RESNUM][i])))
    return None


def _atom_global_index(struct, res_global_idx: int, atom_name: str) -> Optional[int]:
    """Global atom index of `atom_name` within residue `res_global_idx` (atoms are addressed by the
    residue's atom_idx..atom_idx+atom_num range)."""
    res = struct.residues
    a0 = int(res[F_RES_ATOMIDX][res_global_idx]); n = int(res[F_RES_ATOMNUM][res_global_idx])
    names = struct.atoms[F_ATOM_NAME]
    for ai in range(a0, a0 + n):
        if _dec(names[ai]).strip() == atom_name:
            return ai
    return None


def set_headtail_cyclic(struct, pep_idx: int, seq_len: int) -> dict:
    """Set cyclic_period + append the closing C(last)->N(first) bond on the peptide chain."""
    import numpy as np
    chains = struct.chains
    chains[F_CHAIN_CYCLIC][pep_idx] = int(seq_len)
    r0 = int(chains[F_CHAIN_RESIDX][pep_idx]); rn = int(chains[F_CHAIN_RESNUM][pep_idx])
    first_res, last_res = r0, r0 + rn - 1
    c_atom = _atom_global_index(struct, last_res, "C")
    n_atom = _atom_global_index(struct, first_res, "N")
    rep = {"pep_idx": pep_idx, "cyclic_period": int(seq_len), "first_res": first_res,
           "last_res": last_res, "C_atom": c_atom, "N_atom": n_atom}
    if c_atom is None or n_atom is None:
        rep["bond"] = "skipped: missing backbone C/N"
        return rep
    bonds = struct.bonds
    row = np.zeros(1, dtype=bonds.dtype)
    row["chain_1"] = pep_idx; row["chain_2"] = pep_idx
    row["res_1"] = last_res; row["res_2"] = first_res
    row["atom_1"] = c_atom; row["atom_2"] = n_atom
    row["type"] = BOND_COVALENT_TYPE
    # Structure is a FROZEN dataclass -> reassigning .bonds raises FrozenInstanceError. Use
    # object.__setattr__ (the chains['cyclic_period'][pep]=seq_len edit above is an in-place array
    # mutation, which a frozen dataclass allows; appending a bond needs a new array).
    object.__setattr__(struct, "bonds", np.concatenate([bonds, row]))
    rep["bond"] = "added"
    return rep


def n_noncanonical(struct, pep_idx: int) -> int:
    """Count non-standard (ncAA/N-methyl/D-AA) residues in the peptide chain (is_standard==False)."""
    chains = struct.chains
    r0 = int(chains[F_CHAIN_RESIDX][pep_idx]); rn = int(chains[F_CHAIN_RESNUM][pep_idx])
    isstd = struct.residues[F_RES_ISSTD]
    return int(sum(1 for i in range(r0, r0 + rn) if not bool(isstd[i])))


def validate(cif: str, moldir: str, out_dir: Path, seq_len: int, cyclization: str = "head-to-tail") -> int:
    """Parse -> encode (cyclic_period + bond for head-to-tail) -> round-trip assert. Returns 0 on PASS."""
    import numpy as np
    _, Structure, _, _ = _load_api()
    out_dir.mkdir(parents=True, exist_ok=True)
    st = parse_structure(cif, moldir)
    na0, nr0, nb0 = len(st.atoms), len(st.residues), len(st.bonds)
    pep = peptide_chain_index(st, seq_len)
    res_names_before = [_dec(x) for x in st.residues[F_RES_NAME]]
    n_nc = n_noncanonical(st, pep) if pep is not None else None
    added = False
    if pep is not None and cyclization in ("head-to-tail", "head_to_tail"):
        rep = set_headtail_cyclic(st, pep, seq_len); added = rep.get("bond") == "added"
        print("ENCODE:", json.dumps(rep))
    p = out_dir / "rt.npz"; st.dump(p); s2 = Structure.load(p)
    counts_ok = len(s2.atoms) == na0 and len(s2.residues) == nr0
    cyc_ok = int(s2.chains[F_CHAIN_CYCLIC][pep]) == int(seq_len) if pep is not None and cyclization.replace("_", "-") == "head-to-tail" else None
    bond_ok = len(s2.bonds) == nb0 + 1 if added else None
    names_ok = [_dec(x) for x in s2.residues[F_RES_NAME]] == res_names_before  # chirality via CCD name
    ok = counts_ok and (cyc_ok in (True, None)) and (bond_ok in (True, None)) and names_ok
    print(f"RESULT pep_idx={pep} n_noncanonical={n_nc} counts_match={counts_ok} cyclic_persist={cyc_ok} "
          f"bond_persist={bond_ok} residue_names_preserved={names_ok} -> {'PASS' if ok else 'FAIL'}")
    return 0 if ok else 1


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="BoltzGen cyclic co-complex -> training npz converter.")
    ap.add_argument("--validate", metavar="CIF")
    ap.add_argument("--moldir", help="CCD mols dir (mols.zip from hf datasets/boltzgen/inference-data)")
    ap.add_argument("--seq-len", type=int, help="peptide length (identifies the peptide chain)")
    ap.add_argument("--cyclization", default="head-to-tail")
    ap.add_argument("--out", type=Path, default=Path("./bgen_out"))
    args = ap.parse_args(argv)
    if args.validate:
        if not (args.moldir and args.seq_len):
            ap.error("--validate requires --moldir and --seq-len")
        return validate(args.validate, args.moldir, args.out, args.seq_len, args.cyclization)
    ap.error("use --validate <cif> --moldir <dir> --seq-len N")


if __name__ == "__main__":
    raise SystemExit(main())
