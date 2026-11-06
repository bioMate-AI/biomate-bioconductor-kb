#!/usr/bin/env python3
"""Per-fold pretraining-corpus filter (docs/20261028_V5_PREREG_AND_LOOP_INTERFACE.md V5-A3).
For each fold f, removes from the corpus every molecule that (a) has the same FLAT (stereo-free) canonical SMILES as any held-out compound of fold f, or
(b) has Morgan-r2 (2048-bit) Tanimoto >= 0.9 to any held-out compound of fold f. 'Held-out compounds' = every compound labelled on fold-f targets (+ benchmark items).
Exact (not approximate): popcount blocking is lossless because Tanimoto >= t implies min(a,b)/max(a,b) >= t.
usage: python3 filter_corpus.py CORPUS.smi.gz HELDOUT_DIR OUT_DIR [procs]
  HELDOUT_DIR/fold{f}.smi : one isomeric SMILES per line (held-out compounds of fold f)
  writes OUT_DIR/removed_fold{f}.npy (corpus line indices removed), OUT_DIR/filter_report.json"""
import sys, os, gzip, json, hashlib
import numpy as np
from multiprocessing import Pool
from rdkit import Chem, DataStructs, RDLogger
from rdkit.Chem import rdFingerprintGenerator
RDLogger.DisableLog("rdApp.*")
TAN = 0.9; NBITS = 2048
_POP = np.array([bin(i).count("1") for i in range(256)], dtype=np.uint16)
_gen = None


def _g():
    global _gen
    if _gen is None: _gen = rdFingerprintGenerator.GetMorganGenerator(radius=2, fpSize=NBITS)
    return _gen


def featurize(smi):
    """-> (flat_hash int64 or 0, popcount, packed fp (256,) uint8) ; failures -> (0, 0, zeros)."""
    m = Chem.MolFromSmiles(smi) if smi else None
    if m is None: return 0, 0, np.zeros(NBITS // 8, np.uint8)
    flat = Chem.MolToSmiles(m, isomericSmiles=False)
    h = int.from_bytes(hashlib.blake2b(flat.encode(), digest_size=8).digest(), "little", signed=True)
    fp = _g().GetFingerprintAsNumPy(m).astype(np.uint8); packed = np.packbits(fp)
    return h, int(fp.sum()), packed


def _chunk(lines): return [featurize(s) for s in lines]


def featurize_all(lines, procs):
    n = len(lines); step = 20000; chunks = [lines[i:i + step] for i in range(0, n, step)]
    with Pool(procs) as p: res = p.map(_chunk, chunks)
    flat = np.empty(n, np.int64); pc = np.empty(n, np.int32); fps = np.empty((n, NBITS // 8), np.uint8); k = 0
    for r in res:
        for h, c, f in r: flat[k] = h; pc[k] = c; fps[k] = f; k += 1
    return flat, pc, fps


def removed_for(heldout_smiles, c_flat, c_pc, c_fp, tan=TAN):
    """-> (set of corpus indices removed by flat match, set removed additionally by Tanimoto >= tan)."""
    h_flat, h_pc, h_fp = featurize_all(heldout_smiles, 1)
    ok = h_pc > 0; h_flat, h_pc, h_fp = h_flat[ok], h_pc[ok], h_fp[ok]
    flat_set = set(h_flat.tolist()); valid = c_pc > 0
    by_flat = np.nonzero(np.isin(c_flat, np.fromiter(flat_set, np.int64)) & valid)[0]
    order = np.argsort(c_pc, kind="stable"); spc = c_pc[order]; hit = np.zeros(len(c_pc), bool)
    for q in range(len(h_pc)):
        qc = int(h_pc[q]); lo = int(np.ceil(tan * qc)); hi = int(np.floor(qc / tan))
        a, b = np.searchsorted(spc, lo, "left"), np.searchsorted(spc, hi, "right")
        if b <= a: continue
        cand = order[a:b]; inter = _POP[np.bitwise_and(c_fp[cand], h_fp[q])].sum(1).astype(np.float64)
        t = inter / (c_pc[cand] + qc - inter); hit[cand[t >= tan]] = True
    by_tan = set(np.nonzero(hit)[0].tolist()) - set(by_flat.tolist())
    return set(by_flat.tolist()), by_tan


def featurize_sharded(lines, procs, shard_dir, shard=100000, log=print):
    """featurise in shards persisted as npz (resumable: existing shards are skipped), then concatenate. Logs progress per shard."""
    os.makedirs(shard_dir, exist_ok=True); n = len(lines); parts = []
    for si, s0 in enumerate(range(0, n, shard)):
        f = f"{shard_dir}/shard_{si:05d}.npz"
        if not os.path.exists(f):
            fl, pc, fp = featurize_all(lines[s0:s0 + shard], procs); tmp = f + ".tmp.npz"; np.savez(tmp, flat=fl, pc=pc, fp=fp); os.replace(tmp, f); log(f"shard {si} featurised ({min(s0 + shard, n)}/{n})")
        else: log(f"shard {si} reused")
        z = np.load(f); parts.append((z["flat"], z["pc"], z["fp"]))
    return np.concatenate([p[0] for p in parts]), np.concatenate([p[1] for p in parts]), np.concatenate([p[2] for p in parts])


if __name__ == "__main__":
    import argparse, time, urllib.request
    ap = argparse.ArgumentParser(); ap.add_argument("corpus"); ap.add_argument("heldout_dir"); ap.add_argument("out_dir"); ap.add_argument("--procs", type=int, default=8); ap.add_argument("--limit", type=int, default=0, help="canary: use only the first N corpus lines")
    ap.add_argument("--shard", type=int, default=100000); ap.add_argument("--tanimoto", type=float, default=TAN); a = ap.parse_args(); os.makedirs(a.out_dir, exist_ok=True)
    logf = open(f"{a.out_dir}/progress.log", "a")
    def log(m): s = f"{time.strftime('%H:%M:%S')} {m}"; print(s, flush=True); logf.write(s + "\n"); logf.flush()
    def imds(path):
        try:
            tok = urllib.request.urlopen(urllib.request.Request("http://169.254.169.254/latest/api/token", method="PUT", headers={"X-aws-ec2-metadata-token-ttl-seconds": "60"}), timeout=2).read().decode()
            return urllib.request.urlopen(urllib.request.Request("http://169.254.169.254/latest/meta-data/" + path, headers={"X-aws-ec2-metadata-token": tok}), timeout=2).read().decode()
        except Exception: return "unavailable"
    log(f"host instance_type={imds('instance-type')} az={imds('placement/availability-zone')} lifecycle={imds('instance-life-cycle')}")
    lines = [l.strip().split()[0] if l.strip() else "" for l in gzip.open(a.corpus, "rt")]
    if a.limit: lines = lines[:a.limit]
    log(f"corpus lines {len(lines)}")
    c_flat, c_pc, c_fp = featurize_sharded(lines, a.procs, f"{a.out_dir}/shards", a.shard, log); log(f"featurised; unparsable {int((c_pc == 0).sum())}")
    rep = {"corpus_lines": len(lines), "corpus_unparsable": int((c_pc == 0).sum()), "tanimoto_threshold": a.tanimoto, "folds": {}}; union = set()
    for f in range(5):
        hp = f"{a.heldout_dir}/fold{f}.smi"
        if not os.path.exists(hp): continue
        held = [l.strip() for l in open(hp) if l.strip()]; by_flat, by_tan = removed_for(held, c_flat, c_pc, c_fp, a.tanimoto)
        rem = np.array(sorted(by_flat | by_tan), dtype=np.int64); np.save(f"{a.out_dir}/removed_fold{f}.npy", rem); union |= set(rem.tolist())
        rep["folds"][f] = {"heldout_compounds": len(held), "removed_same_flat_structure": len(by_flat), "removed_tanimoto_additional": len(by_tan), "removed_total": int(len(rem)), "removed_frac": round(len(rem) / len(lines), 6)}
        log(f"fold {f} {json.dumps(rep['folds'][f])}")
    u = np.array(sorted(union), dtype=np.int64); np.save(f"{a.out_dir}/removed_union.npy", u); rep["union"] = {"removed_total": int(len(u)), "removed_frac": round(len(u) / max(len(lines), 1), 6), "corpus_after": int(len(lines) - len(u))}
    json.dump(rep, open(f"{a.out_dir}/filter_report.json", "w"), indent=1); log("DONE " + json.dumps(rep["union"]))
