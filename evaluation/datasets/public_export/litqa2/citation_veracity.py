#!/usr/bin/env python3
"""Citation-veracity scorer — the confabulation axis for retrieval-agent evaluation.

A literature agent can produce a rigorous-LOOKING answer whose citations are INVENTED
(real-format PMIDs/DOIs that resolve to unrelated papers, or that don't resolve at all).
Accuracy alone does not catch this — an answer can be "right" while its evidence is fake.
This module resolves every identifier a system emits against NCBI (PMID) and Crossref
(DOI) and flags three failure modes:

  - unresolvable : the identifier does not exist (fabricated number)
  - mismatched   : the identifier EXISTS but its real title does not match the claimed
                   title (fabricated attribution — the PEX failure mode: PMID 20418857
                   claimed as "Meinecke 2010 PEX14 channel", actually a mouse-auditory paper)
  - ok           : resolves AND the real title matches the claimed title

confabulation_rate = (unresolvable + mismatched) / total_identifiers.

Reusable: import `score_citations(claimed)` for a list of {title,pmid,doi}, or run as a
CLI over a predictions.jsonl whose rows carry a `citations` list.
"""
import json
import re
import sys
import time
import urllib.parse
import urllib.request

NCBI = "https://eutils.ncbi.nlm.nih.gov/entrez/eutils"
CROSSREF = "https://api.crossref.org/works"


def _get(url, timeout=15):
    req = urllib.request.Request(url, headers={"User-Agent": "biomate-veracity/1.0 (mailto:eval@biomate.ai)"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode("utf-8", "ignore"))


def _norm(s):
    return re.sub(r"[^a-z0-9]+", " ", (s or "").lower()).strip()


def _title_matches(claimed, real):
    """True if the claimed title matches the resolved record's real title. Token-overlap
    (>=0.8 of claimed tokens present) OR strong sequence ratio — tolerant of truncation/
    punctuation, strict enough that a wholly different paper (mismatch) is caught."""
    import difflib
    a, b = _norm(claimed), _norm(real)
    if not a or not b:
        return False
    toks = set(a.split())
    overlap = len(toks & set(b.split())) / len(toks) if toks else 0.0
    ratio = difflib.SequenceMatcher(None, a, b).ratio()
    return overlap >= 0.8 or ratio >= 0.8


def resolve_pmid(pmid):
    try:
        rec = _get(f"{NCBI}/esummary.fcgi?db=pubmed&retmode=json&id={pmid}").get("result", {}).get(str(pmid), {})
        if rec and not rec.get("error") and rec.get("title"):
            return {"found": True, "title": rec.get("title", "")}
    except Exception:
        pass
    return {"found": False, "title": ""}


def resolve_doi(doi):
    try:
        rec = _get(f"{CROSSREF}/{urllib.parse.quote(doi)}").get("message", {})
        if rec:
            t = (rec.get("title") or [""])
            return {"found": True, "title": t[0] if t else ""}
    except Exception:
        pass
    return {"found": False, "title": ""}


def verify_citation(cit, throttle=0.34):
    """cit: {title, pmid?, doi?}. Returns a verdict dict. Prefers PMID (NCBI), then DOI
    (Crossref). A citation with NO identifier is 'unidentified' (not counted as fabricated —
    not every real paper has a PMID/DOI, e.g. preprints)."""
    title = cit.get("title") or ""
    pmid, doi = cit.get("pmid"), cit.get("doi")
    result = {"title": title, "pmid": pmid, "doi": doi, "verdict": "unidentified", "real_title": ""}
    resolved = None
    if pmid:
        resolved = resolve_pmid(pmid)
    if (not resolved or not resolved["found"]) and doi:
        resolved = resolve_doi(doi)
    time.sleep(throttle)
    if resolved is None:
        return result  # no identifier to check
    if not resolved["found"]:
        result["verdict"] = "unresolvable"          # fabricated number
        return result
    result["real_title"] = resolved["title"]
    result["verdict"] = "ok" if _title_matches(title, resolved["title"]) else "mismatched"
    return result


def score_citations(claimed):
    """claimed: list of {title, pmid?, doi?}. Returns aggregate + per-citation verdicts."""
    verdicts = [verify_citation(c) for c in claimed]
    ided = [v for v in verdicts if v["verdict"] != "unidentified"]
    bad = [v for v in ided if v["verdict"] in ("unresolvable", "mismatched")]
    n_id = len(ided)
    return {
        "n_citations": len(claimed),
        "n_identified": n_id,
        "n_ok": sum(1 for v in ided if v["verdict"] == "ok"),
        "n_unresolvable": sum(1 for v in ided if v["verdict"] == "unresolvable"),
        "n_mismatched": sum(1 for v in ided if v["verdict"] == "mismatched"),
        "n_unidentified": len(verdicts) - n_id,
        # the headline: fraction of IDENTIFIED citations that are fake (nonexistent or wrong paper)
        "confabulation_rate": round(len(bad) / n_id, 4) if n_id else 0.0,
        "verdicts": verdicts,
    }


def main():
    import argparse
    ap = argparse.ArgumentParser(description="Citation-veracity scorer over a predictions.jsonl")
    ap.add_argument("preds", help="jsonl with rows carrying a 'citations' list of {title,pmid,doi}")
    ap.add_argument("--limit", type=int, default=0)
    args = ap.parse_args()
    rows = [json.loads(l) for l in open(args.preds)]
    if args.limit:
        rows = rows[:args.limit]
    agg = {"n_citations": 0, "n_identified": 0, "n_ok": 0, "n_unresolvable": 0, "n_mismatched": 0, "n_unidentified": 0}
    for r in rows:
        s = score_citations(r.get("citations") or [])
        for k in agg:
            agg[k] += s[k]
        r["veracity"] = {k: s[k] for k in s if k != "verdicts"}
    ni = agg["n_identified"]
    agg["confabulation_rate"] = round((agg["n_unresolvable"] + agg["n_mismatched"]) / ni, 4) if ni else 0.0
    print(json.dumps(agg, indent=2))


if __name__ == "__main__":
    main()
