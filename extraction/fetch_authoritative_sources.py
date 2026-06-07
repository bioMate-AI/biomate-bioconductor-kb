#!/usr/bin/env python3
"""
Pass-2 source fetcher.

For each Bioconductor package in MANIFEST.json, fetch:
  - Landing page    https://bioconductor.org/packages/release/bioc/html/<pkg>.html
  - Vignettes       (URLs scraped from the landing page)
  - DESCRIPTION     https://bioconductor.org/packages/release/bioc/DESCRIPTION/<pkg>
  - Citation BibTeX https://bioconductor.org/packages/release/bioc/citations/<pkg>/citation.bib

Plus (per-domain, fetched once and cached):
  - OSCA — Orchestrating Single-Cell Analysis
  - Computational Genomics with R
  - Modern Statistics for Modern Biology
  - Bioconductor Workflows series index

All converted from HTML to readable plain text. Cached at
bioconductor_skill/public_release/.source_cache/.

Output: {.source_cache/<pkg>/{landing,vignette_*,description,citation}.txt}
        + a manifest of what was found per package.

Designed to be re-runnable; HTTP responses cached on disk.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
import time
import urllib.parse
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

try:
    import requests
except ImportError:
    print("pip install requests", file=sys.stderr); sys.exit(1)

# Convert HTML → text without bs4 if not available — use html2text or fall through.
try:
    from html2text import HTML2Text
    _h2t = HTML2Text()
    _h2t.body_width = 0
    _h2t.ignore_images = True
    _h2t.ignore_links = False
    def html_to_text(html: str) -> str: return _h2t.handle(html)
except ImportError:
    # Minimal fallback: strip tags + collapse whitespace
    def html_to_text(html: str) -> str:
        t = re.sub(r"<script[^>]*>.*?</script>", "", html, flags=re.DOTALL|re.I)
        t = re.sub(r"<style[^>]*>.*?</style>", "", t, flags=re.DOTALL|re.I)
        t = re.sub(r"<[^>]+>", " ", t)
        t = re.sub(r"\s+", " ", t)
        return t.strip()

REPO       = Path(__file__).parent.parent
MANIFEST   = REPO / "MANIFEST.json"
CACHE      = REPO / ".source_cache"
INDEX_OUT  = CACHE / "_index.json"

BIOC_BASE  = "https://bioconductor.org/packages/release/bioc"
DESC_BASE  = "https://bioconductor.org/packages/release/bioc/DESCRIPTION"
HEADERS    = {"User-Agent": "biomate-kb-fetcher/1.0 (educational/research)"}
TIMEOUT    = 30
THROTTLE_S = 0.10   # be polite — small delay between same-host requests per worker


def _safe_get(url: str, retries: int = 2) -> tuple[int, str]:
    last_err = ""
    for i in range(retries + 1):
        try:
            r = requests.get(url, headers=HEADERS, timeout=TIMEOUT)
            return r.status_code, r.text
        except requests.RequestException as exc:
            last_err = str(exc)
            time.sleep(1.5 ** i)
    return 0, f"ERR: {last_err}"


def _domain_to_book(domain: str) -> list[str]:
    """Map a domain folder to the Bioconductor book/workflow chapter URLs
    most likely to mention the package."""
    m = {
        "single-cell":     ["https://bioconductor.org/books/release/OSCA/"],
        "scrnaseq":        ["https://bioconductor.org/books/release/OSCA/"],
        "transcriptomics": ["https://compgenomr.github.io/book/rnaseqanalysis.html"],
        "rnaseq-de":       ["https://compgenomr.github.io/book/rnaseqanalysis.html"],
        "chip-seq":        ["https://compgenomr.github.io/book/chipseqanalysis.html"],
        "epigenomics":     ["https://compgenomr.github.io/book/dnameth.html"],
        "methylation":     ["https://compgenomr.github.io/book/dnameth.html"],
        "enrichment":      ["https://www.huber.embl.de/msmb/Chap-Multivariate.html"],
        "variant-calling": ["https://compgenomr.github.io/book/snpcallingannotation.html"],
        "metagenomics":    [],
        "proteomics":      [],
        "metabolomics":    [],
        "imaging":         [],
        "annotation":      [],
        "genomics":        [],
        "infrastructure":  [],
        "general":         [],
    }
    return m.get(domain, [])


def _fetch_one(pkg: dict, force: bool = False) -> dict:
    name = pkg["name"]
    domain = pkg["domain"]
    pkg_cache = CACHE / name.lower()
    pkg_cache.mkdir(parents=True, exist_ok=True)

    out = {"name": name, "domain": domain, "files": {}, "errors": []}
    # Landing page — keep BOTH the raw HTML (to mine href= links) and the text
    landing_path     = pkg_cache / "landing.txt"
    landing_raw_path = pkg_cache / "landing.html"
    landing_html = ""
    if not landing_path.exists() or force:
        url = f"{BIOC_BASE}/html/{name}.html"
        status, html = _safe_get(url)
        if status == 200:
            text = html_to_text(html)
            landing_path.write_text(text)
            landing_raw_path.write_text(html)
            landing_html = html
            out["files"]["landing"] = {"url": url, "bytes": len(text)}
        else:
            out["errors"].append(f"landing_{status}: {url}")
    else:
        out["files"]["landing"] = {"url": f"{BIOC_BASE}/html/{name}.html",
                                     "bytes": landing_path.stat().st_size}
        if landing_raw_path.exists():
            landing_html = landing_raw_path.read_text()
        else:
            # Re-fetch HTML once if missing
            _, landing_html = _safe_get(f"{BIOC_BASE}/html/{name}.html")
            if landing_html and not landing_html.startswith("ERR"):
                landing_raw_path.write_text(landing_html)

    # Parse vignette URLs from RAW HTML href attributes.
    # Bioconductor landing pages link as href="../vignettes/<pkg>/inst/doc/<file>.html"
    vignette_urls: list[str] = []
    # Prefer HTML vignettes; fall back to R scripts (text), then PDFs (last resort)
    # Bioconductor href: ../vignettes/<pkg>/inst/doc/<file>.{html,pdf,R}
    href_pattern = re.compile(
        rf"href=\"(?:\.\./|/packages/release/bioc/)?vignettes/{re.escape(name)}/inst/doc/([^\"]+\.(?:html|R|pdf))\"",
        re.IGNORECASE,
    )
    candidates: list[tuple[int, str]] = []   # (priority, url) where lower = better
    for m in href_pattern.finditer(landing_html or ""):
        fn = m.group(1)
        url = f"{BIOC_BASE}/vignettes/{name}/inst/doc/{fn}"
        prio = 1 if fn.lower().endswith(".html") else (2 if fn.endswith(".R") else 3)
        candidates.append((prio, url))
    # Take up to 4 best-priority unique URLs
    seen: set[str] = set()
    for prio, url in sorted(candidates, key=lambda x: x[0]):
        if url in seen: continue
        seen.add(url)
        vignette_urls.append(url)
        if len(vignette_urls) >= 4: break

    for i, vurl in enumerate(vignette_urls):
        # Handle HTML / R / PDF differently
        lower = vurl.lower()
        slug = hashlib.md5(vurl.encode()).hexdigest()[:8]
        vpath = pkg_cache / f"vignette_{i}_{slug}.txt"
        if vpath.exists() and not force:
            out["files"][f"vignette_{i}"] = {"url": vurl,
                                              "bytes": vpath.stat().st_size}
            continue
        time.sleep(THROTTLE_S)

        if lower.endswith(".pdf"):
            # Use requests to grab raw bytes, then pdftotext via subprocess
            try:
                r = requests.get(vurl, headers=HEADERS, timeout=TIMEOUT, stream=True)
                if r.status_code != 200:
                    out["errors"].append(f"vignette_{r.status_code}: {vurl}")
                    continue
                pdf_path = pkg_cache / f"vignette_{i}_{slug}.pdf"
                pdf_path.write_bytes(r.content)
                # Try pdftotext from poppler
                import subprocess
                try:
                    proc = subprocess.run(["pdftotext", "-q", "-layout",
                                            str(pdf_path), str(vpath)],
                                          timeout=30, capture_output=True)
                    if proc.returncode == 0 and vpath.exists():
                        text = vpath.read_text(errors="ignore")[:80000]
                        vpath.write_text(text)
                        out["files"][f"vignette_{i}"] = {"url": vurl, "bytes": len(text)}
                    else:
                        out["errors"].append(f"pdftotext_fail: {vurl}")
                except (FileNotFoundError, subprocess.TimeoutExpired):
                    out["errors"].append(f"no_pdftotext: {vurl}")
            except requests.RequestException as exc:
                out["errors"].append(f"vignette_req_err: {exc}")
        elif lower.endswith(".r"):
            # R script — already plain text; keep verbatim (it's executable example)
            status, text = _safe_get(vurl)
            if status == 200:
                vpath.write_text(text[:80000])
                out["files"][f"vignette_{i}"] = {"url": vurl, "bytes": len(text)}
            else:
                out["errors"].append(f"vignette_{status}: {vurl}")
        else:
            # HTML default
            status, html = _safe_get(vurl)
            if status == 200:
                text = html_to_text(html)[:80000]
                vpath.write_text(text)
                out["files"][f"vignette_{i}"] = {"url": vurl, "bytes": len(text)}
            else:
                out["errors"].append(f"vignette_{status}: {vurl}")

    # DESCRIPTION file
    desc_path = pkg_cache / "description.txt"
    if not desc_path.exists() or force:
        time.sleep(THROTTLE_S)
        url = f"{DESC_BASE}/{name}"
        status, text = _safe_get(url)
        if status == 200:
            desc_path.write_text(text[:8000])
            out["files"]["description"] = {"url": url, "bytes": len(text)}
        else:
            out["errors"].append(f"description_{status}")
    else:
        out["files"]["description"] = {"url": f"{DESC_BASE}/{name}",
                                         "bytes": desc_path.stat().st_size}

    # Citation
    cit_path = pkg_cache / "citation.txt"
    if not cit_path.exists() or force:
        time.sleep(THROTTLE_S)
        url = f"https://bioconductor.org/packages/release/bioc/citations/{name}/citation.bib"
        status, text = _safe_get(url)
        if status == 200:
            cit_path.write_text(text[:4000])
            out["files"]["citation"] = {"url": url, "bytes": len(text)}
        else:
            out["errors"].append(f"citation_{status}")
    return out


def _fetch_books_once(force: bool = False):
    """Fetch domain-relevant book chapter snippets once; reused by every package
    in that domain at enrichment time."""
    books_dir = CACHE / "_books"
    books_dir.mkdir(parents=True, exist_ok=True)
    book_urls: set[str] = set()
    for d, urls in {
        "single-cell":     ["https://bioconductor.org/books/release/OSCA/"],
        "transcriptomics": ["https://compgenomr.github.io/book/rnaseqanalysis.html"],
        "chip-seq":        ["https://compgenomr.github.io/book/chipseqanalysis.html"],
        "epigenomics":     ["https://compgenomr.github.io/book/dnameth.html"],
        "methylation":     ["https://compgenomr.github.io/book/dnameth.html"],
        "enrichment":      ["https://www.huber.embl.de/msmb/Chap-Multivariate.html"],
        "variant-calling": ["https://compgenomr.github.io/book/snpcallingannotation.html"],
    }.items():
        book_urls.update(urls)
    for url in book_urls:
        slug = hashlib.md5(url.encode()).hexdigest()[:8]
        fpath = books_dir / f"{slug}.txt"
        if fpath.exists() and not force:
            print(f"  [books] cached {url}")
            continue
        status, html = _safe_get(url)
        if status == 200:
            text = html_to_text(html)[:120000]
            fpath.write_text(text)
            (books_dir / f"{slug}.meta.json").write_text(json.dumps({"url": url}))
            print(f"  [books] fetched {url} ({len(text)}c)")
        else:
            print(f"  [books] FAIL {status} {url}")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--workers", type=int, default=6)
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--limit", type=int, default=0, help="0 = all")
    args = ap.parse_args()

    CACHE.mkdir(parents=True, exist_ok=True)
    manifest = json.loads(MANIFEST.read_text())
    pkgs = manifest["packages"]
    if args.limit:
        pkgs = pkgs[:args.limit]

    print(f"[fetch] fetching authoritative sources for {len(pkgs)} packages")
    print(f"[fetch] cache → {CACHE}")
    print(f"[fetch] workers={args.workers} force={args.force}")
    print()
    print("=== Bioconductor book chapters (one-shot) ===")
    _fetch_books_once(force=args.force)
    print()
    print("=== Per-package landing + vignettes + description + citation ===")

    t0 = time.time()
    results: list[dict] = []
    with ThreadPoolExecutor(max_workers=args.workers) as ex:
        futures = {ex.submit(_fetch_one, p, args.force): p for p in pkgs}
        done = 0
        for fut in as_completed(futures):
            r = fut.result()
            results.append(r)
            done += 1
            files_found = list(r["files"].keys())
            n_vign = sum(1 for k in files_found if k.startswith("vignette_"))
            err = f" err={len(r['errors'])}" if r["errors"] else ""
            if done <= 10 or done % 50 == 0:
                print(f"  [{done:4d}/{len(pkgs)}] {r['name']:30s} "
                      f"vignettes={n_vign} files={len(files_found)}{err}",
                      flush=True)

    elapsed = time.time() - t0
    # Summary
    total_vign = sum(sum(1 for k in r["files"] if k.startswith("vignette_")) for r in results)
    pkgs_with_vign = sum(1 for r in results if any(k.startswith("vignette_") for k in r["files"]))
    pkgs_with_landing = sum(1 for r in results if "landing" in r["files"])
    pkgs_with_desc = sum(1 for r in results if "description" in r["files"])
    pkgs_with_cit = sum(1 for r in results if "citation" in r["files"])

    print()
    print(f"[fetch] done in {elapsed/60:.1f} min")
    print(f"[fetch] {pkgs_with_landing}/{len(pkgs)} landing pages")
    print(f"[fetch] {pkgs_with_vign}/{len(pkgs)} have ≥1 vignette ({total_vign} vignettes total)")
    print(f"[fetch] {pkgs_with_desc}/{len(pkgs)} DESCRIPTIONs")
    print(f"[fetch] {pkgs_with_cit}/{len(pkgs)} citations")

    INDEX_OUT.write_text(json.dumps({
        "ran_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "n_packages": len(pkgs),
        "elapsed_minutes": round(elapsed / 60, 2),
        "pkgs_with_landing": pkgs_with_landing,
        "pkgs_with_vignettes": pkgs_with_vign,
        "vignettes_total": total_vign,
        "pkgs_with_description": pkgs_with_desc,
        "pkgs_with_citation": pkgs_with_cit,
        "results": results,
    }, indent=2))
    print(f"[fetch] index → {INDEX_OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
