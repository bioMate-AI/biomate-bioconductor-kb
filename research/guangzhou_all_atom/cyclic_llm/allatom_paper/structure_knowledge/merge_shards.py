"""Merge shard outputs: python merge_shards.py IN_DIR OUT_DIR  (IN_DIR has f*.jsonl features and m*.jsonl meta; dedupe by (pdb_id, pep_chain) / rcsb_id)."""
import glob
import json
import os
import sys

inp, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)


def merge(pattern, keyfn, dest):
    seen, n = set(), 0
    with open(dest, "w") as fo:
        for f in sorted(glob.glob(os.path.join(inp, pattern))):
            for l in open(f):
                try:
                    d = json.loads(l)
                except Exception:  # noqa: BLE001
                    continue
                k = keyfn(d)
                if k in seen:
                    continue
                seen.add(k)
                fo.write(l if l.endswith("\n") else l + "\n")
                n += 1
    return n


nf = merge("f*.jsonl", lambda d: (d.get("pdb_id"), d.get("pep_chain")), os.path.join(out, "features.jsonl"))
nm = merge("m*.jsonl", lambda d: d.get("rcsb_id"), os.path.join(out, "meta.jsonl"))
print(json.dumps({"features": nf, "meta": nm}))
