#!/usr/bin/env python3
"""Check that GEO accessions, PMIDs and DOIs cited in replayed replies actually exist.

Reads the output of replay_sessions.py and, for every GSE/GSM/GDS accession, PMID and DOI in a
reply, asks the authoritative registry: NCBI E-utilities (db=gds / db=pubmed) and Crossref.
Prints one line per scenario: cited / found / NOT FOUND (with the missing identifiers). Used
because users caught invented accessions in replies (e.g. a GSE id that does not exist).

Usage: scripts/routing_eval/verify_citations.py <replay_results.json>
"""
import json
import re
import sys
import time
import urllib.parse
import urllib.request

EUTILS = "https://eutils.ncbi.nlm.nih.gov/entrez/eutils"
UA = {"User-Agent": "BioMate-citation-check/1.0 (mailto:support@biomate.ai)"}


def _get(url, timeout=30):
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.status, r.read().decode(errors="replace")


def geo_exists(acc):
    q = urllib.parse.quote(f"{acc}[ACCN]")
    _, body = _get(f"{EUTILS}/esearch.fcgi?db=gds&term={q}&retmode=json")
    time.sleep(0.4)  # NCBI: <=3 requests/s without an API key
    return int(json.loads(body)["esearchresult"]["count"]) > 0


def pmids_exist(pmids):
    if not pmids:
        return {}
    _, body = _get(f"{EUTILS}/esummary.fcgi?db=pubmed&id={','.join(pmids)}&retmode=json")
    time.sleep(0.4)
    res = json.loads(body).get("result", {})
    return {p: (p in res and "error" not in res[p]) for p in pmids}


def doi_exists(doi):
    try:
        st, _ = _get(f"https://api.crossref.org/works/{urllib.parse.quote(doi)}")
        return st == 200
    except Exception:  # noqa: BLE001 — 404 raises; any failure = not verified
        return False


def main():
    results = json.load(open(sys.argv[1]))
    for sc in results:
        text = "\n".join(t["reply"] for t in sc["turns"])
        geo = sorted(set(re.findall(r"\b(G(?:SE|SM|DS)\d{3,8})\b", text)))
        pmids = sorted(set(re.findall(r"PMID[:\s#]*?(\d{6,9})", text, re.I)))
        dois = sorted(set(d.rstrip(".,;)") for d in re.findall(r"\b(10\.\d{4,9}/[^\s\"<>\]]+)", text)))
        if not (geo or pmids or dois):
            continue
        missing = [a for a in geo if not geo_exists(a)]
        missing += [f"PMID:{p}" for p, ok in pmids_exist(pmids).items() if not ok]
        missing += [f"doi:{d}" for d in dois if not doi_exists(d)]
        n = len(geo) + len(pmids) + len(dois)
        print(f"{sc['id']:26s} cited={n} found={n - len(missing)} NOT FOUND={missing}")


if __name__ == "__main__":
    main()
