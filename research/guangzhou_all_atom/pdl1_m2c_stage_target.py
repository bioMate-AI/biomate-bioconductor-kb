#!/usr/bin/env python3
"""pdl1_m2c_stage_target.py — stage ONE receptor target (default PD-L1, PDB 5O45) as a PepGLAD
CoDesignDataset GENERATION target for the M2c cyclic-peptide generator, then (optionally) build length
variants so the M2c generator can sample de-novo cyclic binders of length ~10-16 conditioned on the pocket.

This is the DIVERSITY-ARM data step for ACT Round-1 (docs/20260930_ACT_APPLICATION_WORKING_PROTOCOL.md §3;
docs/20260930_PEPTIDE_GEN_IN_BIOMATE_AND_ACT_HARNESS_PLAN.md §4a). It reuses the VERIFIED converter path
from m2c_process_complexes.py so the staged target re-parses byte-identically to how the M2c model was trained.

============================================================================================================
WHY THIS SHIM (the verified generate.py / CoDesignDataset contract — read the runtime, do NOT assume)
============================================================================================================
generate.py (runtime/PepGLAD/generate.py) + CoDesignDataset (data/codesign.py) impose this contract, which
this file is built to satisfy EXACTLY (every claim below is grounded in the runtime source):

  * generate.py loads `_, _, test_set = create_dataset(config['dataset'])` (the 'test' slot) and for each
    target samples n_samples designs. It NEVER chooses the peptide length freely: CoDesignDataset.__getitem__
    sets mask=1 for exactly `len(lig_blocks)` ligand positions (codesign.py:96), and ldm.sample() overwrites
    ONLY those masked positions (ldm.py:169-175, X[mask]=0 / S[mask]=latent_idx -> new latent -> decode).
    => THE GENERATED PEPTIDE LENGTH == THE NUMBER OF LIGAND BLOCKS IN THE STAGED COMPLEX. To sample a length
       range (10..16) we stage one target per length (the native 14-mer + truncated variants), each a
       separate mmap row / test-index entry. The native peptide is used ONLY as a length + backbone scaffold
       and to DEFINE THE POCKET; its sequence/coords are discarded by ldm.sample (masked out).

  * the RECEPTOR (pocket) conditions the diffusion (the ~mask positions carry real coords). The pocket set is
    props[-1] = blocks_cb_interface(rec, lig, pocket_th) — receptor residues whose (virtual) CB is within
    pocket_th A of a ligand CB (process.py:33 + blocks_interface.py:77). This is PepGLAD's OWN pocket
    definition (CB-CB, default 10 A). It is NOT identical to boltzgen_ourtarget.sh's pocket (receptor atoms
    within 5 A of ANY native-peptide heavy atom, all-atom). We use the SAME native peptide chain B (incl.
    non-canonical residues) to DEFINE the pocket in both pipelines, but the geometric rule differs by design
    of each harness. Documented honestly in the review note; do NOT silently claim the pockets are identical.

  * get_summary (codesign.py:59) returns (id, mmap_dir/../pdbs/<id>.pdb, props[4]=rec_chain, props[5]=lig_chain);
    generate.py.save_data (generate.py:115) re-reads that ref pdb via pdb_to_list_blocks(selected_chains=
    [rec_chain, lig_chain]) and asserts len(lig_blocks) == len(generated S). Because BOTH the mmap ligand and
    the ref-pdb ligand come from the SAME staged 2-chain pdb via the SAME converter, they match by construction.

  * 5O45 chain B (verified against the RCSB mmCIF): 14 residues, ALL with full N/CA/C/O backbone (so all 14
    survive Block.is_residue(), format.py:206) — 9 canonical + 5 non-canonical (MEA x2, 9KK, SAR x2, CCS) —
    plus an NH2 C-terminal cap that is auto-dropped (no backbone). The 5 ncAAs map to VOCAB UNK '?' (format.py
    :56) so lig_seq has '?' and process.py sets non_standard=1 (process.py:45) — HARMLESS for generation
    because the ligand sequence is masked/overwritten by ldm.sample. The ncAA HETATM records DO carry N/CA/C/O
    so they contribute a valid length-14 backbone scaffold + pocket contacts. => native length 14 is already
    inside the requested 10..16 band; length variants 10/12/14/16 give the requested de-novo length diversity.

OUTPUT LAYOUT (the STOCK two-level layout get_summary + process.py both require — verified):
  <out-dir>/pdbs/<id>.pdb                    staged 2-chain complexes (one per length variant)
  <out-dir>/index.txt                        chain-only index process.py consumes (dirname/pdbs/<id>.pdb)
  <out-dir>/processed/data.bin, index.txt    the mmap (byte offsets + props incl. pocket idxs)
  <out-dir>/processed/test_index.txt         the GENERATION targets (all staged length variants)
  <out-dir>/processed/train_index.txt        == test_index.txt (used ONLY by setup_latent_guidance to compute
                                             consec-dist IF energy guidance is on; see the driver's note)
  <out-dir>/manifest.json                    provenance: pocket size, pocket_th, lengths staged, ncAA note

USAGE
  python3 pdl1_m2c_stage_target.py \
      --pdb 5o45 --rec-chain A --pep-chain B \
      --out-dir ./data/pdl1_m2c_target --pocket-th 10.0 \
      --lengths 10,12,14,16            # de-novo length band; native = 14
"""
from __future__ import annotations

import argparse
import gzip
import json
import os
import sys
import time
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent
RUNTIME = ROOT / "runtime" / "PepGLAD"
for p in (str(RUNTIME), str(ROOT)):
    if p not in sys.path:
        sys.path.insert(0, p)

RCSB_CIF = "https://files.rcsb.org/download/{pdb}.cif"


# --------------------------------------------------------------------------- fetch mmCIF
def _fetch_cif_text(pdb: str, timeout: int = 60, retries: int = 4) -> str:
    """Fetch the ORIGINAL RCSB mmCIF (uncompressed endpoint; falls back to .gz)."""
    last = None
    for url in (RCSB_CIF.format(pdb=pdb.lower()), RCSB_CIF.format(pdb=pdb.lower()) + ".gz"):
        for _ in range(retries):
            try:
                with urllib.request.urlopen(url, timeout=timeout) as r:
                    raw = r.read()
                if url.endswith(".gz"):
                    return gzip.decompress(raw).decode("utf-8", "replace")
                return raw.decode("utf-8", "replace")
            except Exception as e:  # noqa: BLE001
                last = e
                time.sleep(2)
    raise RuntimeError(f"RCSB cif fetch failed for {pdb}: {last}")


# --------------------------------------------------------------------------- stage the target complex
def stage_target(pdb4: str, rec_chain: str, pep_chain: str, tmp_dir: Path):
    """Fetch <pdb4>, extract [rec_chain, pep_chain] via PepGLAD's OWN converter (identical to
    m2c_process_complexes.stage_one), return (rec_blocks, pep_blocks). The pep chain is the FULL native
    macrocycle (all residues with a backbone, incl. non-canonical) — used ONLY for pocket definition +
    length scaffold; its sequence is discarded at generation. Raises on failure (single target -> fatal)."""
    from data.converter.pdb_to_list_blocks import pdb_to_list_blocks
    from Bio.PDB.MMCIFParser import MMCIFParser
    from Bio.PDB import PDBIO
    import warnings
    warnings.filterwarnings("ignore")

    cif_text = _fetch_cif_text(pdb4)
    cif_path = tmp_dir / f"{pdb4}.cif"
    cif_path.write_text(cif_text)
    pdb_tmp = tmp_dir / f"{pdb4}_full.pdb"
    structure = MMCIFParser(QUIET=True).get_structure(pdb4, str(cif_path))
    io = PDBIO()
    io.set_structure(structure)
    io.save(str(pdb_tmp))   # model 1 only downstream (pdb_to_list_blocks uses model 1)

    blocks_by_chain = pdb_to_list_blocks(str(pdb_tmp), dict_form=True)
    if rec_chain not in blocks_by_chain:
        raise RuntimeError(f"rec_chain {rec_chain} absent (have={list(blocks_by_chain)[:12]})")
    if pep_chain not in blocks_by_chain:
        raise RuntimeError(f"pep_chain {pep_chain} absent (have={list(blocks_by_chain)[:12]})")
    rec_blocks = blocks_by_chain[rec_chain]
    pep_blocks = blocks_by_chain[pep_chain]
    if len(pep_blocks) < 3:
        raise RuntimeError(f"native peptide too short after backbone filter: {len(pep_blocks)}")
    if len(rec_blocks) < 20:
        raise RuntimeError(f"receptor too short: {len(rec_blocks)}")
    for f in (cif_path, pdb_tmp):
        try:
            f.unlink()
        except OSError:
            pass
    return rec_blocks, pep_blocks


def make_length_variant(pep_blocks, L: int):
    """Return a length-L contiguous slice of the native peptide backbone, centered on the native peptide so
    the scaffold stays inside the pocket. L == len(native) -> the native peptide itself. L < len(native) ->
    a centered contiguous window (keeps the residues most buried in the pocket for shorter designs). L >
    len(native) is NOT supported by the scaffold approach (would need to invent backbone) -> caller clamps
    lengths to <= native length; longer designs are the BoltzGen arm's job (documented)."""
    n = len(pep_blocks)
    if L >= n:
        return list(pep_blocks)
    start = (n - L) // 2
    return list(pep_blocks[start:start + L])


# --------------------------------------------------------------------------- run stock process.py per variant
def run_stock_process(staged_index: Path, out_dir: Path, pocket_th: float):
    """Reuse the EXACT driver from m2c_process_complexes (stock process_iterator by file path -> identical
    featurization). Returns the list of pdb_ids that passed the interface/pocket filters, in mmap order."""
    from data.mmap_dataset import create_mmap
    from utils.logger import print_log
    import importlib.util
    _proc_path = RUNTIME / "scripts" / "data_process" / "process.py"
    _spec = importlib.util.spec_from_file_location("pepglad_stock_process", str(_proc_path))
    _mod = importlib.util.module_from_spec(_spec)
    _spec.loader.exec_module(_mod)
    process_iterator = _mod.process_iterator

    with open(staged_index) as fin:
        lines = [ln for ln in fin.read().splitlines() if ln.strip()]
    root_dir = os.path.dirname(str(staged_index))
    indexes = {}
    for line in lines:
        c = line.split("\t")
        indexes[c[0]] = {"rec_chain": c[1], "pep_chain": c[2],
                         "pdb_path": os.path.join(root_dir, "pdbs", c[0] + ".pdb")}
    os.makedirs(out_dir, exist_ok=True)
    kept_ids = []

    def _counting_iter():
        for pdb_id, data, props, cnt in process_iterator(indexes, pocket_th):
            kept_ids.append(pdb_id)
            yield pdb_id, data, props, cnt

    create_mmap(_counting_iter(), str(out_dir), len(indexes))
    print_log(f"process.py: {len(kept_ids)}/{len(indexes)} target variants passed interface/pocket filters")
    return kept_ids


# --------------------------------------------------------------------------- main
def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--pdb", default="5o45", help="RCSB 4-char id of the target complex")
    ap.add_argument("--rec-chain", default="A", help="receptor (target) chain id")
    ap.add_argument("--pep-chain", default="B", help="native peptide chain id (pocket definer / length scaffold)")
    ap.add_argument("--out-dir", type=Path, required=True)
    ap.add_argument("--pocket-th", type=float, default=10.0, help="PepGLAD CB-CB pocket threshold (stock 10 A)")
    ap.add_argument("--lengths", default="10,12,14,16",
                    help="comma-sep de-novo peptide lengths to stage (clamped to <= native length)")
    args = ap.parse_args(argv)

    out_dir = args.out_dir
    pdbs_dir = out_dir / "pdbs"
    tmp_dir = out_dir / "_tmp"
    processed_dir = out_dir / "processed"
    for d in (pdbs_dir, tmp_dir, processed_dir):
        d.mkdir(parents=True, exist_ok=True)

    from data.converter.list_blocks_to_pdb import list_blocks_to_pdb

    print(f"[stage] fetching {args.pdb} chains [{args.rec_chain},{args.pep_chain}] ...", flush=True)
    rec_blocks, pep_blocks = stage_target(args.pdb, args.rec_chain, args.pep_chain, tmp_dir)
    native_len = len(pep_blocks)
    print(f"[stage] receptor {args.rec_chain}: {len(rec_blocks)} residues; "
          f"native peptide {args.pep_chain}: {native_len} residues (backbone-complete)", flush=True)

    want = sorted({int(x) for x in args.lengths.split(",") if x.strip()})
    lengths = [L for L in want if 3 <= L <= native_len]
    dropped_lengths = [L for L in want if L > native_len]
    if not lengths:
        print(f"FATAL: no requested length in [3,{native_len}]", file=sys.stderr)
        return 2

    # write one staged pdb + one index line per length variant
    staged = []
    for L in lengths:
        pep_L = make_length_variant(pep_blocks, L)
        vid = f"{args.pdb.upper()}_pdl1_L{L:02d}"
        out_pdb = pdbs_dir / f"{vid}.pdb"
        list_blocks_to_pdb([rec_blocks, pep_L], [args.rec_chain, args.pep_chain], str(out_pdb))
        staged.append((vid, L))
        print(f"[stage] wrote {vid}.pdb (peptide length {L})", flush=True)

    staged_index = out_dir / "index.txt"
    with open(staged_index, "w") as f:
        for vid, _ in staged:
            f.write(f"{vid}\t{args.rec_chain}\t{args.pep_chain}\t0\n")

    print("[process] running stock process.py -> mmap ...", flush=True)
    kept_ids = run_stock_process(staged_index, processed_dir, args.pocket_th)
    if not kept_ids:
        print("FATAL: 0 target variants survived process.py interface/pocket filters", file=sys.stderr)
        return 2

    # read the mmap index to (a) get pocket sizes, (b) drop degenerate pockets (<3 residues -> covariance
    # crash in codesign.py:126-129, the SAME guard m2c_process applies) and build the generation test index.
    mmap_index = processed_dir / "index.txt"
    id2line, pocket_sizes = {}, {}
    n_degenerate = 0
    with open(mmap_index) as f:
        for line in f:
            if not line.strip():
                continue
            fields = line.rstrip("\n").split("\t")
            _id = fields[0]
            pocket = fields[-1].strip() if len(fields) > 1 else ""
            n_pocket = len([x for x in pocket.split(",") if x != ""]) if pocket else 0
            if n_pocket < 3:
                n_degenerate += 1
                continue
            id2line[_id] = line
            pocket_sizes[_id] = n_pocket

    if not id2line:
        print("FATAL: all target variants had a degenerate (<3 residue) pocket", file=sys.stderr)
        return 2

    # generation targets = every usable variant. train_index == test_index: setup_latent_guidance (if energy
    # guidance is on) computes consec-dist over whatever the 'test'-slot index points at; with a SINGLE target
    # there is no held-out train distribution, so we let it estimate consec-dist from the target variants
    # themselves (a mild, honest self-prior). The DEFAULT generation config disables energy guidance instead
    # (energy_func: null) — see pdl1_m2c_generate.py's note. Both files written so either path works.
    test_index = processed_dir / "test_index.txt"
    train_index = processed_dir / "train_index.txt"
    with open(test_index, "w") as ft, open(train_index, "w") as tr:
        for _id, line in id2line.items():
            ft.write(line)
            tr.write(line)

    manifest = {
        "experiment": "M2c PepGLAD generation-target staging (ACT Round-1 diversity arm)",
        "utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "pdb": args.pdb.upper(),
        "rec_chain": args.rec_chain,
        "pep_chain": args.pep_chain,
        "native_peptide_length": native_len,
        "lengths_requested": want,
        "lengths_staged": lengths,
        "lengths_dropped_gt_native": dropped_lengths,
        "n_target_variants_in_mmap": len(kept_ids),
        "n_generation_targets": len(id2line),
        "n_dropped_degenerate_pocket": n_degenerate,
        "pocket_sizes_by_variant": pocket_sizes,
        "pocket_th_cb_cb": args.pocket_th,
        "receptor_residues": len(rec_blocks),
        "note": (
            "GENERATION target (not a train/eval split). Peptide length == #ligand blocks per variant; "
            "ldm.sample overwrites the ligand seq+coords conditioned on the pocket, so the native macrocycle "
            "serves ONLY as pocket definition + length scaffold. 5O45 chain B has 5 non-canonical residues "
            "(MEA/9KK/SAR/CCS) which map to VOCAB UNK '?' -> non_standard=1, harmless (masked at generation). "
            "POCKET DEFINITION DIFFERS from boltzgen_ourtarget.sh: PepGLAD uses CB-CB within pocket_th (10 A) "
            "on the SAME native peptide; boltzgen uses receptor atoms within 5 A of any native-peptide heavy "
            "atom. Same peptide, different geometric rule (each harness's own convention)."
        ),
    }
    (out_dir / "manifest.json").write_text(json.dumps(manifest, indent=2))
    try:
        for p in tmp_dir.iterdir():
            p.unlink()
        tmp_dir.rmdir()
    except OSError:
        pass
    print(json.dumps(manifest, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
