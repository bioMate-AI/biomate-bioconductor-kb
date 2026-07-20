#!/usr/bin/env python3
"""Cyclic-peptide dataset collection — CycPeptMPDB (membrane permeability, the
field-standard macrocycle DB). Downloads the full peptide table for the
permeability model + baseline gate. ChEMBL macrocycle subset is a later add.

Usage: python3 collect_cycpeptides.py --out data/cycpep
"""
import argparse, os, sys
import pandas as pd, requests

CYCPEPT_URL = "http://cycpeptmpdb.com/static//download/peptides/CycPeptMPDB_Peptide_All.csv"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="data/cycpep")
    ap.add_argument("--url", default=CYCPEPT_URL)
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)

    raw = os.path.join(args.out, "CycPeptMPDB_Peptide_All.csv")
    sys.stderr.write(f"downloading {args.url}\n")
    with requests.get(args.url, stream=True, timeout=120) as r:
        r.raise_for_status()
        with open(raw, "wb") as f:
            for c in r.iter_content(1 << 20):
                f.write(c)
    sys.stderr.write(f"  {os.path.getsize(raw)/1e6:.1f} MB\n")

    df = pd.read_csv(raw, low_memory=False)
    # identify SMILES + permeability columns
    smi = next((c for c in df.columns if "smiles" in c.lower()), None)
    perm = next((c for c in df.columns if "permeab" in c.lower()), None) \
        or next((c for c in df.columns if "papp" in c.lower() or "logp_app" in c.lower()), None)
    report = {"n_rows": len(df), "n_cols": len(df.columns),
              "smiles_col": smi, "permeability_col": perm,
              "columns_sample": list(df.columns)[:40]}
    import json
    json.dump(report, open(os.path.join(args.out, "cycpep_source_report.json"), "w"), indent=2)
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
