"""
Health Canada Summary Basis of Decision (SBD) scraper — Option B real-data
enrichment, sibling to scrape_auspar_nonclinical.py.

SBDs are Health Canada's public reviewer-summary documents for approved
drug submissions. They contain a "Non-clinical Basis for Decision" section
that summarizes Module 4 findings — closest Canadian public proxy for §2.6.x.

URL pattern: https://hpr-rps.hres.ca/reg-content/summary-basis-decision-detail.php?lang=en&linkID=SBD<number>

Usage:
    python scripts/scrape_canada_sbd.py --seed
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

# Recent SBD entries (English). Add more as needed.
SEED_URLS = [
    "https://hpr-rps.hres.ca/reg-content/summary-basis-decision-detail-two.php?lang=en&linkID=SBD00766",
    "https://hpr-rps.hres.ca/reg-content/summary-basis-decision-detail-two.php?lang=en&linkID=SBD00755",
    "https://hpr-rps.hres.ca/reg-content/summary-basis-decision-detail-two.php?lang=en&linkID=SBD00742",
    "https://hpr-rps.hres.ca/reg-content/summary-basis-decision-detail-two.php?lang=en&linkID=SBD00738",
    "https://hpr-rps.hres.ca/reg-content/summary-basis-decision-detail-two.php?lang=en&linkID=SBD00724",
]

# Heading patterns marking start of nonclinical section in SBD HTML.
NONCLINICAL_START_RE = re.compile(
    r"(?:Non[- ]clinical\s+(?:Basis|Pharmacology|Toxicology|Evaluation)|"
    r"6\.2\s+Non[- ]clinical)",
    re.IGNORECASE,
)
NONCLINICAL_END_RE = re.compile(
    r"(?:Clinical\s+(?:Basis|Evaluation|Pharmacology)|"
    r"6\.3\s+Clinical|7\s+(?:Quality|Manufacturing))",
    re.IGNORECASE,
)


def download(url: str, cache_dir: Path) -> Path:
    cache_dir.mkdir(parents=True, exist_ok=True)
    # File name from linkID
    m = re.search(r"linkID=(\w+)", url)
    fname = f"{m.group(1) if m else 'sbd_unknown'}.html"
    out = cache_dir / fname
    if out.exists() and out.stat().st_size > 0:
        return out
    print(f"  fetching {fname}...", end=" ", flush=True)
    req = Request(url, headers={"User-Agent": "biomate-research/1.0"})
    with urlopen(req, timeout=60) as resp, out.open("wb") as f:
        f.write(resp.read())
    print(f"{out.stat().st_size // 1024} KB")
    return out


def html_to_text(html: str) -> str:
    """Strip HTML tags, collapse whitespace."""
    text = re.sub(r"<script[^>]*>.*?</script>", " ", html, flags=re.S | re.I)
    text = re.sub(r"<style[^>]*>.*?</style>",   " ", text, flags=re.S | re.I)
    text = re.sub(r"<[^>]+>", " ", text)
    text = re.sub(r"&nbsp;|&#160;", " ", text)
    text = re.sub(r"&[a-z]+;", " ", text)
    text = re.sub(r"\s+", " ", text).strip()
    return text


def extract_nonclinical(text: str) -> str | None:
    start = NONCLINICAL_START_RE.search(text)
    if not start:
        return None
    section = text[start.start():]
    end = NONCLINICAL_END_RE.search(section, pos=200)
    if end:
        section = section[: end.start()]
    return section.strip()


def make_record(url: str, nonclinical_text: str) -> dict:
    m = re.search(r"linkID=(\w+)", url)
    drug_id = m.group(1) if m else "unknown"
    return {
        "messages": [
            {"role": "system", "content":
                "You are a computational pharmacologist preparing ICH M4 CTD Module 2.6 "
                "nonclinical summaries. Write plain regulatory prose."},
            {"role": "user", "content":
                f"Write the nonclinical evaluation summary for the drug submission {drug_id}. "
                f"Cite applicable ICH guidelines (ICH M3(R2), ICH S2(R1), ICH S7A, ICH S7B "
                f"as appropriate)."},
            {"role": "assistant", "content": nonclinical_text},
        ],
        "meta": {
            "task": "section_generation",
            "section_type": "tox_overview",
            "region": "HealthCanada",
            "source": "Canada_SBD",
            "drug": drug_id,
            "source_url": url,
        },
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seed", action="store_true")
    ap.add_argument("--urls-file", type=Path)
    ap.add_argument("--out", type=Path,
                    default=ROOT / "data/regulatory_training/canada_sbd/sbd_nonclinical.jsonl")
    ap.add_argument("--cache", type=Path, default=ROOT / "data/regulatory_training/canada_sbd/html")
    ap.add_argument("--delay", type=float, default=2.0)
    args = ap.parse_args()

    if args.seed:
        urls = SEED_URLS
    elif args.urls_file:
        urls = [u.strip() for u in args.urls_file.read_text().splitlines() if u.strip()]
    else:
        print("Provide --seed or --urls-file")
        sys.exit(1)

    args.out.parent.mkdir(parents=True, exist_ok=True)
    written, failed, skipped = 0, 0, 0

    with args.out.open("w") as f:
        for url in urls:
            try:
                html_path = download(url, args.cache)
                text = html_to_text(html_path.read_text(errors="replace"))
                nonclinical = extract_nonclinical(text)
                if not nonclinical or len(nonclinical) < 500:
                    print(f"    no nonclinical section in {html_path.name}")
                    skipped += 1
                    continue
                record = make_record(url, nonclinical[:8000])
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
