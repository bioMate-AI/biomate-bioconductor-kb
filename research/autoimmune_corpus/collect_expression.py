#!/usr/bin/env python3
"""Layer 2 — ACQUISITION (runs on EC2/Spark; needs cellxgene_census, scanpy, anndata).

Pulls disease-filtered human immune single-cell data from the CELLxGENE Census
into per-disease h5ad shards, with a per-disease cell cap to bound memory.

Usage:
    python3 collect_expression.py --manifest manifest.yaml --out data/raw \
        --diseases SLE --cap 500000 --census-version stable
"""
import argparse, os, sys, yaml
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
OBS_COLS = ["soma_joinid", "donor_id", "cell_type", "tissue", "assay",
            "disease", "sex", "development_stage", "dataset_id"]


def fetch_disease(census, cx, labels, group_name, cap, seed=0):
    """Return an AnnData of up to `cap` primary human cells for `labels`
    (one or more CELLxGENE `disease` ontology labels), tagged `group_name`."""
    if isinstance(labels, str):
        labels = [labels]
    human = census["census_data"]["homo_sapiens"]
    quoted = ", ".join(f"'{l}'" for l in labels)
    filt = (f"disease in [{quoted}] and is_primary_data == True")
    obs = human.obs.read(value_filter=filt, column_names=OBS_COLS).concat().to_pandas()
    n = len(obs)
    if n == 0:
        sys.stderr.write(f"    [{group_name}] 0 cells matched — skip\n")
        return None
    if n > cap:
        # global subsample under the cap (donor diversity preserved in expectation).
        # NB: CELLxGENE returns categorical columns; avoid groupby(observed=False)
        # which would create empty donor groups and break .sample().
        obs = obs.sample(n=cap, random_state=seed)
    ids = obs["soma_joinid"].to_numpy()
    sys.stderr.write(f"    [{group_name}] {n} cells matched -> fetching {len(ids)} (cap {cap})\n")
    adata = cx.get_anndata(census, organism="Homo sapiens",
                           obs_coords=ids,
                           column_names={"obs": OBS_COLS})
    adata.obs["disease_group"] = group_name
    return adata


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--manifest", default=os.path.join(HERE, "manifest.yaml"))
    ap.add_argument("--out", default=os.path.join(HERE, "data", "raw"))
    ap.add_argument("--diseases", default="SLE",
                    help="comma-separated keys from manifest, or ALL")
    ap.add_argument("--cap", type=int, default=500_000, help="max cells per disease")
    ap.add_argument("--census-version", default="stable")
    args = ap.parse_args()

    import cellxgene_census as cx
    cfg = yaml.safe_load(open(args.manifest))
    os.makedirs(args.out, exist_ok=True)
    want = (list(cfg["diseases"]) if args.diseases.upper() == "ALL"
            else [d.strip() for d in args.diseases.split(",")])

    with cx.open_soma(census_version=args.census_version) as census:
        for key in want:
            d = cfg["diseases"].get(key)
            if not d or not d.get("census_disease_label"):
                sys.stderr.write(f"  [{key}] no census_disease_label — skip\n"); continue
            labels = d["census_disease_label"]
            sys.stderr.write(f"[{key}] Census disease={labels}\n")
            try:
                adata = fetch_disease(census, cx, labels, key, args.cap)
            except Exception as e:
                sys.stderr.write(f"  [{key}] ERROR: {e}\n"); continue
            if adata is None:
                continue
            path = os.path.join(args.out, f"{key}.h5ad")
            adata.write_h5ad(path)
            print(f"  wrote {adata.n_obs} cells x {adata.n_vars} genes -> {path}")


if __name__ == "__main__":
    main()
