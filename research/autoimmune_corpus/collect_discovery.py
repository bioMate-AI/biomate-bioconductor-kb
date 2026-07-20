#!/usr/bin/env python3
"""Layer 1 — DISCOVERY (runs anywhere; stdlib + requests + yaml, no heavy deps).

Queries NCBI E-utilities (GEO `gds` DB) for human single-cell RNA-seq Series per
autoimmune disease, and writes a discovery manifest (accession, title, n_samples,
PMIDs, date). Feeds Layer 2 (acquisition) on the DGX Spark.

Usage:
    python3 collect_discovery.py [--manifest manifest.yaml] [--out results]
"""
import argparse, csv, json, os, sys, time, xml.etree.ElementTree as ET
import requests, yaml

EUTILS = "https://eutils.ncbi.nlm.nih.gov/entrez/eutils"
HERE = os.path.dirname(os.path.abspath(__file__))


def _get(url, params, retries=3, pause=0.4):
    params = {**params, "tool": "biomate_autoimmune_corpus"}
    for i in range(retries):
        try:
            r = requests.get(url, params=params, timeout=25)
            if r.status_code == 200:
                time.sleep(pause)  # be polite to NCBI (<3 req/s without api key)
                return r.text
        except requests.RequestException as e:
            sys.stderr.write(f"  retry {i+1}: {e}\n")
        time.sleep(1.5)
    return None


def esearch(term, cfg):
    p = {"db": cfg["eutils"]["db"], "term": term,
         "retmax": cfg["eutils"]["retmax_per_disease"], "retmode": "xml"}
    if cfg["eutils"].get("email") and cfg["eutils"]["email"] != "SET_ME":
        p["email"] = cfg["eutils"]["email"]
    if cfg["eutils"].get("api_key"):
        p["api_key"] = cfg["eutils"]["api_key"]
    txt = _get(f"{EUTILS}/esearch.fcgi", p)
    if not txt:
        return []
    root = ET.fromstring(txt)
    return [e.text for e in root.findall(".//IdList/Id")]


def esummary(uids, cfg):
    if not uids:
        return []
    p = {"db": cfg["eutils"]["db"], "id": ",".join(uids), "retmode": "xml"}
    if cfg["eutils"].get("api_key"):
        p["api_key"] = cfg["eutils"]["api_key"]
    txt = _get(f"{EUTILS}/esummary.fcgi", p)
    if not txt:
        return []
    root = ET.fromstring(txt)
    out = []
    for ds in root.findall(".//DocSum"):
        item = {}
        for it in ds.findall("Item"):
            name = it.get("Name")
            if name in ("Accession", "title", "summary", "taxon", "gdsType",
                        "entryType", "PDAT", "n_samples", "GSE", "suppFile"):
                item[name] = (it.text or "").strip()
            if name == "PubMedIds":
                item["PubMedIds"] = [x.text for x in it.findall("Item") if x.text]
        out.append(item)
    return out


def build_term(disease_terms, cfg):
    org = cfg["organism"]
    title_or = " OR ".join(f'"{t}"[Title]' for t in disease_terms)
    sc = "(single cell[All Fields] OR scRNA[All Fields] OR single-cell[All Fields])"
    return f'({title_or}) AND "{org}"[Organism] AND {sc} AND gse[Entry Type]'


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--manifest", default=os.path.join(HERE, "manifest.yaml"))
    ap.add_argument("--out", default=os.path.join(HERE, "results"))
    args = ap.parse_args()
    cfg = yaml.safe_load(open(args.manifest))
    os.makedirs(args.out, exist_ok=True)

    all_rows, summary = [], {}
    for disease, d in cfg["diseases"].items():
        term = build_term(d["eutils_terms"], cfg)
        sys.stderr.write(f"[{disease}] searching GEO gds…\n")
        uids = esearch(term, cfg)
        recs = esummary(uids, cfg)
        for r in recs:
            all_rows.append({
                "disease": disease,
                "accession": r.get("Accession", ""),
                "title": r.get("title", ""),
                "n_samples": r.get("n_samples", ""),
                "date": r.get("PDAT", ""),
                "pmids": ";".join(r.get("PubMedIds", []) or []),
                "has_supp": "yes" if r.get("suppFile") else "",
                "gdsType": r.get("gdsType", ""),
            })
        summary[disease] = {"n_series": len(recs),
                            "cores": [c["accession"] for c in d.get("cores", [])]}
        sys.stderr.write(f"    {len(recs)} series\n")

    # write outputs
    jpath = os.path.join(args.out, "discovery_manifest.json")
    cpath = os.path.join(args.out, "discovery_manifest.csv")
    json.dump({"summary": summary, "series": all_rows}, open(jpath, "w"), indent=2)
    if all_rows:
        with open(cpath, "w", newline="") as f:
            w = csv.DictWriter(f, fieldnames=list(all_rows[0].keys()))
            w.writeheader(); w.writerows(all_rows)
    print(json.dumps(summary, indent=2))
    print(f"\nWrote {len(all_rows)} series -> {jpath}\n              -> {cpath}")


if __name__ == "__main__":
    main()
