#!/usr/bin/env python3
"""
fetch_ich_guidelines.py — acquire the public ICH/FDA/EMA guideline PDFs that
`galaxy.ai.drug_discovery.ich_corpus` indexes (BM25) for citation verification
and that the Grounded Standards Assistant's live RegulatoryRetriever grounds on.

WHY: the PDFs are NOT in the repo and are NOT shipped by scripts/sync_to_dev.sh
(which syncs backend/lib + DBs + workflows, not data/). Without them,
ich_corpus.verify_citation() returns method="unavailable" and the Grounded
Tier-A guideline grounding stays dormant (falls back to the curated pack). Run
this to populate the corpus, then arrange for the files to reach the dev Galaxy
container (S3 + container pull, or a mounted volume — the sync script does not
carry data/).

Target dir mirrors ich_corpus._ICH_DIR exactly:
    data/regulatory_training/ich_guidelines/raw/ich/<FILENAME>.pdf

SAFETY: every download is validated (must start with the %PDF magic bytes and be
over MIN_BYTES) before it is written, so a stale/redirected/wrong URL fails
loudly and is reported — it never writes an HTML error page as a "PDF".

URLs: taken from the official ICH database (database.ich.org), with FDA media
mirrors as fallbacks. Each entry is tagged `confirmed` (URL verified against a
search result / known mirror) or not (filename inferred from the ICH naming
pattern — validated at download). Entries with url=None need an official source
added before they can be fetched.

Usage:
    python3 scripts/fetch_ich_guidelines.py            # download missing/invalid
    python3 scripts/fetch_ich_guidelines.py --list     # print the plan, fetch nothing
    python3 scripts/fetch_ich_guidelines.py --force     # re-download even if present
    python3 scripts/fetch_ich_guidelines.py --dir /custom/path
"""

from __future__ import annotations

import argparse
import os
import sys
import time
import urllib.parse
import urllib.request
from typing import List, NamedTuple, Optional

MIN_BYTES = 20_000  # a real guideline PDF is far larger; smaller => error page
_UA = "BioMate/1.0 (biomate.ai; guideline-corpus-fetch)"
_TIMEOUT = 60

# Default target = ich_corpus._ICH_DIR (…/data/regulatory_training/ich_guidelines/raw/ich)
_REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
_DEFAULT_DIR = os.path.join(
    _REPO_ROOT, "data", "regulatory_training", "ich_guidelines", "raw", "ich"
)


class Guideline(NamedTuple):
    filename: str            # exact filename ich_corpus expects
    urls: List[str]          # candidate source URLs, tried in order
    confirmed: bool          # True => URL verified; False => inferred from pattern
    note: str


# The 16 distinct PDFs referenced by ich_corpus._GUIDELINE_FILES.
# Confirmed URLs are from database.ich.org search results (Oct 2026) or known FDA
# media mirrors. "pattern" entries follow the <CODE>_Guideline.pdf convention and
# are validated at download.
_BASE = "https://database.ich.org/sites/default/files/"
GUIDELINES: List[Guideline] = [
    Guideline("ICH_S2_R1.pdf", [_BASE + "S2_R1_Guideline.pdf",
                                 _BASE + urllib.parse.quote("S2(R1) Guideline.pdf")],
              True, "Genotoxicity testing (S2(R1))"),
    Guideline("ICH_S7A.pdf", [_BASE + "S7A_Guideline.pdf"],
              True, "Safety pharmacology (S7A)"),
    Guideline("ICH_S7B.pdf", [_BASE + "S7B_Guideline.pdf"],
              True, "QT/hERG nonclinical (S7B)"),
    Guideline("ICH_M3_R2.pdf", [_BASE + "M3_R2__Guideline.pdf"],
              True, "Nonclinical safety for trials (M3(R2)) — note double underscore"),
    Guideline("ICH_M4S_R2.pdf", [_BASE + "M4S_R2_Guideline.pdf"],
              True, "CTD Safety (M4S(R2))"),
    Guideline("ICH_S1A.pdf", [_BASE + urllib.parse.quote("S1A Guideline.pdf")],
              True, "Need for carcinogenicity studies (S1A) — space in filename"),
    Guideline("ICH_S1B.pdf", [_BASE + "S1B_Guideline.pdf",
                              _BASE + "S1B-R1_FinalGuideline_2022_0719.pdf"],
              True, "Carcinogenicity testing (S1B); R1 addendum as fallback"),
    Guideline("ICH_S1C_R2.pdf", [_BASE + urllib.parse.quote("S1C(R2) Guideline.pdf")],
              True, "Dose selection carcinogenicity (S1C(R2)) — parens+space filename"),
    Guideline("ICH_S5_R3.pdf", [_BASE + "S5-R3_Step4_Guideline_2020_0218.pdf"],
              True, "Reproductive/developmental tox (S5(R3))"),
    Guideline("ICH_S6_R1.pdf", [_BASE + "S6_R1_Guideline_0.pdf"],
              True, "Biotech-derived safety (S6(R1))"),
    Guideline("ICH_S8.pdf", [_BASE + "S8_Guideline.pdf"],
              True, "Immunotoxicity (S8)"),
    Guideline("ICH_S9.pdf", [_BASE + "S9_Guideline.pdf"],
              True, "Anticancer nonclinical (S9)"),
    Guideline("ICH_M7_R2.pdf", [_BASE + urllib.parse.quote("ICH_M7(R2)_Guideline_Step4_2023_0216_0.pdf"),
                                "https://www.fda.gov/media/170461/download"],
              True, "Mutagenic impurities (M7(R2)); FDA mirror as fallback"),
    Guideline("ICH_E5_R1.pdf", [_BASE + "E5_R1__Guideline.pdf"],
              True, "Ethnic factors (E5(R1)) — note double underscore"),
    Guideline("ICH_E7.pdf", [_BASE + "E7_Guideline.pdf"],
              True, "Geriatrics (E7)"),
    Guideline("EMA_PBPK.pdf",
              ["https://www.ema.europa.eu/en/documents/scientific-guideline/"
               "guideline-reporting-physiologically-based-pharmacokinetic-pbpk-"
               "modelling-and-simulation_en.pdf"],
              True, "EMA PBPK reporting guideline (EMA/CHMP/458101/2016; the "
                    "ich_corpus EMA/CHMP/EWP/37498/2011 ref is the superseded code)"),
]


def _is_valid_pdf(path: str) -> bool:
    try:
        if os.path.getsize(path) < MIN_BYTES:
            return False
        with open(path, "rb") as fh:
            return fh.read(5).startswith(b"%PDF")
    except OSError:
        return False


def _download(url: str, dest: str) -> Optional[str]:
    """Download url to dest if it validates as a PDF. Return None on success, else an error string."""
    req = urllib.request.Request(url, headers={"User-Agent": _UA})
    tmp = dest + ".part"
    try:
        with urllib.request.urlopen(req, timeout=_TIMEOUT) as resp:
            data = resp.read()
    except Exception as exc:
        return f"fetch failed: {exc}"
    if not data[:5].startswith(b"%PDF"):
        head = data[:80].decode("latin-1", "replace").replace("\n", " ")
        return f"not a PDF (got {len(data)}B starting {head!r})"
    if len(data) < MIN_BYTES:
        return f"too small ({len(data)}B < {MIN_BYTES})"
    with open(tmp, "wb") as fh:
        fh.write(data)
    os.replace(tmp, dest)
    return None


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--dir", default=_DEFAULT_DIR, help="target directory")
    ap.add_argument("--force", action="store_true", help="re-download even if a valid PDF exists")
    ap.add_argument("--list", action="store_true", help="print the plan and exit")
    args = ap.parse_args()

    if args.list:
        print(f"Target: {args.dir}\n{len(GUIDELINES)} guideline PDFs:")
        for g in GUIDELINES:
            tag = "confirmed" if g.confirmed else "PATTERN"
            url = g.urls[0] if g.urls else "(no URL — add official source)"
            print(f"  [{tag:9}] {g.filename:16} <- {url}")
            print(f"              {g.note}")
        return 0

    os.makedirs(args.dir, exist_ok=True)
    have, got, failed = [], [], []

    for g in GUIDELINES:
        dest = os.path.join(args.dir, g.filename)
        if not args.force and _is_valid_pdf(dest):
            have.append(g.filename)
            print(f"[skip] {g.filename} already present")
            continue
        if not g.urls:
            failed.append((g.filename, "no URL configured"))
            print(f"[FAIL] {g.filename}: no URL ({g.note})")
            continue
        err = "no candidates"
        for url in g.urls:
            err = _download(url, dest)
            if err is None:
                got.append(g.filename)
                print(f"[ok]   {g.filename} <- {url} ({os.path.getsize(dest)}B)")
                break
            print(f"[try]  {g.filename} <- {url}: {err}")
            time.sleep(1)
        if err is not None:
            failed.append((g.filename, err))

    print("\n=== summary ===")
    print(f"already present: {len(have)} | downloaded: {len(got)} | "
          f"failed: {len(failed)} | total: {len(GUIDELINES)}")
    if failed:
        print("failed (need a corrected/official URL):")
        for name, why in failed:
            print(f"  - {name}: {why}")
    # Non-zero exit only if NOTHING usable was obtained, so CI can detect a total
    # outage while a partial fetch (some confirmed PDFs) still succeeds.
    return 0 if (have or got) else 1


if __name__ == "__main__":
    sys.exit(main())
