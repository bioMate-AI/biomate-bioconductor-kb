"""
TGA AusPAR nonclinical-section scraper — Option B real-data enrichment.

Downloads AusPAR PDFs from TGA, extracts the "Nonclinical evaluation" section
text via PyMuPDF, emits JSONL records ready for v6+1 distribution-shift
training mix.

Why TGA: AusPARs are publicly published, structured per ICH M4 (Module 4
nonclinical is referenced), and reasonably structurally consistent across
products. They contain *reviewer-summary* prose of the §2.6.x content rather
than the sponsor submission itself — closest public proxy.

Usage:
    python scripts/scrape_auspar_nonclinical.py --urls-file <txt> --out <jsonl>

Or use the bundled seed URL list (10 recent AusPARs):
    python scripts/scrape_auspar_nonclinical.py --seed --out data/auspar_raw.jsonl
"""
from __future__ import annotations

import argparse
import json
import re
import sys
import time
from pathlib import Path
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1]

SEED_URLS = [
    "https://www.tga.gov.au/sites/default/files/2024-05/auspar-abrysvo-240502.pdf",
    "https://www.tga.gov.au/sites/default/files/2024-03/auspar-nurtec-odt-240301.pdf",
    "https://www.tga.gov.au/sites/default/files/2024-01/auspar-sunlenca-240123.pdf",
    "https://www.tga.gov.au/sites/default/files/2024-08/auspar-sidapvia-240814.pdf",
    "https://www.tga.gov.au/sites/default/files/2024-08/auspar-winlevi-240816.pdf",
    "https://www.tga.gov.au/sites/default/files/2025-03/auspar-eladynos-250218.pdf",
    "https://www.tga.gov.au/sites/default/files/2024-04/auspar-tibsovo-240402l.pdf",
    "https://www.tga.gov.au/sites/default/files/2024-12/auspar-kalydeco-241105.pdf",
    "https://www.tga.gov.au/sites/default/files/2024-07/auspar-xeomin-240624.pdf",
    "https://www.tga.gov.au/sites/default/files/2025-09/auspar-leqembi-250924.pdf",
]

# Heading patterns marking start of nonclinical section in AusPAR PDFs.
NONCLINICAL_START_RE = re.compile(
    r"^(?:Nonclinical (?:evaluation|assessment)|Module 4|Nonclinical)\b",
    re.IGNORECASE | re.MULTILINE,
)
# Heading patterns marking end (start of clinical section).
NONCLINICAL_END_RE = re.compile(
    r"^(?:Clinical (?:evaluation|assessment)|Module 5|Clinical findings)\b",
    re.IGNORECASE | re.MULTILINE,
)


def download(url: str, cache_dir: Path) -> Path:
    cache_dir.mkdir(parents=True, exist_ok=True)
    fname = url.rsplit("/", 1)[-1]
    out = cache_dir / fname
    if out.exists() and out.stat().st_size > 0:
        return out
    print(f"  fetching {fname}...", end=" ", flush=True)
    req = Request(url, headers={"User-Agent": "biomate-research/1.0"})
    with urlopen(req, timeout=60) as resp, out.open("wb") as f:
        f.write(resp.read())
    print(f"{out.stat().st_size // 1024} KB")
    return out


def extract_text(pdf_path: Path) -> str:
    import fitz
    doc = fitz.open(str(pdf_path))
    text = "\n".join(page.get_text() for page in doc)
    doc.close()
    return text


def extract_nonclinical(text: str) -> str | None:
    start = NONCLINICAL_START_RE.search(text)
    if not start:
        return None
    section = text[start.start():]
    end = NONCLINICAL_END_RE.search(section, pos=200)  # skip immediate self-match
    if end:
        section = section[: end.start()]
    section = re.sub(r"\n{3,}", "\n\n", section.strip())
    return section


def make_record(url: str, nonclinical_text: str) -> dict:
    slug = url.rsplit("/", 1)[-1].replace(".pdf", "")
    drug_match = re.match(r"auspar-([^-]+(?:-\w+)?)", slug)
    drug = drug_match.group(1) if drug_match else slug
    return {
        "messages": [
            {"role": "system", "content":
                "You are a computational pharmacologist preparing ICH M4 CTD Module 2.6 "
                "nonclinical summaries for IND applications. Write plain regulatory prose."},
            {"role": "user", "content":
                f"Write the nonclinical evaluation summary for {drug}. Cite applicable ICH "
                f"guidelines (ICH M3(R2), ICH S2(R1), ICH S7A, ICH S7B as appropriate)."},
            {"role": "assistant", "content": nonclinical_text},
        ],
        "meta": {
            "task": "section_generation",
            "section_type": "tox_overview",
            "region": "TGA",
            "source": "TGA_AusPAR",
            "drug": drug,
            "source_url": url,
        },
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seed", action="store_true", help="use bundled 10-URL seed list")
    ap.add_argument("--urls-file", type=Path)
    ap.add_argument("--out", type=Path,
                    default=ROOT / "data/regulatory_training/auspar/auspar_nonclinical.jsonl")
    ap.add_argument("--cache", type=Path, default=ROOT / "data/regulatory_training/auspar/pdfs")
    ap.add_argument("--delay", type=float, default=2.0, help="seconds between requests")
    args = ap.parse_args()

    if args.seed:
        urls = SEED_URLS
    elif args.urls_file:
        urls = [u.strip() for u in args.urls_file.read_text().splitlines() if u.strip()]
    else:
        print("Provide --seed or --urls-file")
        sys.exit(1)

    args.out.parent.mkdir(parents=True, exist_ok=True)
    written = 0
    failed = 0
    skipped = 0

    with args.out.open("w") as f:
        for url in urls:
            try:
                pdf = download(url, args.cache)
                text = extract_text(pdf)
                nonclinical = extract_nonclinical(text)
                if not nonclinical or len(nonclinical) < 500:
                    print(f"    no nonclinical section in {pdf.name}")
                    skipped += 1
                    continue
                record = make_record(url, nonclinical[:8000])  # cap length
                f.write(json.dumps(record) + "\n")
                written += 1
                time.sleep(args.delay)
            except Exception as e:
                print(f"    FAIL {url}: {e}")
                failed += 1

    print(f"\nWrote {written} records, skipped {skipped}, failed {failed}")
    print(f"Output: {args.out}")


if __name__ == "__main__":
    main()
