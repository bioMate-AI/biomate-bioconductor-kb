"""Public regulatory corpus scraper — zero-cost expansion.

Pulls additional §2.6 nonclinical-summary prose from public regulatory
archives, output shape compatible with v6 combined_sft.jsonl so the
results can be appended directly.

Primary source: openFDA (real FDA-blessed prose, no auth). The previous
EMA EPAR endpoint shifted to a 404; the scaffold remains for when EMA
publishes a stable replacement.

Usage:
  python scripts/scrape_regulatory_corpus.py --source openfda --limit 50
"""
from __future__ import annotations
import argparse, json, re, sys, time, urllib.parse
import urllib.request as urlreq
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
OUT = REPO / "data" / "regulatory_training" / "scraped"
OUT.mkdir(parents=True, exist_ok=True)

HEADERS = {
    "User-Agent": (
        "BioMate-RegulatoryCorpus/1.0 (+research-only, "
        "purpose=LLM-evaluation-corpus-augmentation)"
    ),
}
SLEEP_S = 2.0


def _fetch(url: str, timeout: int = 30) -> bytes:
    req = urlreq.Request(url, headers=HEADERS)
    with urlreq.urlopen(req, timeout=timeout) as resp:
        return resp.read()


# ─── openFDA — sample categories under-represented in v6 ───────────────────
OPENFDA_URL = "https://api.fda.gov/drug/label.json"


def scrape_openfda_expansion(limit: int = 50) -> list[dict]:
    queries = [
        ("nonclinical_toxicology:carcinogenicity AND openfda.product_type:human", "oncology_carcinogen"),
        ("nonclinical_toxicology:reproductive AND openfda.product_type:human",    "reproductive_tox"),
        ("clinical_pharmacology:pharmacokinetics AND openfda.product_type:human", "pk_human"),
        ("warnings:hepatotoxicity",                                                "dili"),
        ("warnings:QT AND warnings:prolongation",                                 "qt_prolongation"),
    ]
    per_query = max(1, limit // len(queries))
    out: list[dict] = []
    for q, cat in queries:
        params = urllib.parse.urlencode({"search": q, "limit": per_query})
        url = f"{OPENFDA_URL}?{params}"
        try:
            time.sleep(SLEEP_S)
            data = json.loads(_fetch(url).decode("utf-8"))
        except Exception as e:
            print(f"[openfda] {cat}: {e}", file=sys.stderr)
            continue
        for r in data.get("results", []):
            text = (
                "\n\n".join(r.get("nonclinical_toxicology", []))
                or "\n\n".join(r.get("clinical_pharmacology", []))
                or "\n\n".join(r.get("warnings", []))
            )
            if len(text) < 300:
                continue
            molecule = (r.get("openfda", {}).get("generic_name") or ["unknown"])[0]
            out.append({
                "messages": [
                    {"role": "system",
                     "content": "You are a regulatory affairs scientist writing an ICH M4 §2.6 nonclinical written summary."},
                    {"role": "user",
                     "content": f"Source: openFDA label for {molecule}. Write a §2.6 summary based on the available data."},
                    {"role": "assistant",
                     "content": text[:4000]},
                ],
                "meta": {
                    "source": "openFDA_FDA_Labels_v2",
                    "category": cat,
                    "molecule": molecule,
                    "region": "FDA",
                    "task": "section_generation",
                },
            })
    return out


# ─── EMA scaffold — endpoint shifted; revisit when stable ──────────────────
def scrape_ema_epars(limit: int = 50) -> list[dict]:
    """Placeholder. EMA EPAR PDF URL scheme changed mid-2026; the previous
    `/en/documents/assessment-report/...-epar...pdf` slug pattern now 404s.
    Returns [] until a stable replacement endpoint is documented.
    """
    print("[ema] endpoint placeholder — see docs for revisit notes",
          file=sys.stderr)
    return []


SOURCES = {"openfda": scrape_openfda_expansion, "ema": scrape_ema_epars}


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--source", choices=list(SOURCES.keys()) + ["all"], default="openfda")
    ap.add_argument("--limit", type=int, default=50)
    args = ap.parse_args()
    sources = list(SOURCES.keys()) if args.source == "all" else [args.source]
    for src in sources:
        rows = SOURCES[src](limit=args.limit)
        out_path = OUT / f"{src}_corpus.jsonl"
        with out_path.open("w") as f:
            for r in rows:
                f.write(json.dumps(r) + "\n")
        print(f"[{src}] wrote {len(rows)} paragraphs → {out_path}", file=sys.stderr)


if __name__ == "__main__":
    main()
