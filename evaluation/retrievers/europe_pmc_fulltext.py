"""
Europe PMC / NCBI EFetch full-text retrieval for LitQA2 source papers.

LitQA2 dataset rows contain a `sources` field with DOI URLs. We:
1. Resolve DOI → PMC ID via Europe PMC search
2. Fetch full-text XML via NCBI EFetch (more reliable than Europe PMC's
   fullTextXML endpoint, which returns 404 for many papers)
3. Strip XML tags to plain text
4. Find the section most relevant to the question (best-matching paragraph
   by simple keyword overlap; sufficient because we have the literal DOI
   of THE paper that contains the answer)
5. Cache results to disk to avoid hammering NCBI

This is "Path A" per the architectural-debts deep-dive.
"""
from __future__ import annotations

import hashlib
import json
import logging
import re
import time
from pathlib import Path
from typing import Optional, Tuple

import requests

logger = logging.getLogger(__name__)

CACHE_DIR = Path(__file__).parent.parent / "datasets" / "europe_pmc_cache"
CACHE_DIR.mkdir(parents=True, exist_ok=True)

_REQUEST_HEADERS = {
    "User-Agent": "BioMate-LitQA2-Retriever/1.0 (xiaoni5122@gmail.com)",
}


def _doi_from_url(url: str) -> Optional[str]:
    """Extract bare DOI from URL like 'https://doi.org/10.1128/msphere.00109-24'."""
    m = re.search(r"(?:doi\.org/|^)\s*(10\.\d{4,}/[^\s]+)$", url.strip())
    return m.group(1) if m else None


def _resolve_doi_to_pmcid(doi: str, timeout: int = 8) -> Optional[str]:
    """Use Europe PMC search to map DOI → PMC ID (e.g., 'PMC11237425')."""
    try:
        r = requests.get(
            "https://www.ebi.ac.uk/europepmc/webservices/rest/search",
            params={"query": f"DOI:{doi}", "format": "json", "resultType": "core"},
            headers=_REQUEST_HEADERS,
            timeout=timeout,
        )
        r.raise_for_status()
        results = r.json().get("resultList", {}).get("result", [])
        if not results:
            return None
        return results[0].get("pmcid") or None
    except Exception as exc:
        logger.debug("EuropePMC search failed for %s: %s", doi, exc)
        return None


def _fetch_fulltext_xml(pmcid: str, timeout: int = 20) -> Optional[str]:
    """Fetch full-text XML via NCBI EFetch (more reliable than EuropePMC endpoint)."""
    pmc_num = pmcid.replace("PMC", "")
    try:
        r = requests.get(
            "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi",
            params={"db": "pmc", "id": pmc_num, "rettype": "xml"},
            headers=_REQUEST_HEADERS,
            timeout=timeout,
        )
        if r.ok and len(r.text) > 500:
            return r.text
    except Exception as exc:
        logger.debug("NCBI EFetch PMC failed for %s: %s", pmcid, exc)
    return None


def _xml_to_paragraphs(xml: str) -> list[str]:
    """Crude XML → list of paragraph plain-text strings."""
    # Extract <p>...</p> contents
    paragraphs = re.findall(r"<p[^>]*>(.*?)</p>", xml, re.DOTALL)
    # Also include abstract <p>s (already captured by above) and <title>s
    titles = re.findall(r"<title[^>]*>(.*?)</title>", xml, re.DOTALL)
    out = []
    for raw in titles + paragraphs:
        # Strip remaining XML tags and decode common entities
        text = re.sub(r"<[^>]+>", "", raw)
        text = (text.replace("&amp;", "&").replace("&lt;", "<")
                    .replace("&gt;", ">").replace("&quot;", '"')
                    .replace("&#x2009;", " ").replace("&#x2010;", "-")
                    .replace("&#x00a0;", " "))
        text = re.sub(r"\s+", " ", text).strip()
        if text and len(text) > 30:
            out.append(text)
    return out


def _best_section_for_question(paragraphs: list[str], question: str,
                                 choices: Optional[list[str]] = None,
                                 max_chars: int = 2000) -> str:
    """
    Pick paragraphs most relevant to the question using keyword-overlap scoring.
    Returns concatenated paragraphs, capped at max_chars.

    Scoring (per paragraph):
      +1 per distinct question-token match (4+ chars, case-insensitive, non-stopword)
      +2 per capitalized question-token match (genes/species/proper-nouns)
      +5 per choice-entity match (e.g. "ciprofloxacin" when choices includes it) —
         heavily weighted because the answer paragraph almost always mentions the
         choice entities verbatim.
    """
    _STOP = {"the","a","an","is","are","was","were","what","which","how","when",
             "where","who","why","does","do","did","in","of","and","or","for","to","with",
             "that","this","from","by","as","at","be","been","has","have","had","not","no",
             "can","could","would","should","will","its","their","they","it","on","than",
             "into","about","after","study","shown","found","show","associated","between",
             "percent","percentage","following","question","cells","mice"}
    q_lower = question.lower()
    q_tokens = {w for w in re.findall(r"\b[a-zA-Z][a-zA-Z0-9-]{3,}\b", q_lower) if w not in _STOP}
    q_caps = {c.lower() for c in re.findall(r"\b[A-Z][a-zA-Z0-9-]{3,}\b", question)}
    # Choice-entity tokens (e.g., drug names): 4+ chars, case-insensitive
    choice_tokens = set()
    if choices:
        for ch in choices:
            for w in re.findall(r"\b[a-zA-Z][a-zA-Z0-9-]{3,}\b", ch):
                if w.lower() not in _STOP:
                    choice_tokens.add(w.lower())

    scored = []
    for p in paragraphs:
        p_lower = p.lower()
        score = 0
        for t in q_tokens:
            if t in p_lower: score += 1
        for t in q_caps:
            if t in p_lower: score += 2
        for t in choice_tokens:
            if t in p_lower: score += 5
        if score > 0:
            scored.append((score, p))

    scored.sort(key=lambda x: -x[0])
    chosen = []
    total = 0
    for score, p in scored:
        if total + len(p) > max_chars:
            chosen.append(p[:max_chars - total])
            break
        chosen.append(p)
        total += len(p)
    return "\n\n".join(chosen)


def fetch_relevant_passage(question: str, sources: list[str],
                            choices: Optional[list[str]] = None,
                            max_chars: int = 2000, timeout: int = 20) -> str:
    """
    Main entry point: given a LitQA2 question, its `sources` (DOI URLs), and the
    multiple-choice answer choices, return the most-relevant passage from the
    source paper(s), cached on disk.

    Returns "" if no DOI resolves to a PMC paper, or no relevant passage found.
    """
    if not sources:
        return ""

    for src in sources:
        doi = _doi_from_url(src) if isinstance(src, str) else None
        if not doi:
            continue

        # Cache key on (doi, question hash, choices hash) — choices affect scoring
        c_str = "|".join(sorted(choices or []))
        q_hash = hashlib.md5((question + c_str).encode("utf-8")).hexdigest()[:10]
        cache_file = CACHE_DIR / f"{doi.replace('/', '_')}_{q_hash}.txt"
        if cache_file.exists():
            return cache_file.read_text(encoding="utf-8")

        pmcid = _resolve_doi_to_pmcid(doi, timeout=timeout)
        if not pmcid:
            continue

        xml = _fetch_fulltext_xml(pmcid, timeout=timeout)
        if not xml:
            continue

        paragraphs = _xml_to_paragraphs(xml)
        if not paragraphs:
            continue

        passage = _best_section_for_question(paragraphs, question, choices=choices, max_chars=max_chars)
        if passage:
            cache_file.write_text(passage, encoding="utf-8")
            return passage

    return ""
