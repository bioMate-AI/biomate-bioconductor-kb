#!/usr/bin/env python3
"""SLEDAI extraction step — pull the ORIGINAL Perez 2022 SLE h5ad obs (full custom
columns, which the Census standardized schema drops) and look for a per-donor
disease-activity / SLEDAI / status field. Reads obs only (backed mode) to stay
memory-light. Output feeds `disease_activity` labels for the activity evaluation.

Usage: python3 inspect_perez_labels.py --sources results/census_source_datasets.json --out out/
"""
import argparse, json, os, re, sys
import requests

API = "https://api.cellxgene.cziscience.com/curation/v1"
KEYS = re.compile(r"sled|activ|status|severit|flare|class|condition|disease|state|group|treat", re.I)


def h5ad_url(collection_id, dataset_id):
    d = requests.get(f"{API}/collections/{collection_id}/datasets/{dataset_id}", timeout=60).json()
    for a in (d.get("assets") or []):
        if a.get("filetype") == "H5AD":
            return a.get("url")
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sources", default="results/census_source_datasets.json")
    ap.add_argument("--out", default="out")
    ap.add_argument("--group", default="SLE")
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)
    import anndata as ad

    rows = json.load(open(args.sources))
    row = next((r for r in rows if r.get("group") == args.group), None)
    if not row:
        sys.stderr.write(f"no {args.group} source dataset found\n"); return
    did, cid = row["dataset_id"], row["collection_id"]
    url = h5ad_url(cid, did)
    sys.stderr.write(f"[{args.group}] dataset {did}\n  h5ad: {url}\n")
    if not url:
        sys.stderr.write("  no H5AD asset url\n"); return

    local = os.path.join(args.out, f"{args.group}_source.h5ad")
    with requests.get(url, stream=True, timeout=120) as r:
        r.raise_for_status()
        with open(local, "wb") as f:
            for chunk in r.iter_content(chunk_size=1 << 24):
                f.write(chunk)
    sys.stderr.write(f"  downloaded {os.path.getsize(local)/1e9:.2f} GB\n")

    adata = ad.read_h5ad(local, backed="r")
    obs = adata.obs
    schema = {"dataset_id": did, "doi": row.get("doi"), "n_cells": int(adata.n_obs),
              "obs_columns": list(obs.columns)}
    # candidate activity columns
    cand = [c for c in obs.columns if KEYS.search(str(c))]
    schema["candidate_activity_columns"] = {}
    for c in cand:
        try:
            vc = obs[c].astype(str).value_counts().head(20)
            schema["candidate_activity_columns"][c] = vc.to_dict()
        except Exception:
            pass
    # donor id column guess
    donor_col = next((c for c in obs.columns
                      if re.search(r"donor|patient|subject|individual", str(c), re.I)), None)
    schema["donor_column"] = donor_col
    json.dump(schema, open(os.path.join(args.out, f"{args.group}_obs_schema.json"), "w"), indent=2)

    # per-donor activity table (donor x candidate cols, first value per donor)
    if donor_col and cand:
        import pandas as pd
        t = obs[[donor_col] + cand].astype(str).drop_duplicates(donor_col)
        t.to_csv(os.path.join(args.out, f"{args.group}_donor_activity.csv"), index=False)
        print(f"donor activity table: {len(t)} donors x {len(cand)} candidate cols")
    print(json.dumps({"obs_columns": schema["obs_columns"],
                      "candidate_activity_columns": list(schema["candidate_activity_columns"])},
                     indent=2))


if __name__ == "__main__":
    main()
