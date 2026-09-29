#!/usr/bin/env python3
"""m2c_process_complexes.py — turn the D2 bound-cyclic index (235 experimental complexes) into a PepGLAD
CoDesignDataset mmap, using the OFFICIAL scripts/data_process/process.py, plus a cyclic-aware train/val/test
split. This is the 2c data step. Runs on the instance (CPU + light network). NO GPU.

============================================================================================================
THE VERIFIED process.py INPUT CONTRACT (read runtime/PepGLAD/scripts/data_process/process.py — do NOT assume)
============================================================================================================
process.py (the stock PDB-complex -> mmap processor) does, per line of --index:
    pdb_id   = line[0]                       # the WHOLE first column, e.g. "11MG_C"
    rec_chain= line[1]                       # a SINGLE chain id string
    pep_chain= line[2]                       # a SINGLE chain id string
    pdb_path = <dir(index)>/pdbs/<pdb_id>.pdb   # <-- PRE-STAGED .pdb REQUIRED, one file per entry
then: rec_blocks, lig_blocks = pdb_to_list_blocks(pdb_path, selected_chains=[rec_chain, pep_chain])
      blocks_interface(...6A) must be non-empty; blocks_cb_interface(...pocket_th) must not KeyError;
      writes an mmap (data.bin + index.txt) whose properties row ends with the comma-joined pocket residue idxs.

  => process.py FETCHES NOTHING. It reads `pdbs/<pdb_id>.pdb` off disk. The D2 index does NOT ship those
     .pdb files (verified: s3://.../bound_cyclic_v1/ has only index.txt + manifest + summary, NO pdbs/).
     So the D2 index does NOT feed process.py directly — a STAGING SHIM is required (this script), which:
       (a) reads the D2 manifest/index,
       (b) fetches each entry's mmCIF from RCSB (files.rcsb.org),
       (c) parses it with PepGLAD's OWN pdb_to_list_blocks and re-emits pdbs/<pdb_id>.pdb containing EXACTLY
           the [rec_chain, pep_chain] two chains (so process.py re-parses it identically — same code path),
       (d) writes a fresh index.txt (dropping entries whose staging failed),
     then invokes the STOCK process.py verbatim on that staged dir, then splits.

WHY RE-EMIT VIA list_blocks_to_pdb (not just dump the raw cif chains): process.py -> pdb_to_list_blocks uses
Biopython single-char chain ids and drops solvent/HETATM. Re-emitting through the SAME converter guarantees
the staged .pdb is exactly what process.py expects (no altloc / multi-model / assembly surprises), and lets
us map a possibly multi-char mmCIF auth chain id onto the single-char id the D2 index recorded.

MULTI-CHAIN RECEPTOR NOTE (honest limiter): the D2 miner recorded rec_chains as a LIST (e.g. ["A","D","B"])
but its index.txt kept only the FIRST (line[1]). process.py itself only ever uses ONE rec_chain. So 2c trains
against the single largest receptor chain of each complex — consistent with process.py's design, but for a few
multi-chain-epitope complexes the pocket may be under-represented. Flagged in the review note; matches stock.

============================================================================================================
THE SPLIT (235 is small -> a real held-out test, leakage-aware)
============================================================================================================
process.py builds ONE mmap over ALL staged entries. The stock pipeline then uses scripts/data_process/split.py
to write train_index.txt / valid_index.txt / test_index.txt (subsets of the same index.txt, sharing data.bin;
selected via CoDesignDataset(specify_index=...)). We reproduce that mechanism here with a SEQUENCE-IDENTITY-
AWARE assignment so the tiny test set is not a near-duplicate of train:
  * group entries by peptide-sequence cluster (greedy single-linkage at >=0.6 identity over equal-length
    peptides; different lengths never cluster). Whole clusters go to one split (no cluster spans splits) ->
    no train/test leakage from redundant PDB depositions (e.g. the 11MG/11MH or 1CWA..1CWH families visible
    in the index share a peptide).
  * default split ~ 80/10/10 by CLUSTER, but guarantee >= MIN_TEST test entries and >= 1 val.
  * deterministic (seeded) so a spot-resume re-derives the identical split.
This is stricter than the stock random split (which had far more data); with n~235 leakage control matters more.

OUTPUT LAYOUT (VERIFIED against the stock convention — codesign.py:62 reads pdbs at mmap_dir/../pdbs, and
process.py reads pdbs at dirname(index)/pdbs; both agree ONLY with this two-level layout):
  <out-dir>/pdbs/<id>.pdb                 staged 2-chain complexes
  <out-dir>/index.txt                     the staged index process.py reads (dirname(index)/pdbs/<id>.pdb)
  <out-dir>/processed/data.bin,index.txt  the mmap (process.py --out_dir = <out-dir>/processed)
  <out-dir>/processed/{train,valid,test}_index.txt   the split subsets (stock specify_index mechanism)
  <out-dir>/manifest.json                 provenance: counts, dropped entries + reasons, split sizes, leakage
  => TRAIN/EVAL configs point mmap_dir at <out-dir>/processed; get_summary then resolves
     <out-dir>/processed/../pdbs = <out-dir>/pdbs. Matches configs/pepbench/*/mmap_dir: .../processed.

USAGE
  python3 m2c_process_complexes.py \
      --d2-dir ./data/bound_cyclic_v1 \       # contains index.txt + bound_cyclic_manifest.jsonl
      --out-dir ./data/bound_cyclic_pepglad \
      --pocket-th 10.0 --min-test 24 --val-frac 0.1 --test-frac 0.1 --seed 12
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

RCSB_CIF = "https://files.rcsb.org/download/{pdb}.cif.gz"


# --------------------------------------------------------------------------- fetch + stage one complex
def _fetch_cif_text(pdb: str, timeout: int = 60, retries: int = 4) -> str:
    url = RCSB_CIF.format(pdb=pdb.lower())
    last = None
    for _ in range(retries):
        try:
            with urllib.request.urlopen(url, timeout=timeout) as r:
                raw = r.read()
            return gzip.decompress(raw).decode("utf-8", "replace")
        except Exception as e:  # noqa: BLE001
            last = e
            time.sleep(2)
    raise RuntimeError(f"RCSB cif fetch failed for {pdb}: {last}")


def _write_cif_tmp(pdb_id: str, cif_text: str, tmp_dir: Path) -> Path:
    p = tmp_dir / f"{pdb_id}.cif"
    p.write_text(cif_text)
    return p


def stage_one(pdb4: str, pdb_id: str, rec_chain: str, pep_chain: str, pdbs_dir: Path, tmp_dir: Path):
    """Fetch <pdb4> mmCIF, extract [rec_chain, pep_chain] via PepGLAD's own converter, re-emit
    pdbs/<pdb_id>.pdb. Returns (ok: bool, reason: str). Uses the SAME converters process.py uses so the
    staged file re-parses identically downstream."""
    # PepGLAD converters need Biopython; imported here so an import error is reported per-entry, not fatal.
    from data.converter.pdb_to_list_blocks import pdb_to_list_blocks
    from data.converter.list_blocks_to_pdb import list_blocks_to_pdb

    try:
        cif = _fetch_cif_text(pdb4)
    except Exception as e:  # noqa: BLE001
        return False, f"fetch_failed:{type(e).__name__}"

    # Biopython can read mmCIF via MMCIFParser, but pdb_to_list_blocks uses PDBParser. Convert the cif to a
    # PDB first using Biopython's MMCIFParser -> PDBIO, then run the SAME pdb_to_list_blocks process.py uses.
    from Bio.PDB.MMCIFParser import MMCIFParser
    from Bio.PDB import PDBIO
    import warnings
    warnings.filterwarnings("ignore")

    cif_path = _write_cif_tmp(pdb_id, cif, tmp_dir)
    pdb_tmp = tmp_dir / f"{pdb_id}_full.pdb"
    try:
        structure = MMCIFParser(QUIET=True).get_structure(pdb_id, str(cif_path))
        # first model only (PDBIO writes all; pdb_to_list_blocks already uses model 1 only)
        io = PDBIO()
        io.set_structure(structure)
        io.save(str(pdb_tmp))
    except Exception as e:  # noqa: BLE001
        return False, f"cif_to_pdb_failed:{type(e).__name__}"
    finally:
        try:
            cif_path.unlink()
        except OSError:
            pass

    # PDB single-char chain ids: if the mmCIF auth chain ids were multi-char, MMCIFParser->PDBIO truncates/
    # renames them, so verify our two chains still resolve. Try requested ids; if absent, report (dropped).
    try:
        blocks_by_chain = pdb_to_list_blocks(str(pdb_tmp), dict_form=True)
    except Exception as e:  # noqa: BLE001
        return False, f"parse_failed:{type(e).__name__}"
    finally:
        pass

    if rec_chain not in blocks_by_chain:
        return False, f"rec_chain_absent:{rec_chain}(have={list(blocks_by_chain)[:8]})"
    if pep_chain not in blocks_by_chain:
        return False, f"pep_chain_absent:{pep_chain}(have={list(blocks_by_chain)[:8]})"
    if pep_chain == rec_chain:
        return False, "pep_eq_rec"

    rec_blocks = blocks_by_chain[rec_chain]
    pep_blocks = blocks_by_chain[pep_chain]
    if len(pep_blocks) < 3:
        return False, f"peptide_too_short:{len(pep_blocks)}"
    if len(rec_blocks) < 5:
        return False, f"receptor_too_short:{len(rec_blocks)}"

    out = pdbs_dir / f"{pdb_id}.pdb"
    try:
        list_blocks_to_pdb([rec_blocks, pep_blocks], [rec_chain, pep_chain], str(out))
    except Exception as e:  # noqa: BLE001
        return False, f"emit_failed:{type(e).__name__}"
    try:
        pdb_tmp.unlink()
    except OSError:
        pass
    return True, "ok"


# --------------------------------------------------------------------------- D2 index / manifest readers
def read_d2(d2_dir: Path):
    """Return list of {pdb_id, pdb4, rec_chain, pep_chain, peptide_seq, cyclization_type, conformer_provenance}
    from the D2 index.txt (+ manifest for seq/provenance). index line: pdb_id\\trec\\tpep\\t0."""
    idx = d2_dir / "index.txt"
    man = d2_dir / "bound_cyclic_manifest.jsonl"
    rows = []
    # manifest keyed by (pdb4, pep_chain) for seq/provenance enrichment
    meta = {}
    if man.is_file():
        for line in man.read_text().splitlines():
            if not line.strip():
                continue
            r = json.loads(line)
            if r.get("status") != "ok":
                continue
            meta[(r["pdb_id"].upper(), r["pep_chain"])] = r
    for line in idx.read_text().splitlines():
        if not line.strip():
            continue
        parts = line.rstrip("\n").split("\t")
        if len(parts) < 3:
            continue
        pdb_id, rec_chain, pep_chain = parts[0], parts[1], parts[2]
        pdb4 = pdb_id.split("_")[0]
        m = meta.get((pdb4.upper(), pep_chain), {})
        rows.append({
            "pdb_id": pdb_id,
            "pdb4": pdb4,
            "rec_chain": rec_chain,
            "pep_chain": pep_chain,
            "peptide_seq": m.get("peptide_seq", ""),
            "cyclization_type": m.get("cyclization_type", "unknown"),
            "conformer_provenance": m.get("conformer_provenance", "PDB_experimental"),
        })
    return rows


# --------------------------------------------------------------------------- sequence-cluster split
def _identity(a: str, b: str) -> float:
    """Position-wise identity for equal-length strings; 0 for different lengths (peptides of diff length
    never cluster). Cheap + deterministic; sufficient at this scale (235 short peptides)."""
    if len(a) != len(b) or not a:
        return 0.0
    same = sum(1 for x, y in zip(a, b) if x == y)
    return same / len(a)


def cluster_by_sequence(rows, id_th: float = 0.6):
    """Greedy single-linkage clustering by peptide sequence identity. Entries with empty seq get their own
    singleton cluster (conservative: never merge unknown seqs). Returns list of clusters (each a list of
    row-indexes)."""
    n = len(rows)
    parent = list(range(n))

    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    def union(x, y):
        parent[find(x)] = find(y)

    for i in range(n):
        si = rows[i]["peptide_seq"]
        if not si:
            continue
        for j in range(i + 1, n):
            sj = rows[j]["peptide_seq"]
            if not sj:
                continue
            if _identity(si, sj) >= id_th:
                union(i, j)
    clusters = {}
    for i in range(n):
        clusters.setdefault(find(i), []).append(i)
    return list(clusters.values())


def split_clusters(clusters, n_total, val_frac, test_frac, min_test, seed):
    """Assign whole clusters to train/val/test. Test filled FIRST to guarantee >= min_test, then val, rest
    train. Deterministic (seeded shuffle of clusters, largest-first tie-break for stable sizes)."""
    import random
    rng = random.Random(seed)
    # sort clusters by size desc for stable filling, then shuffle within equal sizes for variety
    order = sorted(range(len(clusters)), key=lambda k: (-len(clusters[k]), k))
    rng.shuffle(order)  # seeded
    want_test = max(min_test, int(round(test_frac * n_total)))
    want_val = max(1, int(round(val_frac * n_total)))
    test, val, train = [], [], []
    n_test = n_val = 0
    for k in order:
        cl = clusters[k]
        if n_test < want_test:
            test.extend(cl); n_test += len(cl)
        elif n_val < want_val:
            val.extend(cl); n_val += len(cl)
        else:
            train.extend(cl)
    return train, val, test


# --------------------------------------------------------------------------- run stock process.py
def run_stock_process(staged_index: Path, out_dir: Path, pocket_th: float):
    """Invoke the OFFICIAL scripts/data_process/process.py on the staged dir. process.py reads
    <dir(index)>/pdbs/<id>.pdb, so `staged_index` must sit next to the pdbs/ dir. It writes data.bin +
    index.txt into out_dir."""
    from data.mmap_dataset import create_mmap
    from data.format import VOCAB
    from data.converter.pdb_to_list_blocks import pdb_to_list_blocks
    from data.converter.blocks_interface import blocks_interface, blocks_cb_interface
    from utils.logger import print_log

    # Re-implement process.py.main's driver here so we can COUNT drops (interface-empty / missing-backbone)
    # instead of silently `continue`-ing, while calling the SAME per-entry logic (process_iterator). scripts/
    # is NOT a package (no __init__.py), so load the stock module by FILE PATH via importlib and pull its
    # process_iterator — this guarantees IDENTICAL featurization to the official process.py.
    import importlib.util
    _proc_path = RUNTIME / "scripts" / "data_process" / "process.py"
    _spec = importlib.util.spec_from_file_location("pepglad_stock_process", str(_proc_path))
    _mod = importlib.util.module_from_spec(_spec)
    _spec.loader.exec_module(_mod)
    process_iterator = _mod.process_iterator  # the stock iterator (unchanged)

    with open(staged_index, "r") as fin:
        lines = [ln for ln in fin.read().splitlines() if ln.strip()]
    indexes = {}
    root_dir = os.path.dirname(str(staged_index))
    for line in lines:
        c = line.split("\t")
        pdb_id = c[0]
        indexes[pdb_id] = {
            "rec_chain": c[1],
            "pep_chain": c[2],
            "pdb_path": os.path.join(root_dir, "pdbs", pdb_id + ".pdb"),
        }
    if not os.path.exists(out_dir):
        os.makedirs(out_dir)
    # process_iterator yields only the entries that passed (interface non-empty, backbone present). We wrap it
    # to record which pdb_ids actually made it into the mmap (so the split only references real mmap rows).
    kept_ids = []

    def _counting_iter():
        for pdb_id, data, props, cnt in process_iterator(indexes, pocket_th):
            kept_ids.append(pdb_id)
            yield pdb_id, data, props, cnt

    create_mmap(_counting_iter(), str(out_dir), len(indexes))
    print_log(f"process.py: {len(kept_ids)}/{len(indexes)} entries passed interface/pocket filters")
    return kept_ids


# --------------------------------------------------------------------------- main
def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--d2-dir", type=Path, required=True, help="dir with index.txt + bound_cyclic_manifest.jsonl")
    ap.add_argument("--out-dir", type=Path, required=True)
    ap.add_argument("--pocket-th", type=float, default=10.0)
    ap.add_argument("--min-test", type=int, default=24, help="floor for the held-out test set size")
    ap.add_argument("--val-frac", type=float, default=0.1)
    ap.add_argument("--test-frac", type=float, default=0.1)
    ap.add_argument("--id-th", type=float, default=0.6, help="peptide-seq identity threshold for clustering")
    ap.add_argument("--seed", type=int, default=12)
    ap.add_argument("--sleep", type=float, default=0.1, help="delay between RCSB fetches (s)")
    ap.add_argument("--limit", type=int, default=0, help="cap #entries staged (0 = all); for a quick dry run")
    args = ap.parse_args(argv)

    out_dir = args.out_dir
    pdbs_dir = out_dir / "pdbs"
    tmp_dir = out_dir / "_tmp"
    pdbs_dir.mkdir(parents=True, exist_ok=True)
    tmp_dir.mkdir(parents=True, exist_ok=True)

    rows = read_d2(args.d2_dir)
    if args.limit:
        rows = rows[: args.limit]
    print(f"[stage] {len(rows)} D2 entries -> fetching + staging pdbs/ ...", flush=True)

    staged, dropped = [], []
    for i, r in enumerate(rows, 1):
        # resume-aware: skip if already staged
        if (pdbs_dir / f"{r['pdb_id']}.pdb").is_file():
            staged.append(r)
            continue
        ok, reason = stage_one(r["pdb4"], r["pdb_id"], r["rec_chain"], r["pep_chain"], pdbs_dir, tmp_dir)
        if ok:
            staged.append(r)
        else:
            dropped.append({**{k: r[k] for k in ("pdb_id", "rec_chain", "pep_chain")}, "reason": reason})
        if i % 25 == 0:
            print(f"[stage] {i}/{len(rows)} : {len(staged)} staged, {len(dropped)} dropped", flush=True)
        time.sleep(args.sleep)
    print(f"[stage] done: {len(staged)} staged, {len(dropped)} dropped", flush=True)

    # STOCK two-level layout: index.txt at <out-dir>/ (dirname(index)/pdbs), mmap at <out-dir>/processed/.
    processed_dir = out_dir / "processed"
    processed_dir.mkdir(parents=True, exist_ok=True)
    # write the staged index.txt at <out-dir>/index.txt so process.py resolves <out-dir>/pdbs/<id>.pdb.
    staged_index = out_dir / "index.txt"
    with open(staged_index, "w") as f:
        for r in staged:
            f.write(f"{r['pdb_id']}\t{r['rec_chain']}\t{r['pep_chain']}\t0\n")

    # run the STOCK process.py -> data.bin + index.txt in <out-dir>/processed; returns ids that passed filters
    print("[process] running stock process.py -> mmap ...", flush=True)
    kept_ids = run_stock_process(staged_index, processed_dir, args.pocket_th)
    kept_set = set(kept_ids)
    kept_rows = [r for r in staged if r["pdb_id"] in kept_set]
    if not kept_rows:
        print("FATAL: 0 entries survived process.py interface/pocket filters", file=sys.stderr)
        return 2

    # sequence-cluster split over the entries that ACTUALLY made it into the mmap
    clusters = cluster_by_sequence(kept_rows, args.id_th)
    tr_i, va_i, te_i = split_clusters(clusters, len(kept_rows), args.val_frac, args.test_frac,
                                      args.min_test, args.seed)

    # map mmap index.txt lines by id, then write train/valid/test subsets (the specify_index mechanism).
    # NOTE: the mmap's OWN index.txt (with byte offsets) lives in processed/, distinct from the staged
    # <out-dir>/index.txt (chain-only) process.py consumed.
    mmap_index = processed_dir / "index.txt"
    id2line = {}
    n_degenerate_pocket = 0
    with open(mmap_index) as f:
        for line in f:
            if not line.strip():
                continue
            fields = line.rstrip("\n").split("\t")
            _id = fields[0]
            # props[-1] is the comma-joined pocket residue idxs. use_covariance_matrix=True computes
            # np.cov over the receptor(pocket) CA atoms -> needs >=2 points for a valid 3x3 matrix
            # (a 1-residue pocket -> np.cov returns a 0-d scalar -> codesign.py:128 cov.shape[0] IndexError,
            # the exact crash we hit). Drop entries with <3 pocket residues so the covariance path is safe.
            pocket = fields[-1].strip() if len(fields) > 1 else ""
            n_pocket = len([x for x in pocket.split(",") if x != ""]) if pocket else 0
            if n_pocket < 3:
                n_degenerate_pocket += 1
                continue
            id2line[_id] = line
    id_of = lambda i: kept_rows[i]["pdb_id"]

    def _write(split_idxs, name):
        p = processed_dir / name    # splits live next to the mmap (stock: .../processed/train_index.txt)
        with open(p, "w") as f:
            for i in split_idxs:
                _id = id_of(i)
                if _id in id2line:  # defensive: only real mmap rows
                    f.write(id2line[_id])
        return sum(1 for i in split_idxs if id_of(i) in id2line)

    n_tr = _write(tr_i, "train_index.txt")
    n_va = _write(va_i, "valid_index.txt")
    n_te = _write(te_i, "test_index.txt")

    # leakage stat: max train/test peptide identity (should be < id_th by construction, report it)
    max_cross = 0.0
    tr_seqs = [kept_rows[i]["peptide_seq"] for i in tr_i]
    te_seqs = [kept_rows[i]["peptide_seq"] for i in te_i]
    for s in te_seqs:
        for t in tr_seqs:
            max_cross = max(max_cross, _identity(s, t))

    manifest = {
        "experiment": "2c D2 bound-cyclic complex processing (stock process.py + seq-cluster split)",
        "utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "d2_dir": str(args.d2_dir),
        "out_dir": str(out_dir),
        "n_d2_entries": len(rows),
        "n_staged": len(staged),
        "n_dropped_stage": len(dropped),
        "n_in_mmap": len(kept_rows),
        "n_dropped_process": len(staged) - len(kept_rows),
        "n_dropped_degenerate_pocket": n_degenerate_pocket,
        "n_usable": len(id2line),
        "split": {"train": n_tr, "valid": n_va, "test": n_te},
        "n_clusters": len(clusters),
        "max_train_test_peptide_identity": round(max_cross, 3),
        "id_th": args.id_th,
        "pocket_th": args.pocket_th,
        "by_cyclization_type_in_mmap": _count(kept_rows, "cyclization_type"),
        "dropped_stage_examples": dropped[:20],
        "note": ("process.py fetches NOTHING; it reads pdbs/<id>.pdb — this script stages those from RCSB via "
                 "PepGLAD's own converters. Split is whole-cluster (no train/test peptide leakage). Test set "
                 "is a floor of --min-test entries. Single rec_chain per complex (matches process.py)."),
    }
    (out_dir / "manifest.json").write_text(json.dumps(manifest, indent=2))
    # clean tmp
    try:
        for p in tmp_dir.iterdir():
            p.unlink()
        tmp_dir.rmdir()
    except OSError:
        pass
    print(json.dumps(manifest, indent=2))
    return 0


def _count(rows, key):
    out = {}
    for r in rows:
        out[r.get(key, "unknown")] = out.get(r.get(key, "unknown"), 0) + 1
    return out


if __name__ == "__main__":
    raise SystemExit(main())
