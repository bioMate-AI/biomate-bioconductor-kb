"""
Europe PMC + NCBI EFetch literature retriever.

Productized from `evaluation/retrievers/europe_pmc_fulltext.py`. Two public
entry points:

- `fetch_literature_passage(query, *, doi=..., pmid=..., choices=..., max_chars=2000)`
  Given a known paper (by DOI or PMID), fetch full text, score paragraphs by
  keyword overlap with `query` (+ optional `choices` for MCQ), return the
  best-matching passage. Used for UC-1 (gene literature QA), UC-3 (auto-loop
  citation), UC-5 (param prefill from cited paper).

- `search_literature(query, *, year_min=None, max_results=5)`
  Free-text search → list of {pmid, doi, title, abstract, year}. Used for UC-2
  (CRO compliance) and UC-1 when no specific paper is cited.

All network calls have disk caching keyed on hash of inputs. Returns "" or []
on failure — never raises. Stdlib + `requests` only.
"""
from __future__ import annotations

import hashlib
import json
import logging
import os
import re
from pathlib import Path
from typing import Optional, List, Dict, Any

import requests

logger = logging.getLogger(__name__)

# Cache directory: prefer env override, then user cache, then a tmp fallback.
_DEFAULT_CACHE = (
    os.environ.get("BIOMATE_RETRIEVER_CACHE")
    or os.path.expanduser("~/.cache/biomate/retrievers/europe_pmc")
)
CACHE_DIR = Path(_DEFAULT_CACHE)
CACHE_DIR.mkdir(parents=True, exist_ok=True)

_HEADERS = {
    "User-Agent": "BioMate-Retriever/1.0 (xiaoni5122@gmail.com)",
}

# ─────────────────────────────────────────────────────────────────────────────
# DOI / PMID resolution
# ─────────────────────────────────────────────────────────────────────────────

def _doi_from_url(url: str) -> Optional[str]:
    m = re.search(r"(?:doi\.org/|^)\s*(10\.\d{4,}/[^\s]+)$", url.strip())
    return m.group(1) if m else None


def _resolve_to_pmcid(doi: Optional[str] = None, pmid: Optional[str] = None,
                      timeout: int = 8) -> Optional[str]:
    """Map DOI or PMID → PMC ID (e.g. 'PMC11237425'). Returns None if not in PMC."""
    if doi:
        query = f"DOI:{doi}"
    elif pmid:
        query = f"EXT_ID:{pmid} AND SRC:MED"
    else:
        return None
    try:
        r = requests.get(
            "https://www.ebi.ac.uk/europepmc/webservices/rest/search",
            params={"query": query, "format": "json", "resultType": "core"},
            headers=_HEADERS, timeout=timeout,
        )
        r.raise_for_status()
        results = r.json().get("resultList", {}).get("result", [])
        if not results:
            return None
        return results[0].get("pmcid") or None
    except Exception as exc:
        logger.debug("EuropePMC resolve failed: %s", exc)
        return None


def _fetch_fulltext_xml(pmcid: str, timeout: int = 20) -> Optional[str]:
    pmc_num = pmcid.replace("PMC", "")
    try:
        r = requests.get(
            "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi",
            params={"db": "pmc", "id": pmc_num, "rettype": "xml"},
            headers=_HEADERS, timeout=timeout,
        )
        if r.ok and len(r.text) > 500:
            return r.text
    except Exception as exc:
        logger.debug("NCBI EFetch PMC failed: %s", exc)
    return None


def _xml_to_paragraphs(xml: str) -> List[str]:
    paragraphs = re.findall(r"<p[^>]*>(.*?)</p>", xml, re.DOTALL)
    titles = re.findall(r"<title[^>]*>(.*?)</title>", xml, re.DOTALL)
    out = []
    for raw in titles + paragraphs:
        text = re.sub(r"<[^>]+>", "", raw)
        text = (text.replace("&amp;", "&").replace("&lt;", "<")
                    .replace("&gt;", ">").replace("&quot;", '"')
                    .replace("&#x2009;", " ").replace("&#x2010;", "-")
                    .replace("&#x00a0;", " "))
        text = re.sub(r"\s+", " ", text).strip()
        if text and len(text) > 30:
            out.append(text)
    return out


_STOP = {"the","a","an","is","are","was","were","what","which","how","when",
         "where","who","why","does","do","did","in","of","and","or","for","to","with",
         "that","this","from","by","as","at","be","been","has","have","had","not","no",
         "can","could","would","should","will","its","their","they","it","on","than",
         "into","about","after","study","shown","found","show","associated","between",
         "percent","percentage","following","question","cells","mice"}


def _score_paragraphs(paragraphs: List[str], query: str,
                       choices: Optional[List[str]] = None,
                       max_chars: int = 2000) -> str:
    q_lower = query.lower()
    q_tokens = {w for w in re.findall(r"\b[a-zA-Z][a-zA-Z0-9-]{3,}\b", q_lower) if w not in _STOP}
    q_caps = {c.lower() for c in re.findall(r"\b[A-Z][a-zA-Z0-9-]{3,}\b", query)}
    choice_tokens = set()
    for ch in choices or []:
        for w in re.findall(r"\b[a-zA-Z][a-zA-Z0-9-]{3,}\b", ch):
            if w.lower() not in _STOP:
                choice_tokens.add(w.lower())

    scored = []
    for p in paragraphs:
        p_lower = p.lower()
        score = sum(1 for t in q_tokens if t in p_lower)
        score += sum(2 for t in q_caps if t in p_lower)
        score += sum(5 for t in choice_tokens if t in p_lower)
        if score > 0:
            scored.append((score, p))
    scored.sort(key=lambda x: -x[0])

    chosen, total = [], 0
    for _, p in scored:
        if total + len(p) > max_chars:
            chosen.append(p[: max_chars - total])
            break
        chosen.append(p)
        total += len(p)
    return "\n\n".join(chosen)


# ─────────────────────────────────────────────────────────────────────────────
# Public API
# ─────────────────────────────────────────────────────────────────────────────

def fetch_literature_passage(query: str, *,
                              doi: Optional[str] = None,
                              pmid: Optional[str] = None,
                              source_url: Optional[str] = None,
                              choices: Optional[List[str]] = None,
                              max_chars: int = 2000,
                              timeout: int = 20) -> str:
    """
    Fetch the most query-relevant passage from a known paper.

    Provide one of `doi`, `pmid`, or `source_url` (URL containing a DOI).
    Returns "" if the paper is not in PMC, can't be fetched, or has no
    relevant passage.
    """
    if source_url and not doi:
        doi = _doi_from_url(source_url)
    if not (doi or pmid):
        return ""

    cache_key_src = f"{doi or ''}|{pmid or ''}|{query}|{'|'.join(sorted(choices or []))}|{max_chars}"
    cache_hash = hashlib.md5(cache_key_src.encode("utf-8")).hexdigest()[:16]
    cache_file = CACHE_DIR / f"passage_{cache_hash}.txt"
    if cache_file.exists():
        content = cache_file.read_text(encoding="utf-8")
        # Sentinel "" written by us means a prior lookup returned nothing
        return content if content != "__NEGATIVE__" else ""

    def _write_negative():
        try:
            cache_file.write_text("__NEGATIVE__", encoding="utf-8")
        except Exception:
            pass

    pmcid = _resolve_to_pmcid(doi=doi, pmid=pmid, timeout=timeout)
    if not pmcid:
        _write_negative(); return ""
    xml = _fetch_fulltext_xml(pmcid, timeout=timeout)
    if not xml:
        _write_negative(); return ""
    paragraphs = _xml_to_paragraphs(xml)
    if not paragraphs:
        _write_negative(); return ""

    passage = _score_paragraphs(paragraphs, query, choices=choices, max_chars=max_chars)
    if passage:
        cache_file.write_text(passage, encoding="utf-8")
    else:
        _write_negative()
    return passage


def search_literature(query: str, *,
                       year_min: Optional[int] = None,
                       max_results: int = 5,
                       timeout: int = 10) -> List[Dict[str, Any]]:
    """
    Free-text search against Europe PMC. Returns list of dicts with
    {pmid, doi, title, abstract, year, citedByCount}. Empty list on failure.
    """
    q = query
    if year_min:
        q = f"({query}) AND PUB_YEAR:[{year_min} TO 3000]"

    cache_hash = hashlib.md5(f"{q}|{max_results}".encode("utf-8")).hexdigest()[:16]
    cache_file = CACHE_DIR / f"search_{cache_hash}.json"
    if cache_file.exists():
        try:
            return json.loads(cache_file.read_text(encoding="utf-8"))
        except Exception:
            pass

    try:
        r = requests.get(
            "https://www.ebi.ac.uk/europepmc/webservices/rest/search",
            params={"query": q, "format": "json", "resultType": "core",
                    "pageSize": max_results},
            headers=_HEADERS, timeout=timeout,
        )
        r.raise_for_status()
        results = r.json().get("resultList", {}).get("result", [])
    except Exception as exc:
        logger.debug("EuropePMC search failed: %s", exc)
        return []

    out = []
    for res in results[:max_results]:
        out.append({
            "pmid": res.get("pmid") or "",
            "doi": res.get("doi") or "",
            "pmcid": res.get("pmcid") or "",
            "title": res.get("title") or "",
            "abstract": (res.get("abstractText") or "")[:1500],
            "year": res.get("pubYear") or "",
            "citedByCount": res.get("citedByCount") or 0,
            "authorString": res.get("authorString") or "",
        })
    try:
        cache_file.write_text(json.dumps(out), encoding="utf-8")
    except Exception:
        pass
    return out
