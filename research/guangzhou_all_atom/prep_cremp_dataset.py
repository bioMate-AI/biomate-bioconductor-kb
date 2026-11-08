#!/usr/bin/env python3
"""prep_cremp_dataset.py — build a PepGLAD peptide-only mmap dataset from CREMP macrocycle
conformers for the M1 geometry-AE mid-train (Option B).

WHAT THIS IS (docs/20260927_PEPTIDE_PARALLEL_WORK_PLAN.md M1; ..._CYCLIC_CORPUS_AND_TRAINING_STRATEGY.md
Part B AE=B). CPU-only data-engineering (NO GPU, NO training). It turns CREMP
(summary.csv + sdf_and_json.tar.bz2, s3://.../cyclic_peptide/datasets/cremp_partial) into the exact
on-disk mmap format the vendored PepGLAD AutoEncoderTrainer + CoDesignDataset consume — one
peptide-only record per (molecule, conformer), with a PER-MOLECULE train/val/test split that reuses
the M0 sequence-hash bucketing so the M1 eval hold-out is identical to M0's.

WHY A NEW PROCESSOR (what we reuse vs. what we had to add)
  REUSE (do NOT reinvent, per CLAUDE.md):
    * cycpeptmpdb_to_pepglad.py `_trace_backbone` / `_identify_residue` — the vetted backbone-walk +
      VF2 sidechain-identify that handles head-to-tail macrolactams + canonical sidechains. This is
      exactly what m0_frozen_probe.py's `_blocks_from_rdkit_conformer` uses on CREMP, so the M1
      training featurization matches the M0 probe featurization byte-for-byte.
    * data.mmap_dataset.compress() serialization + index.txt layout (we mirror it — same gzip-JSON
      blob container the official scripts/data_process/process.py writes via create_mmap()).
    * The peptide-only record shape `([], lig_block_tuples)` and the 11 property columns are copied
      from cycpeptmpdb_to_pepglad.build_dataset() (which already writes peptide-only PepGLAD records).
  HAD TO ADD (and why):
    * CREMP reads from an SDF tarball (per-molecule SDF, many conformers), not per-complex PDBs, so
      process.py (which is PDB->pocket-complex only) does not apply. We write the mmap directly with
      the same compress()/index.txt contract.
    * MULTI-CONFORMER emission with a PER-MOLECULE split (all conformers of a molecule on ONE side) —
      process.py has no notion of molecules-vs-conformers; CREMP's correlation bias (31M conformers !=
      31M molecules) demands molecule-level splitting + capped conformers/molecule.

PEPTIDE-ONLY SUPPORT — VERIFIED, WITH ONE DATASET BUG THAT M1 FIXES (see m1_peptide_dataset.py)
  The AutoEncoder itself supports peptide-only: with no receptor every residue has mask=1, so
  encode()/decode() reconstruct the whole peptide (prepare_inputs makes all edges ctx edges). BUT the
  stock CoDesignDataset.__getitem__ does `pocket_idx = [int(i) for i in props[-1].split(',')]`; for a
  peptide-only record props[-1] is the empty string, and `int('')` raises ValueError. That is a REAL
  bug for peptide-only entries (it also affects cycpeptmpdb_to_pepglad.build_dataset output). M1 fixes
  it at the root with a tiny registered subclass `PeptideOnlyCoDesignDataset` (m1_peptide_dataset.py)
  whose __getitem__ treats an empty pocket string as "no receptor" — it does NOT hack the caller.
  This processor therefore writes an empty pocket column (pocket_idx=""), and the M1 config points at
  PeptideOnlyCoDesignDataset, not CoDesignDataset.

OUTPUT (mirrors data/mmap_dataset.create_mmap layout, one dir per split):
  <out>/{train,valid,test}/data.bin        gzip-JSON blobs: each = ([], [block_tuple, ...])
  <out>/{train,valid,test}/index.txt       "<id>\t<start>\t<end>\t<11 tab-sep props>"
  <out>/manifest.json                       counts, per-split, fail reasons, atom-slot histogram
  <out>/records.jsonl                       one audit line per written conformer

PROPERTY COLUMNS (tab-separated; the order CoDesignDataset reads):
  [n_rec_blocks, n_lig_blocks, rec_units, lig_units, rec_chain, lig_chain,
   rec_seq, lig_seq, non_standard, <unused>, pocket_idx_csv=""]
  CoDesignDataset uses props[1] (n_lig_blocks, for _lengths) and props[-1] (pocket_idx). The rest are
  metadata. We keep column 10 free (like build_dataset uses it for nme_mask) — here it is "".

USAGE
  # CPU smoke (no torch, no S3, no big data) — proves the partition+split+write path on 2 synthetic mols:
  python3 prep_cremp_dataset.py --smoke

  # Real build (on the spot instance; run_m1_ae_midtrain.sh drives this):
  python3 prep_cremp_dataset.py \
      --cremp-dir /data/cremp \
      --out-dir   /data/cremp_pepglad \
      --max-confs-per-mol 8 \
      --max-train-mols 6000 --max-val-mols 400
"""
from __future__ import annotations

import argparse
import csv
import gzip
import hashlib
import io
import json
import sys
import tarfile
import time
from pathlib import Path
from typing import Dict, List, Optional, Tuple

ROOT = Path(__file__).resolve().parent
RUNTIME = ROOT / "runtime" / "PepGLAD"
# Make the vendored PepGLAD package importable (data.format VOCAB, utils.const) and this dir importable
# (cycpeptmpdb_to_pepglad partition reuse) — same sys.path dance as m0_frozen_probe.py.
if str(RUNTIME) not in sys.path:
    sys.path.insert(0, str(RUNTIME))
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))


# =================================================================================================
# Per-molecule split — IDENTICAL to m0_frozen_probe._mol_split so the M1 hold-out == the M0 hold-out.
# =================================================================================================
def mol_split(sequence: str, test_frac: float = 0.1, val_frac: float = 0.1) -> str:
    """Deterministic per-MOLECULE bucket by sequence hash. Copied verbatim from
    m0_frozen_probe._mol_split — the frozen split guarantee (all conformers of a molecule share a
    bucket; M1 trains only on train+val molecules, is evaluated on the SAME test molecules as M0)."""
    h = int(hashlib.sha1(sequence.encode()).hexdigest(), 16) % 1000
    if h < int(test_frac * 1000):
        return "test"
    if h < int((test_frac + val_frac) * 1000):
        return "val"
    return "train"


# =================================================================================================
# CREMP conformer -> PepGLAD Blocks (reuses the M0 / cycpeptmpdb partition machinery verbatim)
# =================================================================================================
def blocks_from_conformer(mol, conf_id: int) -> Optional[List[Dict]]:
    """Partition ONE RDKit conformer into per-residue block dicts {symbol, atoms:[{name,element,coord}]}
    via cycpeptmpdb_to_pepglad._trace_backbone + _identify_residue. This is a straight lift of
    m0_frozen_probe._blocks_from_rdkit_conformer so training-time featurization == probe-time
    featurization. Returns None on any partition failure (counted, never a silent fallback)."""
    import cycpeptmpdb_to_pepglad as cvt
    from rdkit import Chem

    molNoH = Chem.RemoveHs(mol)
    try:
        conf = molNoH.GetConformer(conf_id)
    except (ValueError, RuntimeError):
        return None
    residues = cvt._trace_backbone(molNoH)
    if not residues:
        return None
    all_bb = set()
    for d in residues:
        all_bb.update(d[k] for k in ("N", "CA", "C", "O"))
        if d.get("CN") is not None:
            all_bb.add(d["CN"])
    blocks = []
    for d in residues:
        sym, names = cvt._identify_residue(molNoH, d, all_bb)
        if sym is None:
            return None
        abrv = cvt.SYMBOL_TO_ABRV[sym]
        atoms = []
        for bn in cvt.BACKBONE_NAMES:
            p = conf.GetAtomPosition(d[bn])
            atoms.append({"name": bn, "element": molNoH.GetAtomWithIdx(d[bn]).GetSymbol(),
                          "coord": [p.x, p.y, p.z]})
        for aname in cvt._AA_SIDECHAIN[sym]:
            p = conf.GetAtomPosition(names[aname])
            atoms.append({"name": aname, "element": molNoH.GetAtomWithIdx(names[aname]).GetSymbol(),
                          "coord": [p.x, p.y, p.z]})
        # N-Me CN methyl on the backbone N, if present (CREMP has Sar/N-Me monomers)
        if d.get("CN") is not None:
            p = conf.GetAtomPosition(d["CN"])
            atoms.append({"name": "CN", "element": "C", "coord": [p.x, p.y, p.z]})
        blocks.append({"abrv": abrv, "symbol": sym, "nme": d.get("CN") is not None, "atoms": atoms})
    return blocks


def _block_dict_to_tuple(b: Dict, res_index: int):
    """block dict -> Block.to_tuple() shape (abrv, [(name,[x,y,z],element,pos_code), ...], id).
    pos_code mirrors cycpeptmpdb_to_pepglad._peptide_to_block_tuples (CN->'N', else element-stripped)."""
    atom_tuples = []
    for at in b["atoms"]:
        name, elem = at["name"], at["element"]
        if name == "CN":
            pos_code = "N"
        else:
            pos_code = name[len(elem):] if name.startswith(elem) else name.lstrip(elem)
        atom_tuples.append([name, list(at["coord"]), elem, pos_code])
    blk_id = {"nme": 1 if b.get("nme") else 0, "res_index": res_index}
    return [b["abrv"], atom_tuples, blk_id]


def record_and_props(blocks: List[Dict]) -> Tuple[list, list]:
    """Build the (record, props) pair for ONE conformer, matching cycpeptmpdb_to_pepglad.build_dataset
    exactly. record = ([], lig_block_tuples); props = the 11-column list with an EMPTY pocket column."""
    block_tuples = [_block_dict_to_tuple(b, i) for i, b in enumerate(blocks)]
    record = ([], block_tuples)  # (rec_blocks=[], lig_blocks=peptide)
    lig_seq = "".join(b["symbol"] for b in blocks)
    lig_units = sum(len(b["atoms"]) for b in blocks)
    props = [
        0, len(block_tuples), 0, lig_units, "-", "A",
        "", lig_seq, 0, "", "",  # col 9 unused here; col 10 pocket_idx = "" (peptide-only)
    ]
    return record, props


def _compress(record) -> bytes:
    """gzip-JSON exactly like data.mmap_dataset.compress()."""
    serialized = json.dumps(record).encode()
    buf = io.BytesIO()
    with gzip.GzipFile(fileobj=buf, mode="wb", compresslevel=6) as f:
        f.write(serialized)
    return buf.getvalue()


# =================================================================================================
# Tar iteration: yield (sequence, rdkit_mol_with_confs) for the wanted molecules
# =================================================================================================
def _seq_from_stem(stem: str) -> str:
    """CREMP SDF stem -> sequence. m0 uses stem.replace('_','.'); mirror it (dot-joined monomer seq)."""
    return stem.replace("_", ".") if "." not in stem else stem


def _mols_from_sdf_text(sdf_text: str):
    """Yield every conformer record (one RDKit mol each) from a multi-record CREMP SDF."""
    from rdkit import Chem

    supplier = Chem.SDMolSupplier()
    supplier.SetData(sdf_text, removeHs=True, sanitize=True)
    for mol in supplier:
        if mol is not None and mol.GetNumConformers() > 0:
            yield mol


def _find_tar(cremp_dir: Path) -> Path:
    for n in ("sdf_and_json.tar.bz2", "sdf_and_json.tar.gz", "sdf.tar.bz2"):
        p = cremp_dir / n
        if p.exists():
            return p
    raise FileNotFoundError(f"No CREMP SDF tarball in {cremp_dir}")


# =================================================================================================
# Build
# =================================================================================================
def build(cremp_dir: Path, out_dir: Path, max_confs_per_mol: int,
          max_train_mols: Optional[int], max_val_mols: Optional[int],
          max_test_mols: Optional[int]) -> Dict:
    """Stream the CREMP SDF tarball; for each wanted molecule take up to max_confs_per_mol conformers,
    partition each into PepGLAD blocks, and append to the split its molecule belongs to. Per-molecule
    caps stop conformer-rich compounds from dominating and cap the wall time. test-bucket molecules are
    NOT written to training (they are the held-out eval set the M1 evaluator reads)."""
    from rdkit import RDLogger

    RDLogger.DisableLog("rdApp.*")

    out_dir = Path(out_dir)
    splits = ("train", "valid", "test")
    for s in splits:
        (out_dir / s).mkdir(parents=True, exist_ok=True)
    bins = {s: open(out_dir / s / "data.bin", "wb") for s in splits}
    idxf = {s: open(out_dir / s / "index.txt", "w") for s in splits}
    offsets = {s: 0 for s in splits}
    sidecar = open(out_dir / "records.jsonl", "w")

    # split-name mapping: mol_split() returns train/val/test; PepGLAD dirs are train/valid/test
    dirname = {"train": "train", "val": "valid", "test": "test"}
    mol_caps = {"train": max_train_mols, "val": max_val_mols, "test": max_test_mols}
    mol_count = {"train": 0, "val": 0, "test": 0}

    stats = {
        "molecules_seen": 0, "molecules_written": {s: 0 for s in splits},
        "conformers_written": {s: 0 for s in splits}, "conformers_total": 0,
        "fail_partition": 0, "fail_reasons": {}, "max_block_atoms_hist": {},
        "max_confs_per_mol": max_confs_per_mol,
    }

    def _cap_hit() -> bool:
        return all(mol_caps[b] is not None and mol_count[b] >= mol_caps[b] for b in mol_count)

    tar_path = _find_tar(cremp_dir)
    mode = "r:bz2" if tar_path.name.endswith(".bz2") else "r:gz"
    with tarfile.open(tar_path, mode) as tf:
        for member in tf:
            if _cap_hit():
                break
            if not member.isfile() or not member.name.endswith(".sdf"):
                continue
            stem = Path(member.name).stem
            seq = _seq_from_stem(stem)
            bucket = mol_split(seq)  # train/val/test
            cap = mol_caps[bucket]
            if cap is not None and mol_count[bucket] >= cap:
                continue
            fh = tf.extractfile(member)
            if fh is None:
                continue
            try:
                sdf_text = fh.read().decode("utf-8", "ignore")
            finally:
                fh.close()

            stats["molecules_seen"] += 1
            n_conf_written = 0
            for mol in _mols_from_sdf_text(sdf_text):
                if n_conf_written >= max_confs_per_mol:
                    break
                blocks = blocks_from_conformer(mol, 0)
                if blocks is None:
                    stats["fail_partition"] += 1
                    stats["fail_reasons"]["partition"] = stats["fail_reasons"].get("partition", 0) + 1
                    continue
                record, props = record_and_props(blocks)
                sdir = dirname[bucket]
                blob = _compress(record)
                blen = bins[sdir].write(blob)
                _id = f"cremp_{stem}_c{n_conf_written}"
                idxf[sdir].write(f"{_id}\t{offsets[sdir]}\t{offsets[sdir] + blen}\t" +
                                 "\t".join(str(p) for p in props) + "\n")
                offsets[sdir] += blen
                stats["conformers_written"][sdir] += 1
                stats["conformers_total"] += 1
                mba = max(len(b["atoms"]) for b in blocks)
                stats["max_block_atoms_hist"][mba] = stats["max_block_atoms_hist"].get(mba, 0) + 1
                sidecar.write(json.dumps({
                    "id": _id, "seq": seq, "split": sdir, "n_res": len(blocks),
                    "conf": n_conf_written, "max_block_atoms": mba,
                }) + "\n")
                n_conf_written += 1

            if n_conf_written > 0:
                mol_count[bucket] += 1
                stats["molecules_written"][dirname[bucket]] += 1

    for s in splits:
        bins[s].close()
        idxf[s].close()
    sidecar.close()
    with open(out_dir / "manifest.json", "w") as m:
        json.dump(stats, m, indent=2)
    return stats


# =================================================================================================
# Smoke: torch-free, no S3, exercises split + tuple/record shape + gzip round-trip on synthetic mols
# =================================================================================================
def _smoke() -> int:
    print("== prep_cremp_dataset smoke (no torch, no rdkit, no S3) ==")
    # split determinism must match m0's rule
    for seq in ("N.A.P.A", "P.F.C.S", "G.G.G.G.G"):
        b = mol_split(seq)
        assert b in ("train", "val", "test"), b
        print(f"  mol_split({seq!r}) = {b}")

    # synthetic 4-residue peptide block dicts -> record/props -> gzip round-trip
    def blk(sym, abrv, nme=False):
        atoms = [{"name": "N", "element": "N", "coord": [0.0, 0.0, 0.0]},
                 {"name": "CA", "element": "C", "coord": [1.0, 0.0, 0.0]},
                 {"name": "C", "element": "C", "coord": [1.5, 1.0, 0.0]},
                 {"name": "O", "element": "O", "coord": [1.2, 2.0, 0.0]},
                 {"name": "CB", "element": "C", "coord": [1.5, -1.0, 0.5]}]
        if nme:
            atoms.append({"name": "CN", "element": "C", "coord": [-0.8, 0.4, 0.0]})
        return {"abrv": abrv, "symbol": sym, "nme": nme, "atoms": atoms}

    blocks = [blk("A", "ALA"), blk("A", "ALA", nme=True), blk("A", "ALA"), blk("A", "ALA")]
    record, props = record_and_props(blocks)
    assert record[0] == [], "receptor must be empty (peptide-only)"
    assert len(record[1]) == 4, "4 residue blocks expected"
    assert props[1] == 4, f"n_lig_blocks column must be 4, got {props[1]}"
    assert props[-1] == "", "pocket column must be empty for peptide-only"
    # block tuple shape must match Block.from_tuple: (abrv, [(name,coord,elem,pos), ...], id)
    abrv, atom_tuples, blk_id = record[1][1]  # the N-Me residue
    assert abrv == "ALA" and isinstance(blk_id, dict) and blk_id["nme"] == 1, (abrv, blk_id)
    assert atom_tuples[-1][0] == "CN" and atom_tuples[-1][3] == "N", atom_tuples[-1]
    # gzip round-trip matches data.mmap_dataset.decompress()
    blob = _compress(record)
    got = json.loads(gzip.GzipFile(fileobj=io.BytesIO(blob)).read().decode())
    assert got[0] == [] and len(got[1]) == 4, "round-trip mismatch"
    print(f"  record/props/gzip round-trip ok  (props={props})")
    print("  [ok] smoke passed — split rule, record/props shape, and mmap serialization are sound.")
    return 0


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--smoke", action="store_true", help="torch/rdkit/S3-free wiring self-test")
    ap.add_argument("--cremp-dir", type=Path, help="dir with summary.csv + sdf_and_json.tar.bz2")
    ap.add_argument("--out-dir", type=Path, help="output dataset dir (train/valid/test + manifest)")
    ap.add_argument("--max-confs-per-mol", type=int, default=8,
                    help="conformers/molecule cap (CREMP SDFs list many; sample the first N)")
    ap.add_argument("--max-train-mols", type=int, default=None, help="cap #train molecules (None=all)")
    ap.add_argument("--max-val-mols", type=int, default=400, help="cap #val molecules")
    ap.add_argument("--max-test-mols", type=int, default=300,
                    help="cap #test molecules (mirrors M0's 300 held-out for eval parity)")
    args = ap.parse_args(argv)

    if args.smoke:
        return _smoke()
    if not args.cremp_dir or not args.out_dir:
        print("FATAL: --cremp-dir and --out-dir are required (or use --smoke)", file=sys.stderr)
        return 2

    t0 = time.time()
    stats = build(args.cremp_dir, args.out_dir, args.max_confs_per_mol,
                  args.max_train_mols, args.max_val_mols, args.max_test_mols)
    stats["elapsed_sec"] = round(time.time() - t0, 1)
    with open(Path(args.out_dir) / "manifest.json", "w") as m:
        json.dump(stats, m, indent=2)
    print(json.dumps(stats, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
