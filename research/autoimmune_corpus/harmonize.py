#!/usr/bin/env python3
"""Layer 3 — HARMONIZE + LABEL (runs on EC2/Spark; needs scanpy/anndata).

Concatenates per-disease h5ad shards into one curated corpus, applies basic QC,
does a PATIENT-LEVEL train/val/test split (no donor leakage), and emits a
clinical-label review queue (donors whose SLEDAI/anti-dsDNA/complement must be
extracted-then-verified from linked papers).

Usage:
    python3 harmonize.py --raw data/raw --out data/curated --manifest manifest.yaml
"""
import argparse, json, os, sys, glob
import numpy as np
import pandas as pd

HERE = os.path.dirname(os.path.abspath(__file__))


def patient_split(donors, seed=0, frac=(0.70, 0.15, 0.15)):
    rng = np.random.default_rng(seed)
    d = np.array(sorted(set(donors)))
    rng.shuffle(d)
    n = len(d)
    n_tr = int(n * frac[0]); n_va = int(n * frac[1])
    return ({x: "train" for x in d[:n_tr]}
            | {x: "val" for x in d[n_tr:n_tr + n_va]}
            | {x: "test" for x in d[n_tr + n_va:]})


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--raw", default=os.path.join(HERE, "data", "raw"))
    ap.add_argument("--out", default=os.path.join(HERE, "data", "curated"))
    ap.add_argument("--manifest", default=os.path.join(HERE, "manifest.yaml"))
    ap.add_argument("--min-genes", type=int, default=200)
    args = ap.parse_args()

    import anndata as ad
    import scanpy as sc
    import yaml
    cfg = yaml.safe_load(open(args.manifest))
    os.makedirs(args.out, exist_ok=True)

    shards = sorted(glob.glob(os.path.join(args.raw, "*.h5ad")))
    if not shards:
        sys.stderr.write("no shards in %s\n" % args.raw); sys.exit(1)
    parts = []
    for s in shards:
        a = ad.read_h5ad(s)
        sys.stderr.write(f"  loaded {os.path.basename(s)}: {a.n_obs}x{a.n_vars}\n")
        parts.append(a)
    adata = ad.concat(parts, join="outer", label="shard",
                      keys=[os.path.basename(s)[:-5] for s in shards], fill_value=0)

    # basic QC
    sc.pp.filter_cells(adata, min_genes=args.min_genes)
    sc.pp.filter_genes(adata, min_cells=10)

    # provisional disease_activity (refined later by verified clinical labels)
    dg = adata.obs["disease_group"].astype(str)
    adata.obs["disease_activity"] = np.where(dg.str.contains("normal", case=False),
                                             "healthy", "disease_unlabeled")

    # patient-level split
    donor = adata.obs["donor_id"].astype(str)
    split_map = patient_split(donor.tolist())
    adata.obs["split"] = donor.map(split_map).fillna("train")

    # write curated corpus
    corpus_path = os.path.join(args.out, "autoimmune_sc_corpus.h5ad")
    adata.write_h5ad(corpus_path)

    # splits + summary
    splits = {k: donor[adata.obs["split"] == k].unique().tolist()
              for k in ("train", "val", "test")}
    json.dump({"n_cells": int(adata.n_obs), "n_genes": int(adata.n_vars),
               "by_disease": adata.obs["disease_group"].value_counts().to_dict(),
               "n_donors": int(donor.nunique()),
               "splits_donor_counts": {k: len(v) for k, v in splits.items()}},
              open(os.path.join(args.out, "summary.json"), "w"), indent=2)
    json.dump(splits, open(os.path.join(args.out, "splits.json"), "w"), indent=2)

    # clinical-label review queue: one row per donor to be extracted-then-verified
    targets = cfg.get("clinical_labels", [])
    q = (adata.obs[["donor_id", "disease_group", "dataset_id"]]
         .drop_duplicates("donor_id").reset_index(drop=True))
    for t in targets:
        q[t] = ""
    q["verified"] = False
    q.to_csv(os.path.join(args.out, "clinical_labels_queue.csv"), index=False)

    print(f"curated {adata.n_obs} cells x {adata.n_vars} genes, "
          f"{donor.nunique()} donors -> {corpus_path}")
    print(f"label review queue: {len(q)} donors")


if __name__ == "__main__":
    main()
