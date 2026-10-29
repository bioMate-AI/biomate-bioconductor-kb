"""Driver (runs on EC2): manifest -> RCSB metadata -> CIF download -> per-complex features -> JSONL. Resumable.

usage: python run_library.py --manifest MANIFEST.jsonl --out OUTDIR [--limit N] [--workers 8]
Outputs in OUTDIR: meta.jsonl (RCSB metadata per entry), features.jsonl (one row per manifest row), run_summary.json.
Each feature row carries: manifest fields (pdb_id, pep_chain, rec_chains, manifest cyclization label/evidence), our own
re-detected cyclisation, and `agree_cyclisation` (manifest label vs re-detection) so label errors are visible."""
from __future__ import annotations

import argparse
import json
import os
import sys
import time
import urllib.request
from concurrent.futures import ProcessPoolExecutor

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import features as F  # noqa: E402
import rcsb_meta as M  # noqa: E402

KEEP_CIF = os.environ.get("K3_KEEP_CIF", "0") == "1"
MAX_CIF_BYTES = int(os.environ.get("K3_MAX_CIF_BYTES", str(12_000_000)))   # skip giant assemblies (ribosomes etc.): not short-peptide ligand complexes and they exhaust memory
MANIFEST_TYPE_TO_KINDS = {"disulfide": {"disulfide"}, "head_to_tail": {"head_to_tail"},
                          "sidechain_backbone": {"amide_like", "thioether", "ester_like", "c_c_link"}}


def download(pdb_id: str, cache: str) -> str:
    p = os.path.join(cache, pdb_id.lower() + ".cif")
    if os.path.exists(p) and os.path.getsize(p) > 1000:
        return p
    last = None
    for k in range(3):
        try:
            data = urllib.request.urlopen(f"https://files.rcsb.org/download/{pdb_id.lower()}.cif", timeout=60).read()
            open(p, "wb").write(data)
            return p
        except Exception as e:  # noqa: BLE001
            last = e
            time.sleep(2 * (k + 1))
    raise RuntimeError(f"download failed {pdb_id}: {last}")


def one(row: dict, cache: str) -> dict:
    t0 = time.time()
    base = {k: row.get(k) for k in ("pdb_id", "pep_chain", "rec_chains", "peptide_seq", "seq_len", "cyclization_type",
                                    "cyclization_evidence", "resolution", "method", "receptor_name", "conformer_provenance")}
    try:
        path = download(row["pdb_id"], cache)
        if os.path.getsize(path) > MAX_CIF_BYTES:
            sz = os.path.getsize(path)
            os.remove(path)
            base.update({"ok": False, "error": f"cif too large ({sz} bytes > {MAX_CIF_BYTES}); giant assembly skipped"})
            return base
        f = F.featurize_complex(path, row["pep_chain"], list(row["rec_chains"]))
    except Exception as e:  # noqa: BLE001
        base.update({"ok": False, "error": f"{type(e).__name__}: {str(e)[:160]}"})
        return base
    base.update(f)
    for k in ("source", "biolip_uniprot", "biolip_pubmed", "biolip_affinity", "biolip_resolution"):
        if k in row:
            base[k] = row[k]
    if not KEEP_CIF:
        try:
            os.remove(path)
        except OSError:
            pass
    if f.get("ok") and row.get("cyclization_type"):
        want = MANIFEST_TYPE_TO_KINDS.get(row.get("cyclization_type"), set())
        base["agree_cyclisation"] = bool(want & set(f["closure_kinds"]))
    base["seconds"] = round(time.time() - t0, 2)
    return base


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--manifest", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--workers", type=int, default=8)
    ap.add_argument("--shard", default="0/1", help="k/n: process rows with index %% n == k (deterministic order of the manifest file)")
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    cache = os.path.join(a.out, "cif")
    os.makedirs(cache, exist_ok=True)
    rows = [json.loads(l) for l in open(a.manifest) if l.strip()]
    rows = [r for r in rows if r.get("status") == "ok"]
    if a.limit:
        rows = rows[: a.limit]
    sk, sn = (int(x) for x in a.shard.split("/"))
    rows = [r for i, r in enumerate(rows) if i % sn == sk]
    # metadata
    mp = os.path.join(a.out, "meta.jsonl")
    have = {json.loads(l)["rcsb_id"] for l in open(mp)} if os.path.exists(mp) else set()
    ids = sorted({r["pdb_id"].upper() for r in rows} - have)
    if ids:
        meta = M.fetch_all(ids)
        with open(mp, "a") as f:
            for k, v in meta.items():
                v["retrieved_utc"] = time.strftime("%FT%TZ", time.gmtime())
                f.write(json.dumps(v) + "\n")
    # features (resumable on (pdb_id, pep_chain))
    fp = os.path.join(a.out, "features.jsonl")
    done = set()
    if os.path.exists(fp):
        for l in open(fp):
            try:
                d = json.loads(l); done.add((d["pdb_id"], d["pep_chain"]))
            except Exception:  # noqa: BLE001
                pass
    todo = [r for r in rows if (r["pdb_id"], r["pep_chain"]) not in done]
    t0 = time.time()
    n_ok = n_fail = 0
    with ProcessPoolExecutor(a.workers) as ex, open(fp, "a") as f:
        for res in ex.map(one, todo, [cache] * len(todo), chunksize=8):
            f.write(json.dumps(res) + "\n"); f.flush()
            if res.get("ok"):
                n_ok += 1
            else:
                n_fail += 1
    summ = {"manifest": os.path.basename(a.manifest), "n_manifest_rows_ok": len(rows), "n_done_before": len(done), "n_new_ok": n_ok,
            "n_new_fail": n_fail, "seconds": round(time.time() - t0, 1), "utc": time.strftime("%FT%TZ", time.gmtime())}
    json.dump(summ, open(os.path.join(a.out, "run_summary.json"), "w"), indent=1)
    print(json.dumps(summ))


if __name__ == "__main__":
    main()
