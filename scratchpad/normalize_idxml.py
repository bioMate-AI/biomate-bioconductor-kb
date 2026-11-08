#!/usr/bin/env python3
"""
normalize_idxml.py — OpenMS idXML (CometAdapter output) -> benchmark PSM schema.
One row per PeptideHit: spectrum_id, peptide, protein, score, label.
Comet XCorr via OpenMS: higher = better (scorer contract). Label from db_map by
protein accession prefix (target|entrapment|decoy). Dependency-free (stdlib XML).
"""
import argparse, csv, sys
import xml.etree.ElementTree as ET


def load_dbmap(path):
    m = {}
    with open(path, newline="") as fh:
        for r in csv.DictReader(fh, delimiter="\t"):
            m[r["accession"]] = r["label"]
    return m


def label_for(protein, dbmap):
    if protein in dbmap:
        return dbmap[protein]
    if protein.startswith("DECOY_"):
        return "decoy"
    if protein.startswith("ENT_"):
        return "entrapment"
    return "target"


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--input", required=True)
    ap.add_argument("--dbmap", required=True)
    ap.add_argument("--out", required=True)
    a = ap.parse_args(argv)
    dbmap = load_dbmap(a.dbmap)

    # Map ProteinHit id -> accession
    tree = ET.parse(a.input)
    root = tree.getroot()
    prot_acc = {}
    for ph in root.iter("ProteinHit"):
        prot_acc[ph.get("id")] = ph.get("accession", "")

    n = 0
    with open(a.out, "w", newline="") as out:
        w = csv.writer(out, delimiter="\t")
        w.writerow(["spectrum_id", "peptide", "protein", "score", "label"])
        for pid in root.iter("PeptideIdentification"):
            sid = pid.get("spectrum_reference") or pid.get("identifier") or ""
            for hit in pid.findall("PeptideHit"):
                seq = hit.get("sequence", "")
                score = hit.get("score", "0")
                refs = (hit.get("protein_refs") or "").split()
                accs = [prot_acc.get(r, "") for r in refs if prot_acc.get(r)]
                prot = accs[0] if accs else ""
                # If ANY protein is a real target, label target; else use first.
                lbls = [label_for(x, dbmap) for x in accs] or ["target"]
                # prefer target > entrapment > decoy for a razor-shared peptide
                lbl = ("target" if "target" in lbls else
                       "entrapment" if "entrapment" in lbls else "decoy")
                try:
                    sc = float(score)
                except ValueError:
                    sc = 0.0
                w.writerow([sid, seq, prot, f"{sc:.6f}", lbl])
                n += 1
    print(f"normalized {n} PSMs -> {a.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
