#!/usr/bin/env python3
"""
normalize_psms.py — convert an engine's native PSM output to the ONE benchmark schema.

This is the benchmark's engine-agnostic seam: every search engine's native format
(Comet pepXML, MS-GF+ mzIdentML, ...) is reduced to the same 5-column TSV the scorer
consumes, so score_proteomics_search_benchmark.py never parses engine formats.

Output schema (see scorer docstring):
    spectrum_id  peptide  protein  score  label
where `label` (target|entrapment|decoy) is looked up from db_map.tsv by protein
accession prefix (produced by prepare_search_db.py).

  ⚠️ INTEGRATION POINT — parsing is implemented with pyteomics but MUST be validated
     against real Comet/MS-GF+ output on the first Batch run (score sign, accession
     formatting, and decoy/entrapment prefix propagation differ subtly by engine
     version). Until then treat the parsed numbers as provisional. Per repo policy:
     do not trust this on real data until a real run confirms the column mapping.

Usage:
    python normalize_psms.py --engine comet --input x.comet.pep.xml --dbmap db_map.tsv --out x.psms.tsv
    python normalize_psms.py --engine msgf  --input x.msgf.mzid     --dbmap db_map.tsv --out x.psms.tsv
"""
from __future__ import annotations
import argparse
import csv
import sys


def load_dbmap(path):
    """accession -> label (target|entrapment|decoy)."""
    m = {}
    with open(path, newline="") as fh:
        rdr = csv.DictReader(fh, delimiter="\t")
        for r in rdr:
            m[r["accession"]] = r["label"]
    return m


def label_for(protein, dbmap):
    """Resolve label from accession, falling back to the prepare_search_db prefixes."""
    if protein in dbmap:
        return dbmap[protein]
    if protein.startswith("DECOY_"):
        return "decoy"
    if protein.startswith("ENT_"):
        return "entrapment"
    return "target"


def parse_comet_pepxml(path):
    """Yield (spectrum_id, peptide, protein, score). Comet XCorr; higher = better."""
    from pyteomics import pepxml
    for psm in pepxml.read(path):
        spec = psm.get("spectrum", "")
        for hit in psm.get("search_hit", []):
            pep = hit.get("peptide", "")
            prot = hit.get("proteins", [{}])[0].get("protein", "") if hit.get("proteins") else \
                   hit.get("protein", "")
            score = float(hit.get("search_score", {}).get("xcorr", 0.0))
            yield spec, pep, prot, score


def parse_msgf_mzid(path):
    """
    Yield (spectrum_id, peptide, protein, score). MS-GF+ reports MS-GF:SpecEValue —
    LOWER is better, so we emit -log10(SpecEValue) to make HIGHER = better (scorer
    contract). Handles the common mzIdentML layout via pyteomics.mzid.
    """
    import math
    from pyteomics import mzid
    with mzid.read(path) as reader:
        for spec in reader:
            sid = spec.get("spectrumID", spec.get("id", ""))
            for item in spec.get("SpectrumIdentificationItem", []):
                pep = item.get("PeptideSequence", item.get("peptide_ref", ""))
                prots = item.get("PeptideEvidenceRef", [])
                prot = ""
                if prots:
                    prot = prots[0].get("accession", prots[0].get("protein description", ""))
                sev = item.get("MS-GF:SpecEValue")
                score = -math.log10(sev) if sev and sev > 0 else 0.0
                yield sid, pep, prot, score


def parse_sage_tsv(path):
    """
    Yield (spectrum_id, peptide, protein, score). Sage's native results.sage.tsv is a
    plain TSV; the discriminant score (sage_discriminant_score) is HIGHER = better
    (already the scorer contract). Columns vary slightly by Sage version; we look up
    by name and fall back to hyperscore.
    """
    with open(path, newline="") as fh:
        rdr = csv.DictReader(fh, delimiter="\t")
        for r in rdr:
            sid = r.get("scannr") or r.get("psm_id") or r.get("spectrum_q") or ""
            pep = r.get("peptide", "")
            prot = (r.get("proteins") or r.get("protein") or "").split(";")[0]
            score_s = (r.get("sage_discriminant_score") or r.get("hyperscore")
                       or r.get("score") or "0")
            try:
                score = float(score_s)
            except ValueError:
                score = 0.0
            yield sid, pep, prot, score


def parse_mokapot_psms(path):
    """
    Yield (spectrum_id, peptide, protein, score, qvalue). Mokapot's *.mokapot.psms.txt
    gives a CALIBRATED 'mokapot q-value' (LOWER = better). We pass the q-value through
    as a 5th element so the scorer honors mokapot's own FDR (it is the correct rescored
    FDR) instead of recomputing target-decoy on rescored PSMs (mokapot drops decoys from
    the target output, so a recomputed TD pass would see no decoys). Score = 1 - q so
    HIGHER = better if any downstream ranking is still applied. Entrapment/decoy labels
    still come from the protein accession via db_map — the honesty check is unaffected.
    """
    with open(path, newline="") as fh:
        rdr = csv.DictReader(fh, delimiter="\t")
        for r in rdr:
            sid = r.get("PSMId") or r.get("SpecId") or r.get("psm_id") or ""
            pep = r.get("peptide") or r.get("Peptide") or ""
            prot = (r.get("Proteins") or r.get("proteins") or "").split("\t")[0].split(";")[0]
            q_s = r.get("mokapot q-value") or r.get("q-value") or "1.0"
            try:
                q = float(q_s)
            except ValueError:
                q = 1.0
            yield sid, pep, prot, 1.0 - q, q


PARSERS = {"comet": parse_comet_pepxml, "msgf": parse_msgf_mzid,
           "sage": parse_sage_tsv, "sage_mokapot": parse_mokapot_psms}


def normalize(engine, input_path, dbmap_path, out_path):
    dbmap = load_dbmap(dbmap_path)
    parser = PARSERS.get(engine)
    if parser is None:
        raise SystemExit(f"unknown engine {engine!r}; expected one of {list(PARSERS)}")
    n = 0
    emit_q = engine == "sage_mokapot"   # this engine carries its own calibrated q-value
    with open(out_path, "w", newline="") as out:
        w = csv.writer(out, delimiter="\t")
        header = ["spectrum_id", "peptide", "protein", "score", "label"]
        if emit_q:
            header.append("qvalue")
        w.writerow(header)
        for rec in parser(input_path):
            if emit_q:
                sid, pep, prot, score, q = rec
                w.writerow([sid, pep, prot, f"{score:.6f}", label_for(prot, dbmap), f"{q:.6g}"])
            else:
                sid, pep, prot, score = rec
                w.writerow([sid, pep, prot, f"{score:.6f}", label_for(prot, dbmap)])
            n += 1
    return n


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--engine", required=True, choices=list(PARSERS))
    ap.add_argument("--input", required=True)
    ap.add_argument("--dbmap", required=True)
    ap.add_argument("--out", required=True)
    args = ap.parse_args(argv)
    n = normalize(args.engine, args.input, args.dbmap, args.out)
    print(f"normalized {n} PSMs -> {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
