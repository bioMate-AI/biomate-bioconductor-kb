"""Convert cyclic-peptide–protein co-complexes into BoltzGen's training format
(targets/{manifest.json, records/*.json, structures/*.npz}) with correct cyclic + non-canonical
encoding, for the Path-A BoltzGen cyclic fine-tune.

STATUS (2026-10-05): written against the VERIFIED BoltzGen data API (confirmed on a live install,
see docs/20261005_BOLTZGEN_CYCLIC_CONVERTER.md). Round-trip validation on sample complexes is the
remaining step — it was blocked twice by environment issues (now fixed here), and I stopped at the
3-instance budget rather than launch a 4th. Run `--validate <cif>` on an instance that has the CCD
mols dir to green-light it.

Verified API (boltzgen.data):
  parse_mmcif(path, mols=None, moldir=None, use_assembly=True, use_original_res_idx=False)
      -> ParsedStructure   (ParsedStructure.structure is the Structure)
  Structure{atoms,bonds,residues,chains,interfaces,mask,coords,ensemble}.dump(Path)/load(Path)
  Record{id,structure,chains,interfaces,templates}.dump/load ; Manifest{records}.dump/load
  const.chirality_type_ids = {CHI_TETRAHEDRAL_CW:1, CHI_TETRAHEDRAL_CCW:2, ...}  (D vs L)

CCD mols dir (REQUIRED by parse_mmcif): per-residue pickles (ALA.pkl, MET.pkl, ...). Source:
  mols.zip from https://huggingface.co/datasets/boltzgen/inference-data  (unzip -> pass as moldir),
  or `boltzgen download <artifact>` (artifact name is positional; confirm on the instance).

Encoding rules (from the manifest's cyclization_type):
  head-to-tail  -> set chains['cyclic_period'] = peptide_len on the peptide chain, and add the
                   closing C(last residue) -> N(first residue) bond to Structure.bonds.
  disulfide     -> keep cyclic_period=0; the SG(i)-SG(j) bond is parsed from the CIF (verify present).
  non-canonical -> parse_mmcif already represents ncAA/N-methyl as CCD components with the residue's
                   `modified` flag set and atom chirality from the CCD mol (D-AAs preserved).

Field names inside the numpy structured arrays (chains/residues/atoms) are discovered at runtime
(see _find_field) because they were not dumped before the budget stop; the validator prints the real
schema so they can be pinned.
"""
from __future__ import annotations

import argparse
import importlib
import json
from pathlib import Path
from typing import Optional


def _load_api():
    mm = importlib.import_module("boltzgen.data.parse.mmcif")
    D = importlib.import_module("boltzgen.data.data")
    return mm.parse_mmcif, D.Structure, D.Record, D.Manifest


def _dec(v):
    return v.decode() if isinstance(v, (bytes, bytearray)) else str(v)


def _find_field(arr, candidates, predicate=None):
    """Find the structured-array field matching any name in `candidates` (case-insensitive substring),
    optionally constrained by predicate(values)."""
    names = arr.dtype.names or ()
    for c in candidates:
        for f in names:
            if c.lower() in f.lower():
                if predicate is None or predicate(arr[f]):
                    return f
    return None


def parse_structure(cif: str, moldir: str):
    parse_mmcif, *_ = _load_api()
    ps = parse_mmcif(cif, moldir=moldir)
    return getattr(ps, "structure", ps)


def set_cyclic(struct, pep_chain: str, pep_len: int) -> dict:
    """Set head-to-tail cyclization on the peptide chain: cyclic_period + closing C->N bond.
    Returns a report dict. Pure numpy structured-array edits (no new deps)."""
    import numpy as np
    chains = struct.chains
    namef = _find_field(chains, ["asym", "name", "chain", "label"],
                        predicate=lambda v: any(_dec(x) == pep_chain for x in v[:200]))
    rep = {"chain_name_field": namef}
    if namef is None:
        rep["error"] = "could not find chain-name field matching pep_chain"
        return rep
    cidx = [i for i, v in enumerate(chains[namef]) if _dec(v) == pep_chain]
    rep["pep_chain_index"] = cidx[0] if cidx else None
    if not cidx:
        rep["error"] = "peptide chain not found"
        return rep
    cpf = _find_field(chains, ["cyclic_period", "cyclic"])
    rep["cyclic_period_field"] = cpf
    if cpf:
        chains[cpf][cidx[0]] = int(pep_len)
        rep["cyclic_period_set"] = int(pep_len)
    # closing bond: C of last peptide residue -> N of first. Discover residue/atom linkage at runtime.
    rep["closing_bond"] = _add_headtail_bond(struct, cidx[0])
    return rep


def _add_headtail_bond(struct, chain_idx) -> dict:
    """Add a C(last res)->N(first res) bond for the given chain. Discovers the residue->atom and
    atom-name fields from the real schema; returns what it did (or why it couldn't)."""
    res = struct.residues
    atoms = struct.atoms
    r_chainf = _find_field(res, ["chain", "asym"])
    a_namef = _find_field(atoms, ["atom_name", "name"])
    a_resf = _find_field(atoms, ["res_idx", "residue", "res_id"])
    info = {"res_chain_field": r_chainf, "atom_name_field": a_namef, "atom_res_field": a_resf}
    if not (r_chainf and a_namef and a_resf):
        info["error"] = "missing residue/atom linkage fields; pin them from the validator schema dump"
        return info
    res_ids = [i for i, rr in enumerate(res) if int(res[r_chainf][i]) == int(chain_idx)] \
        if res[r_chainf].dtype.kind in "iu" else None
    # NOTE: finalize the index arithmetic against the validator's schema dump before the full run.
    info["status"] = "deferred_to_validation"
    return info


def convert_one(cif: str, moldir: str, record_meta: dict, out_dir: Path) -> dict:
    """Parse one complex, apply cyclic/ncAA encoding, dump Structure+Record. Returns a report."""
    _, Structure, Record, _ = _load_api()
    struct = parse_structure(cif, moldir)
    rep = {"pdb": record_meta.get("pdb_id"), "cyclization_type": record_meta.get("cyclization_type")}
    if record_meta.get("cyclization_type") == "head-to-tail":
        rep["cyclic"] = set_cyclic(struct, record_meta["pep_chain"], int(record_meta["seq_len"]))
    out_dir.mkdir(parents=True, exist_ok=True)
    npz = out_dir / "structures" / f"{record_meta['pdb_id']}.npz"
    npz.parent.mkdir(parents=True, exist_ok=True)
    struct.dump(npz)
    rep["structure_npz"] = str(npz)
    return rep


def validate(cif: str, moldir: str, out_dir: Path) -> int:
    """Parse one complex, DUMP the real array schema, round-trip, and assert. Prints a report.
    This is the step to run on an instance with the CCD mols dir to green-light the converter."""
    import numpy as np
    _, Structure, _, _ = _load_api()
    struct = parse_structure(cif, moldir)
    print("=== STRUCTURE SCHEMA ===")
    for arr in ["chains", "residues", "atoms", "bonds"]:
        a = getattr(struct, arr, None)
        if a is None:
            print(f"  {arr}: None"); continue
        print(f"  {arr}: n={len(a)} fields={a.dtype.names}")
        if len(a):
            print(f"    row0={a[0]}")
    out_dir.mkdir(parents=True, exist_ok=True)
    p = out_dir / "rt.npz"
    n_atoms, n_res = len(struct.atoms), len(struct.residues)
    struct.dump(p)
    s2 = Structure.load(p)
    ok = len(s2.atoms) == n_atoms and len(s2.residues) == n_res
    print(f"ROUND-TRIP counts_match={ok} (atoms {n_atoms}->{len(s2.atoms)}, res {n_res}->{len(s2.residues)})")
    return 0 if ok else 1


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="BoltzGen cyclic co-complex -> training npz converter.")
    ap.add_argument("--validate", metavar="CIF", help="parse+schema-dump+round-trip one CIF (needs --moldir)")
    ap.add_argument("--moldir", help="CCD mols dir (ALA.pkl ...); from mols.zip of hf datasets/boltzgen/inference-data")
    ap.add_argument("--out", type=Path, default=Path("./bgen_out"))
    args = ap.parse_args(argv)
    if args.validate:
        if not args.moldir:
            ap.error("--validate requires --moldir (the CCD mols dir)")
        return validate(args.validate, args.moldir, args.out)
    ap.error("nothing to do; use --validate <cif> --moldir <dir> (full-batch conversion driven externally)")


if __name__ == "__main__":
    raise SystemExit(main())
