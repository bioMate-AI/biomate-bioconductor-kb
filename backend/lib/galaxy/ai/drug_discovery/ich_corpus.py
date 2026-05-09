"""
ICH Guideline Corpus — BM25 retrieval for citation verification.

Indexes the ICH/FDA/EMA PDF guidelines in data/regulatory_training/ich_guidelines/
using BM25 (rank_bm25). Used by _regulatory_guardrails() in ind_assembly.py to
verify that cited guidelines actually cover the adjacent regulatory claim.

No GPU required — pure BM25 text retrieval.

Usage:
    corpus = ICHCorpus()
    result = corpus.verify_citation("ICH S2(R1)", claim_text)
    # result.grounded: True if claim is supported by the guideline
    # result.score: BM25 similarity score (higher = more grounded)
    # result.top_chunk: most relevant guideline excerpt
"""
from __future__ import annotations

import logging
import os
import re
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path
from typing import Optional

log = logging.getLogger(__name__)

# Map citation IDs to their PDF filenames
_GUIDELINE_FILES: dict[str, str] = {
    "ICH S2(R1)":              "ICH_S2_R1.pdf",
    "S2(R1)":                  "ICH_S2_R1.pdf",
    "ICH S2":                  "ICH_S2_R1.pdf",
    "ICH S7A":                 "ICH_S7A.pdf",
    "ICH S7B":                 "ICH_S7B.pdf",
    "S7B":                     "ICH_S7B.pdf",
    "ICH M3(R2)":              "ICH_M3_R2.pdf",
    "ICH M3":                  "ICH_M3_R2.pdf",
    "ICH M4S(R2)":             "ICH_M4S_R2.pdf",
    "ICH M4S":                 "ICH_M4S_R2.pdf",
    "ICH S1A":                 "ICH_S1A.pdf",
    "ICH S1B":                 "ICH_S1B.pdf",
    "ICH S1C(R2)":             "ICH_S1C_R2.pdf",
    "ICH S5(R3)":              "ICH_S5_R3.pdf",
    "ICH S6(R1)":              "ICH_S6_R1.pdf",
    "ICH S8":                  "ICH_S8.pdf",
    "ICH S9":                  "ICH_S9.pdf",
    "ICH M7(R2)":              "ICH_M7_R2.pdf",
    "ICH M7":                  "ICH_M7_R2.pdf",
    "ICH E5":                  "ICH_E5_R1.pdf",
    "ICH E7":                  "ICH_E7.pdf",
    "EMA/CHMP/EWP/37498/2011": "EMA_PBPK.pdf",
    "EMA PBPK":                "EMA_PBPK.pdf",
}

# Terms that, if present in a claim, strongly signal the claim is about genotoxicity
_DOMAIN_KEYWORDS: dict[str, list[str]] = {
    "ICH S2(R1)": ["ames", "bacterial reverse mutation", "micronucleus",
                   "chromosomal aberration", "genotox", "mutagenic",
                   "clastogenic", "in vitro", "in vivo"],
    "ICH S7B":    ["herg", "ikr", "qt", "cardiac", "patch clamp", "ic50",
                   "channel", "electrophysiol"],
    "ICH S7A":    ["safety pharmacology", "cns", "respiratory", "cardiovascular",
                   "fob", "functional observational"],
    "ICH M3(R2)": ["phase i", "first-in-human", "duration", "phase-appropriate",
                   "timing", "repeat-dose"],
    "EMA/CHMP/EWP/37498/2011": ["pbpk", "within 2-fold", "67%", "aafe",
                                  "physiologically based", "pharmacokinetic model"],
}

_ICH_DIR = Path(__file__).parent.parent.parent.parent.parent.parent / \
    "data" / "regulatory_training" / "ich_guidelines" / "raw" / "ich"

_CITATION_EXTRACT_RE_LOCAL = re.compile(
    r"(?:ICH\s+[A-Z]\d+(?:\([A-Z]\d*\))?(?:/R\d+)?|"
    r"EMA/CHMP/EWP/\d+/\d+|"
    r"21\s+CFR\s+Part\s+\d+|"
    r"S\d+\([A-Z]\d*\)|"
    r"NMPA\s+(?:Announcement|Guideline)|"
    r"PMDA\s+Notification)",
    re.I,
)


def _extract_citations_local(text: str) -> list[str]:
    return _CITATION_EXTRACT_RE_LOCAL.findall(text)


@dataclass
class VerificationResult:
    grounded: bool          # True if claim appears supported by guideline
    score: float            # BM25 similarity (0–1 normalized)
    top_chunk: str          # Most relevant guideline excerpt
    method: str             # "bm25", "keyword", or "unavailable"
    citation: str
    claim_preview: str


class ICHCorpus:
    """BM25-indexed ICH guideline corpus for citation verification."""

    def __init__(self, ich_dir: Optional[Path] = None):
        self._dir = ich_dir or _ICH_DIR
        self._index: dict[str, list[str]] = {}  # citation_id → chunks
        self._bm25: dict[str, object] = {}      # citation_id → BM25Okapi

    def _load_guideline(self, citation: str) -> list[str]:
        """Load and chunk one guideline PDF into 200-word chunks."""
        if citation in self._index:
            return self._index[citation]

        # Find the right file
        fname = _GUIDELINE_FILES.get(citation)
        if not fname:
            # Try fuzzy match on the citation keys
            for key, f in _GUIDELINE_FILES.items():
                if citation.lower().replace(" ", "") in key.lower().replace(" ", ""):
                    fname = f
                    break
        if not fname:
            log.debug("No guideline file for citation %r", citation)
            self._index[citation] = []
            return []

        pdf_path = self._dir / fname
        if not pdf_path.exists():
            log.debug("Guideline PDF not found: %s", pdf_path)
            self._index[citation] = []
            return []

        try:
            import fitz
            doc = fitz.open(str(pdf_path))
            full_text = " ".join(page.get_text() for page in doc)
            doc.close()
        except ImportError:
            log.warning("PyMuPDF not available — citation verification disabled")
            self._index[citation] = []
            return []
        except Exception as e:
            log.warning("Failed to load %s: %s", pdf_path, e)
            self._index[citation] = []
            return []

        # Split into 200-word chunks with 50-word overlap
        words = full_text.split()
        chunks = []
        step = 150
        size = 200
        for i in range(0, len(words), step):
            chunk = " ".join(words[i:i + size])
            if len(chunk.split()) >= 30:
                chunks.append(chunk)

        self._index[citation] = chunks
        log.debug("Loaded %d chunks for %s", len(chunks), citation)
        return chunks

    def _get_bm25(self, citation: str):
        """Lazy-load BM25 index for one guideline."""
        if citation in self._bm25:
            return self._bm25[citation]

        chunks = self._load_guideline(citation)
        if not chunks:
            return None

        try:
            from rank_bm25 import BM25Okapi
            tokenized = [c.lower().split() for c in chunks]
            bm25 = BM25Okapi(tokenized)
            self._bm25[citation] = bm25
            return bm25
        except ImportError:
            log.warning("rank_bm25 not installed — using keyword fallback")
            return None

    def verify_citation(self, citation: str, claim_text: str,
                        threshold: float = 0.15) -> VerificationResult:
        """
        Verify that claim_text is grounded in the cited guideline.

        Args:
            citation: e.g. "ICH S2(R1)"
            claim_text: the sentence/paragraph citing this guideline
            threshold: BM25 score below which we flag as potentially ungrounded

        Returns:
            VerificationResult
        """
        claim_preview = claim_text[:100].strip()

        # Fast keyword check first — if domain keywords present, likely grounded
        domain_kws = _DOMAIN_KEYWORDS.get(citation, [])
        claim_lower = claim_text.lower()
        keyword_hits = sum(1 for kw in domain_kws if kw in claim_lower)
        if keyword_hits >= 2:
            return VerificationResult(
                grounded=True, score=1.0, top_chunk="",
                method="keyword", citation=citation, claim_preview=claim_preview,
            )

        # BM25 retrieval
        chunks = self._load_guideline(citation)
        if not chunks:
            return VerificationResult(
                grounded=True, score=0.5, top_chunk="",
                method="unavailable", citation=citation, claim_preview=claim_preview,
            )

        bm25 = self._get_bm25(citation)
        if bm25 is None:
            # Fallback: keyword count in raw chunks
            query_words = set(claim_text.lower().split())
            best_overlap = max(
                len(query_words & set(chunk.lower().split())) / max(len(query_words), 1)
                for chunk in chunks
            )
            return VerificationResult(
                grounded=best_overlap >= threshold,
                score=best_overlap,
                top_chunk=chunks[0][:200] if chunks else "",
                method="keyword_overlap",
                citation=citation,
                claim_preview=claim_preview,
            )

        import numpy as np
        query_tokens = claim_text.lower().split()
        scores = bm25.get_scores(query_tokens)
        best_idx = int(np.argmax(scores))
        best_score = float(scores[best_idx])
        max_possible = float(np.max(bm25.get_scores(chunks[best_idx].lower().split()))) if chunks else 1.0
        normalized = best_score / max(max_possible, 1e-6)

        return VerificationResult(
            grounded=normalized >= threshold,
            score=normalized,
            top_chunk=chunks[best_idx][:300],
            method="bm25",
            citation=citation,
            claim_preview=claim_preview,
        )

    def verify_all_citations(self, text: str, section_type: str) -> list[VerificationResult]:
        """Extract all citations from text and verify each against its guideline."""
        citations = _extract_citations_local(text)
        results = []
        for cite in set(citations):
            # Find the sentence containing this citation
            idx = text.lower().find(cite.lower())
            if idx == -1:
                continue
            start = max(0, text.rfind(".", 0, idx) + 1)
            end = text.find(".", idx)
            if end == -1:
                end = min(len(text), idx + 300)
            claim = text[start:end].strip()
            results.append(self.verify_citation(cite, claim))
        return results


@lru_cache(maxsize=1)
def get_ich_corpus() -> ICHCorpus:
    """Singleton ICH corpus instance."""
    return ICHCorpus()
