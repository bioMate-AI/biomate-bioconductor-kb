#!/usr/bin/env python3
"""
BioMate GLP Study Data Collector

Downloads publicly available nonclinical study data from three sources:

1. FDA Drugs@FDA Pharmacology Reviews (PharmR.pdf)
   - URL pattern: accessdata.fda.gov/drugsatfda_docs/nda/[YEAR]/[NDA]PharmR.pdf
   - Content: FDA reviewer summaries of Module 4 GLP studies
   - Quality: HIGH — pharmaceutical context, NOAEL tables, dose groups, species
   - Scale: ~3,000+ NDAs with pharmR documents

2. NTP (National Toxicology Program) Technical Reports
   - URL: ntp.niehs.nih.gov/results/dbsearch
   - Content: 2,000+ GLP carcinogenesis/toxicology bioassays, highly structured
   - Quality: HIGH — standardised format, always has NOAEL, species, dose groups
   - Scale: 2,000+ studies

3. EMA EPAR nonclinical study tables (already partially collected)
   - We have 375 EPARs. The nonclinical assessment section contains study tables.
   - Quality: MEDIUM — study tables are EPAR reviewer summaries, similar to FDA PharmR

Usage:
    python3 scripts/collect_glp_study_data.py --fda --max 200
    python3 scripts/collect_glp_study_data.py --ntp --max 50
    python3 scripts/collect_glp_study_data.py --epar-tables  # extract from cached EPARs
"""
from __future__ import annotations

import argparse
import json
import logging
import re
import time
import io
from pathlib import Path
from typing import Optional
import urllib.request
import urllib.error

log = logging.getLogger(__name__)
logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")

_HEADERS = {"User-Agent": "Mozilla/5.0 (compatible; BioMate regulatory data research)"}
_FDA_API = "https://api.fda.gov/drug/drugsfda.json"
_FDA_BASE = "https://www.accessdata.fda.gov/drugsatfda_docs/nda"


def _fetch(url: str, timeout: int = 20) -> bytes:
    req = urllib.request.Request(url, headers=_HEADERS)
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read()


def _head_size(url: str) -> int:
    try:
        req = urllib.request.Request(url, headers=_HEADERS, method="HEAD")
        with urllib.request.urlopen(req, timeout=8) as r:
            return int(r.headers.get("Content-Length", 0))
    except Exception:
        return 0


# ---------------------------------------------------------------------------
# Source 1: FDA Pharmacology/Toxicology Reviews
# ---------------------------------------------------------------------------

def discover_fda_pharmar_urls(max_apps: int = 500, prefer_recent: bool = True) -> list[dict]:
    """
    Query Drugs@FDA API to get NDA application numbers, then construct PharmR PDF URLs.
    Returns list of {app_num, toc_url, pharmar_url, year}.

    prefer_recent=True: sort results by year descending, prioritising 2020–2025 approvals.
    Recent approvals reflect current ICH guidelines: S7B(R1) 2024, M7(R2) 2023,
    S5(R3) 2022, S9 2020 — the exact guidelines our regulatory LLM is trained to cite.
    Older approvals (pre-2015) often use superseded guideline versions.
    """
    pharmar_urls = []
    skip = 0
    batch = 100

    while len(pharmar_urls) < max_apps:
        # Sort by submission date descending to get recent approvals first
        sort_clause = "&sort=submissions.submission_status_date:desc" if prefer_recent else ""
        url = f"{_FDA_API}?search=submissions.submission_type:NDA&limit={batch}&skip={skip}{sort_clause}"
        try:
            data = json.loads(_fetch(url, timeout=15))
        except Exception as e:
            log.warning("FDA API error at skip=%d: %s", skip, e)
            break

        results = data.get("results", [])
        if not results:
            break

        for app in results:
            app_num = app.get("application_number", "")
            if not app_num.startswith("NDA"):
                continue
            for sub in app.get("submissions", []):
                docs = sub.get("application_docs", [])
                for doc in docs:
                    doc_url = doc.get("url", "")
                    if "TOC.html" in doc_url:
                        # Derive year from URL
                        m = re.search(r"/nda/(\d{4})/", doc_url)
                        year = m.group(1) if m else "unknown"
                        pharmar_url = doc_url.replace("TOC.html", "PharmR.pdf")
                        pharmar_urls.append({
                            "app_num": app_num,
                            "year": year,
                            "toc_url": doc_url,
                            "pharmar_url": pharmar_url,
                        })
                        break  # one PharmR per submission

        skip += batch
        if len(results) < batch:
            break
        time.sleep(0.3)  # FDA API rate limit

    log.info("Discovered %d PharmR URL candidates", len(pharmar_urls))
    return pharmar_urls


def extract_study_tables_from_pharmar(pdf_bytes: bytes) -> list[dict]:
    """
    Extract nonclinical study parameters from an FDA PharmR PDF.
    Returns list of study records: {study_type, species, route, dose_groups, noael, duration, findings}.
    """
    try:
        import pdfplumber
    except ImportError:
        log.error("pdfplumber not installed")
        return []

    records = []
    with pdfplumber.open(io.BytesIO(pdf_bytes)) as pdf:
        full_text = "\n".join(page.extract_text() or "" for page in pdf.pages)

        # Strategy A: Extract from prose conclusion paragraphs (most reliable)
        # Every GLP study report has "The NOAEL was X mg/kg/day" in conclusion
        noael_pattern = re.compile(
            r"(?:NOAEL|no[- ]observed[- ]adverse[- ]effect[- ]level)[^\n]{0,200}?"
            r"(\d+(?:\.\d+)?)\s*(?:mg/kg(?:/day)?|µg/kg|g/kg|mmol/kg)",
            re.I,
        )
        species_pattern = re.compile(
            r"\b(rat|mouse|mice|dog|monkey|rabbit|hamster|guinea pig)\b", re.I
        )
        study_type_pattern = re.compile(
            r"\b(genotox|ames|micronucleus|chromosomal aberration|herg|"
            r"single.dose|repeat.dose|28.day|90.day|13.week|26.week|"
            r"carcinogen|reproductive|embryo.fetal|fertility)\b",
            re.I,
        )

        # Find NOAEL mentions with surrounding context
        for m in noael_pattern.finditer(full_text):
            start = max(0, m.start() - 500)
            end = min(len(full_text), m.end() + 200)
            context = full_text[start:end]

            species = species_pattern.search(context)
            study_type = study_type_pattern.search(context)

            records.append({
                "source": "prose",
                "noael_value": m.group(1),
                "noael_context": context[max(0, m.start()-start-200):m.end()-start+100].strip(),
                "species": species.group(1).lower() if species else "unknown",
                "study_type": study_type.group(1).lower() if study_type else "general toxicology",
            })

        # Strategy B: Extract structured tables
        for page in pdf.pages:
            tables = page.extract_tables()
            for table in tables:
                if not table or len(table) < 3:
                    continue
                headers = [str(c or "").lower() for c in (table[0] or [])]
                # Look for tables with dose/NOAEL/species columns
                if any(kw in " ".join(headers) for kw in ["noael", "dose", "species", "duration", "finding"]):
                    records.append({
                        "source": "table",
                        "headers": headers,
                        "rows": [
                            [str(c or "").replace("\n", " ") for c in row]
                            for row in table[1:6]  # first 5 data rows
                        ],
                    })

    return records


def collect_fda_pharmar(out_dir: Path, max_docs: int = 200, year_min: int = 2018) -> int:
    """Main FDA PharmR collection function."""
    out_dir.mkdir(parents=True, exist_ok=True)
    raw_dir = out_dir / "raw" / "fda_pharmar"
    raw_dir.mkdir(parents=True, exist_ok=True)

    # Discover URLs
    candidates = discover_fda_pharmar_urls(max_apps=max_docs * 3, prefer_recent=True)
    # Filter to year_min to get documents reflecting current guidelines
    candidates = [c for c in candidates if int(c.get("year", "0") or "0") >= year_min]
    log.info("After year filter (>=%d): %d candidates", year_min, len(candidates))

    records_all = []
    n_collected = 0

    for c in candidates:
        if n_collected >= max_docs:
            break

        app_num = c["app_num"]
        pharmar_url = c["pharmar_url"]
        cache_path = raw_dir / f"{app_num}_PharmR.pdf"

        # Download (or use cache)
        if cache_path.exists():
            pdf_bytes = cache_path.read_bytes()
            log.info("[%d/%d] Using cached: %s", n_collected + 1, max_docs, app_num)
        else:
            # Check if PharmR exists (HEAD request)
            size = _head_size(pharmar_url)
            if size == 0:
                continue  # No PharmR for this NDA

            try:
                pdf_bytes = _fetch(pharmar_url, timeout=30)
                cache_path.write_bytes(pdf_bytes)
                log.info("[%d/%d] Downloaded %s: %.1f MB", n_collected + 1, max_docs,
                         app_num, len(pdf_bytes) / 1024 / 1024)
                time.sleep(1)  # be polite
            except Exception as e:
                log.warning("Failed to download %s: %s", app_num, e)
                continue

        # Extract study records
        records = extract_study_tables_from_pharmar(pdf_bytes)
        for rec in records:
            rec["source_app"] = app_num
            rec["source_url"] = pharmar_url
            records_all.append(rec)

        n_collected += 1

        if n_collected % 10 == 0:
            log.info("Progress: %d/%d docs, %d study records extracted", n_collected, max_docs, len(records_all))

    # Save
    out_file = out_dir / "fda_pharmar_studies.jsonl"
    with open(out_file, "w") as f:
        for rec in records_all:
            f.write(json.dumps(rec, ensure_ascii=False) + "\n")
    log.info("Saved %d study records → %s", len(records_all), out_file)
    return len(records_all)


# ---------------------------------------------------------------------------
# Source 2: NTP Technical Reports
# ---------------------------------------------------------------------------

_NTP_SEARCH = "https://ntp.niehs.nih.gov/results/dbsearch/index.html"
_NTP_TR_BASE = "https://ntp.niehs.nih.gov/ntp/htdocs/lt_rpts"


def collect_ntp_reports(out_dir: Path, max_reports: int = 50) -> int:
    """
    Collect NTP Technical Reports. These are highly structured GLP carcinogenesis
    and toxicology studies with standardised NOAEL tables.

    NTP TR index: https://ntp.niehs.nih.gov/results/dbsearch/
    Direct TR PDFs: https://ntp.niehs.nih.gov/ntp/htdocs/lt_rpts/tr[NNN].pdf
    Report numbers go from ~50 to ~600.
    """
    out_dir.mkdir(parents=True, exist_ok=True)
    raw_dir = out_dir / "raw" / "ntp_reports"
    raw_dir.mkdir(parents=True, exist_ok=True)

    records_all = []
    n_collected = 0

    # NTP TR numbers — known range of technical reports
    # Recent reports (300-600) are PDF, well-structured
    for tr_num in range(600, 200, -1):
        if n_collected >= max_reports:
            break

        url = f"{_NTP_TR_BASE}/tr{tr_num:03d}.pdf"
        cache_path = raw_dir / f"ntp_tr{tr_num:03d}.pdf"

        if cache_path.exists():
            pdf_bytes = cache_path.read_bytes()
        else:
            size = _head_size(url)
            if size == 0:
                continue
            try:
                pdf_bytes = _fetch(url, timeout=30)
                cache_path.write_bytes(pdf_bytes)
                log.info("[NTP] Downloaded TR%d: %.1f MB", tr_num, len(pdf_bytes)/1024/1024)
                time.sleep(1)
            except Exception as e:
                log.debug("NTP TR%d not found: %s", tr_num, e)
                continue

        # Extract NOAEL and study parameters
        try:
            import pdfplumber
            with pdfplumber.open(io.BytesIO(pdf_bytes)) as pdf:
                # NTP reports have a standardised Summary table in first 20 pages
                for i, page in enumerate(pdf.pages[:30]):
                    text = page.extract_text() or ""
                    if "NOAEL" in text or "no-observed-adverse-effect" in text.lower():
                        records_all.append({
                            "source": "ntp_report",
                            "tr_number": tr_num,
                            "page": i + 1,
                            "text_excerpt": text[:1000],
                        })
                        break
        except Exception as e:
            log.warning("NTP TR%d extraction failed: %s", tr_num, e)

        n_collected += 1

    out_file = out_dir / "ntp_studies.jsonl"
    with open(out_file, "w") as f:
        for rec in records_all:
            f.write(json.dumps(rec, ensure_ascii=False) + "\n")
    log.info("Saved %d NTP records → %s", len(records_all), out_file)
    return len(records_all)


# ---------------------------------------------------------------------------
# Source 3: EMA EPAR nonclinical study tables (from cached PDFs)
# ---------------------------------------------------------------------------

def extract_epar_study_tables(epar_raw_dir: Path, out_dir: Path) -> int:
    """
    Extract nonclinical study summary tables from cached EPAR PDFs.
    The CHMP assessment report nonclinical section (typically pages 30-100)
    contains structured study tables with species, dose, duration, NOAEL.
    """
    try:
        import pdfplumber
    except ImportError:
        log.error("pdfplumber not installed")
        return 0

    out_dir.mkdir(parents=True, exist_ok=True)
    records_all = []

    pdf_files = list(epar_raw_dir.glob("*.pdf"))
    log.info("Processing %d cached EPAR PDFs for nonclinical study tables", len(pdf_files))

    for pdf_path in pdf_files:
        drug_name = pdf_path.stem
        try:
            with pdfplumber.open(pdf_path) as pdf:
                for i, page in enumerate(pdf.pages):
                    text = page.extract_text() or ""
                    tables = page.extract_tables()

                    # Look for study summary tables: must have 4+ rows and NOAEL/dose keywords
                    for t in tables:
                        if not t or len(t) < 4:
                            continue
                        flat = " ".join(str(c or "") for row in t for c in row).lower()
                        if any(kw in flat for kw in ["noael", "dose", "species", "duration",
                                                      "genotox", "ames", "carcinogen"]):
                            records_all.append({
                                "source": "epar_table",
                                "drug": drug_name,
                                "page": i + 1,
                                "headers": [str(c or "").replace("\n", " ") for c in (t[0] or [])],
                                "rows": [
                                    [str(c or "").replace("\n", " ") for c in row]
                                    for row in t[1:8]
                                ],
                            })
        except Exception as e:
            log.warning("Error processing %s: %s", drug_name, e)

    out_file = out_dir / "epar_study_tables.jsonl"
    with open(out_file, "w") as f:
        for rec in records_all:
            f.write(json.dumps(rec, ensure_ascii=False) + "\n")
    log.info("Saved %d EPAR study table records → %s", len(records_all), out_file)
    return len(records_all)


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser(description="Collect public GLP nonclinical study data")
    ap.add_argument("--fda", action="store_true", help="Collect FDA PharmR PDFs")
    ap.add_argument("--ntp", action="store_true", help="Collect NTP Technical Reports")
    ap.add_argument("--epar-tables", action="store_true",
                    help="Extract study tables from cached EPAR PDFs")
    ap.add_argument("--max", type=int, default=50,
                    help="Maximum documents to collect (default: 50)")
    ap.add_argument("--year-min", type=int, default=2018,
                    help="Only collect FDA PharmR from this year onwards (default: 2018). "
                         "2018+ reflects ICH S7B 2005 (hERG), S2(R1) 2012, S5(R3) 2022 etc. "
                         "2022+ reflects the newest guidelines (S7B(R1), M7(R2), S9 oncology).")
    ap.add_argument("--output", type=Path,
                    default=Path("data/glp_study_data"))
    ap.add_argument("--epar-cache", type=Path,
                    default=Path("data/regulatory_training/epar/raw/epar"))
    args = ap.parse_args()

    if args.fda:
        n = collect_fda_pharmar(args.output, max_docs=args.max, year_min=args.year_min)
        print(f"FDA PharmR: {n} study records collected")

    if args.ntp:
        n = collect_ntp_reports(args.output, max_reports=args.max)
        print(f"NTP: {n} study records collected")

    if args.epar_tables:
        n = extract_epar_study_tables(args.epar_cache, args.output)
        print(f"EPAR tables: {n} study table records extracted")


if __name__ == "__main__":
    main()
