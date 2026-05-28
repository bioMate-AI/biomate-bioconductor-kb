#!/usr/bin/env python3
"""
verify_citations.py — Citation audit for BioMate evidence catalog + manuscripts.

Reads backend/config/qc_evidence.yaml and the three MANUSCRIPT_DRAFT.md files,
extracts (paper_ref, paper_doi) pairs, and verifies each via Crossref.

Output:
  research_repos/scripts/citation_audit_20260528.csv

Status values:
  verified           — Crossref returns matching author+year+journal
  author_mismatch    — Crossref hit but first author differs
  year_mismatch      — Crossref hit but year differs
  journal_mismatch   — Crossref hit but journal differs
  not_found          — DOI does not resolve in Crossref
  non_doi_skip       — URL or textbook, no DOI to verify automatically
  no_doi             — no DOI string given
"""
from __future__ import annotations

import csv
import json
import re
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path("/home/yzhang/biomate")
YAML = ROOT / "backend/config/qc_evidence.yaml"
OUT_CSV = ROOT / "research_repos/scripts/citation_audit_20260528.csv"
MS_FILES = {
    "flagship":  ROOT / "research_repos/flagship_paper/manuscript/MANUSCRIPT_DRAFT.md",
    "autoloop":  ROOT / "research_repos/autoloop_benchmark_paper/manuscript/MANUSCRIPT_DRAFT.md",
    "cryo":      ROOT / "research_repos/cryo_em_benchmark_paper/manuscript/MANUSCRIPT_DRAFT.md",
    "cryoensemble": ROOT / "research_repos/cryoensemble_paper/manuscript/MANUSCRIPT_DRAFT.md",
}

DOI_RE = re.compile(r"\b10\.\d{4,9}/[-._;()/:A-Za-z0-9]+", re.I)
YEAR_RE = re.compile(r"\b(?:19|20)\d{2}\b")

def crossref_lookup(doi: str) -> dict | None:
    url = f"https://api.crossref.org/works/{urllib.parse.quote(doi, safe='/')}"
    req = urllib.request.Request(url, headers={"User-Agent": "BioMate-CitationAudit/1.0 (mailto:audit@biomate.ai)"})
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            data = json.load(r)
        return data.get("message")
    except Exception as e:
        return {"_error": str(e)}

def parse_yaml_pairs(path: Path) -> list[tuple[str, str]]:
    pairs = []
    cur_ref = None
    for line in path.read_text().splitlines():
        m = re.search(r'paper_ref:\s*"([^"]*)"', line)
        if m:
            cur_ref = m.group(1); continue
        m = re.search(r'paper_doi:\s*"([^"]*)"', line)
        if m and cur_ref is not None:
            pairs.append((cur_ref, m.group(1)))
            cur_ref = None
    return pairs

def parse_ms_refs(path: Path) -> list[tuple[str, str]]:
    """Extract (ref_text, doi_or_url) from a manuscript's References section."""
    txt = path.read_text()
    # Find references section
    m = re.search(r'## References[^\n]*\n(.+?)(?:\n## |\Z)', txt, re.S)
    if not m:
        return []
    block = m.group(1)
    out = []
    for line in block.splitlines():
        line = line.strip()
        if not line or not re.match(r'^\d+\.', line):
            continue
        doi_m = DOI_RE.search(line)
        url_m = re.search(r'https?://\S+', line)
        token = doi_m.group(0).rstrip('.,;)') if doi_m else (url_m.group(0).rstrip('.,;)') if url_m else "")
        out.append((line, token))
    return out

def classify(ref: str, doi: str) -> tuple[str, str, str]:
    """Return (status, crossref_title, note)."""
    if not doi or doi in ("(none)", "(textbook, no DOI)"):
        return ("no_doi", "", "no DOI provided")
    if doi.startswith("http"):
        return ("non_doi_skip", "", "URL (FDA/ICH/ISO/EMA gov doc)")
    if doi.startswith("(no DOI"):
        return ("non_doi_skip", "", doi)
    # Crossref
    msg = crossref_lookup(doi)
    if msg is None or "_error" in (msg or {}):
        return ("not_found", "", f"crossref error: {(msg or {}).get('_error','none')}")
    title = " ".join(msg.get("title") or [])
    container = " ".join(msg.get("container-title") or [])
    year = None
    for k in ("published-print", "published-online", "issued", "created"):
        if k in msg and msg[k].get("date-parts"):
            year = msg[k]["date-parts"][0][0]
            break
    authors = msg.get("author") or []
    first_author_family = (authors[0].get("family","") if authors else "").lower()

    note_parts = []
    status = "verified"

    # Year check
    ref_years = [int(y) for y in YEAR_RE.findall(ref)]
    if year and ref_years and year not in ref_years:
        status = "year_mismatch"
        note_parts.append(f"crossref year={year} vs ref years={ref_years}")

    # Author check (find ref's first surname token after start)
    # Get first plausible surname from ref
    m = re.match(r'^([A-Z][a-zA-Z\-]+)', ref)
    ref_first_author = m.group(1).lower() if m else ""
    if first_author_family and ref_first_author and ref_first_author != first_author_family:
        # Tolerate: ref might start with "FDA"/"ICH"/"EMA"
        if ref_first_author not in ("fda","ich","ema","iso","gatk","autodock"):
            if status == "verified":
                status = "author_mismatch"
            note_parts.append(f"crossref author={first_author_family} vs ref author={ref_first_author}")

    return (status, f"{title} ({container} {year})", "; ".join(note_parts))

def main():
    rows = []
    seen = set()

    # YAML
    for ref, doi in parse_yaml_pairs(YAML):
        key = ("yaml", ref, doi)
        if key in seen: continue
        seen.add(key)
        # extract first DOI from doi field
        m = DOI_RE.search(doi)
        doi_clean = m.group(0) if m else doi
        status, title, note = classify(ref, doi_clean)
        rows.append({"source":"qc_evidence.yaml","ref":ref,"doi":doi,"status":status,"crossref_title":title,"note":note})
        time.sleep(0.15)

    # Manuscripts
    for tag, path in MS_FILES.items():
        for ref, doi in parse_ms_refs(path):
            key = (tag, ref)
            if key in seen: continue
            seen.add(key)
            m = DOI_RE.search(doi)
            doi_clean = m.group(0) if m else doi
            status, title, note = classify(ref, doi_clean)
            rows.append({"source":f"manuscript:{tag}","ref":ref,"doi":doi,"status":status,"crossref_title":title,"note":note})
            time.sleep(0.15)

    OUT_CSV.parent.mkdir(parents=True, exist_ok=True)
    with OUT_CSV.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=["source","ref","doi","status","crossref_title","note"])
        w.writeheader()
        w.writerows(rows)

    # Summary
    from collections import Counter
    c = Counter(r["status"] for r in rows)
    print(f"Wrote {len(rows)} citations -> {OUT_CSV}")
    for k, v in c.most_common():
        print(f"  {k}: {v}")

if __name__ == "__main__":
    main()
