#!/usr/bin/env python3
"""Merge per-patient radiomics outputs into one cohort table (union of columns; duplicate patients are an error)."""
import argparse, csv, json, sys


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--wide", nargs="+", required=True)
    ap.add_argument("--qc", nargs="+", required=True)
    ap.add_argument("--prov", nargs="+", required=True)
    ap.add_argument("--outdir", default=".")
    a = ap.parse_args(argv)
    rows, cols = [], ["patient_id"]
    for f in a.wide:
        with open(f, newline="") as fh:
            for r in csv.DictReader(fh):
                rows.append(r)
                for k in r:
                    if k not in cols:
                        cols.append(k)
    ids = [r["patient_id"] for r in rows]
    if len(set(ids)) != len(ids):
        sys.stderr.write("ERROR: duplicate patient_id across inputs\n"); return 1
    with open(a.outdir + "/features_wide_all.csv", "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=cols); w.writeheader()
        for r in rows:
            w.writerow({c: r.get(c, "") for c in cols})
    qc, prov = [], []
    for f in a.qc:
        qc.extend(json.load(open(f))["cases"])
    for f in a.prov:
        prov.extend(json.load(open(f))["cases"])
    json.dump({"cases": qc, "n_cases": len(qc)}, open(a.outdir + "/qc_all.json", "w"), indent=1)
    json.dump({"cases": prov}, open(a.outdir + "/provenance_all.json", "w"), indent=1)
    print("merged %d patients, %d feature columns" % (len(rows), len(cols) - 1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
