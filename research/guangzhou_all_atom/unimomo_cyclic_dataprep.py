#!/usr/bin/env python3
"""Cyclic-specialization data-prep for the UniMoMo fine-tune.

Builds a UniMoMo pepbench index (pdb_id<TAB>rec_chain<TAB>pep_chain) + fetched pdbs/ from either:
  --mode train : the d2-mine cyclic manifest (bound_cyclic_manifest.jsonl), EXCLUDING the held-out
                 PepBDB-cyclic test PDB ids (train/eval hygiene — no leakage).
  --mode test  : the PepBDB-cyclic test_index.txt (the SAME 68/88 eval set), for a fair UniMoMo-format
                 cyclic eval (reprocessed through UniMoMo's own pepbench + DockQ harness).

Receptor-chain pick for multi-chain complexes: the rec chain with the MOST heavy atoms within 10 Å of
the peptide chain (pure-python PDB parse — no biotite/gemmi/torch dependency, runs anywhere). pepbench's
own pocket_th=10 then carves the true binding site from that chain.

Downstream: `python -m scripts.data_process.peptide.pepbench --index <out>/index.txt --out_dir <out>/processed [--remove_het]`
then split processed index -> train_index.txt / valid_index.txt (train mode).
"""
import argparse, json, os, sys, urllib.request, math
from collections import defaultdict

def fetch_pdb(pdb_id, dest):
    if os.path.exists(dest) and os.path.getsize(dest) > 0:
        return True
    url = f"https://files.rcsb.org/download/{pdb_id.upper()}.pdb"
    for _ in range(3):
        try:
            urllib.request.urlretrieve(url, dest)
            if os.path.getsize(dest) > 0:
                return True
        except Exception:
            continue
    return False

def parse_ca_and_heavy(pdb_path):
    """chain -> list of (x,y,z) heavy-atom coords (first model only)."""
    coords = defaultdict(list)
    with open(pdb_path) as f:
        for ln in f:
            if ln.startswith("ENDMDL"):
                break
            if ln.startswith("ATOM") or ln.startswith("HETATM"):
                elem = ln[76:78].strip() or ln[12:16].strip()[:1]
                if elem == "H":
                    continue
                ch = ln[21]
                try:
                    x, y, z = float(ln[30:38]), float(ln[38:46]), float(ln[46:54])
                except ValueError:
                    continue
                coords[ch].append((x, y, z))
    return coords

def best_rec_chain(pdb_path, rec_chains, pep_chain, cutoff=10.0):
    coords = parse_ca_and_heavy(pdb_path)
    pep = coords.get(pep_chain, [])
    if not pep:
        return rec_chains[0] if rec_chains else None
    c2 = cutoff * cutoff
    best, best_n = None, -1
    for rc in rec_chains:
        rec = coords.get(rc, [])
        n = 0
        for (px, py, pz) in pep:
            for (rx, ry, rz) in rec:
                dx, dy, dz = px - rx, py - ry, pz - rz
                if dx * dx + dy * dy + dz * dz <= c2:
                    n += 1
                    break  # count this pep atom as contacting; move on
        if n > best_n:
            best, best_n = rc, n
    return best if best_n > 0 else (rec_chains[0] if rec_chains else None)

def load_test_ids(test_index):
    ids = set()
    if test_index and os.path.exists(test_index):
        for ln in open(test_index):
            ln = ln.strip()
            if ln:
                ids.add(ln.split("\t")[0].split("_")[0].upper())
    return ids

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--mode", choices=["train", "test"], required=True)
    ap.add_argument("--manifest", help="d2-mine bound_cyclic_manifest.jsonl (train mode)")
    ap.add_argument("--test_index", help="PepBDB-cyclic test_index.txt (holdout in train mode; the eval set in test mode)")
    ap.add_argument("--out_dir", required=True)
    ap.add_argument("--min_len", type=int, default=5)
    ap.add_argument("--max_len", type=int, default=40)
    ap.add_argument("--type_filter", default="", help="comma list of cyclization_type to keep (train mode); empty=all")
    ap.add_argument("--limit", type=int, default=0, help="cap # entries (for local smoke test); 0=all")
    args = ap.parse_args()

    pdbs_dir = os.path.join(args.out_dir, "pdbs")
    os.makedirs(pdbs_dir, exist_ok=True)
    index_path = os.path.join(args.out_dir, "index.txt")
    rows = []  # (pdb_id, rec_chain, pep_chain)

    if args.mode == "train":
        held = load_test_ids(args.test_index)
        type_keep = set(t for t in args.type_filter.split(",") if t)
        recs = [json.loads(l) for l in open(args.manifest)]
        cand = []
        for r in recs:
            if r.get("status") != "ok":
                continue
            sl = r.get("seq_len") or 0
            if not (args.min_len <= sl <= args.max_len):
                continue
            if r["pdb_id"].upper() in held:
                continue
            if type_keep and r.get("cyclization_type") not in type_keep:
                continue
            cand.append(r)
        if args.limit:
            cand = cand[: args.limit]
        print(f"[train] candidates after filter/holdout: {len(cand)} (held-out ids={len(held)})")
        for r in cand:
            pid = r["pdb_id"]
            dest = os.path.join(pdbs_dir, pid + ".pdb")
            if not fetch_pdb(pid, dest):
                print(f"  WARN fetch failed {pid}")
                continue
            rc = best_rec_chain(dest, r.get("rec_chains", []), r["pep_chain"])
            if not rc:
                print(f"  WARN no rec chain {pid}")
                continue
            rows.append((pid, rc, r["pep_chain"]))
    else:  # test: PepBDB-cyclic test_index -> fetch + index (rec=field7, pep=field8)
        for ln in open(args.test_index):
            p = ln.strip().split("\t")
            if len(p) < 9:
                continue
            pid = p[0].split("_")[0]
            rec_chain, pep_chain = p[7], p[8]
            if args.limit and len(rows) >= args.limit:
                break
            dest = os.path.join(pdbs_dir, pid + ".pdb")
            if not fetch_pdb(pid, dest):
                print(f"  WARN fetch failed {pid}")
                continue
            rows.append((pid, rec_chain, pep_chain))
        print(f"[test] eval complexes: {len(rows)}")

    # de-dup by pdb_id (pepbench keys on pdb_id)
    seen = set(); uniq = []
    for pid, rc, pc in rows:
        if pid in seen:
            continue
        seen.add(pid); uniq.append((pid, rc, pc))
    with open(index_path, "w") as f:
        for pid, rc, pc in uniq:
            f.write(f"{pid}\t{rc}\t{pc}\n")
    print(f"wrote {len(uniq)} entries -> {index_path}")
    print(f"pdbs -> {pdbs_dir}")

if __name__ == "__main__":
    main()
