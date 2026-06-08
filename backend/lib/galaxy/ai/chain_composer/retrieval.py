"""Retrieval over patterns and curated chains.

Prototype uses simple token-overlap scoring with light biological synonym
expansion — no embedding model required to run. The interface matches what
a future BGE-backed retriever would expose, so the swap is one-function-call
away when we wire L2 into production.
"""

from __future__ import annotations

import json
import os
import re
import sqlite3
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Tuple

from .pattern_loader import Pattern, load_patterns


_DEFAULT_DB = Path(
    os.environ.get(
        "BIOMATE_AI_TOOLS_DB",
        Path(__file__).resolve().parents[4] / "database" / "galaxy_ai_tools.db",
    )
)

# Small synonym map — bio queries use these interchangeably and token-overlap
# would otherwise miss the connection. Keep tight; this is not a thesaurus.
_SYNONYMS: Dict[str, List[str]] = {
    "rna-seq": ["rnaseq", "rna", "transcriptomics", "expression"],
    "rna": ["rnaseq", "transcriptomics", "expression"],
    "atac-seq": ["atacseq", "atac", "chromatin", "accessibility"],
    "atac": ["atacseq", "chromatin"],
    "scrna": ["singlecell", "single-cell", "scrnaseq", "sc-rna"],
    "single-cell": ["scrna", "scrnaseq", "singlecell"],
    "multi-omics": ["multiomics", "multimodal", "integrative"],
    "multimodal": ["multiomics", "multi-omics"],
    "differential": ["de", "deg", "differentially-expressed"],
    "expression": ["transcriptomics", "rnaseq"],
    "enrichment": ["pathway", "ontology", "gsea", "go"],
    "pathway": ["enrichment", "kegg", "reactome", "gsea"],
    "variant": ["snv", "indel", "mutation", "vcf"],
    "drug": ["compound", "molecule", "ligand"],
    "screen": ["screening", "library", "panel"],
    "admet": ["pharmacokinetics", "tox", "absorption"],
    "consensus": ["ensemble", "vote", "intersect", "intersection"],
    "validate": ["validation", "confirm", "replicate"],
    "cohort": ["population", "dataset", "study"],
    "meta": ["meta-analysis", "metaanalysis", "pool"],
    "qc": ["quality", "filter", "outlier"],
    "cluster": ["clustering", "subpopulation", "sub-cluster"],
    "annotate": ["annotation", "label", "celltype"],
    "dose": ["dosing", "dose-response", "concentration"],
    "time": ["timecourse", "longitudinal", "temporal"],
}

_TOKEN_RE = re.compile(r"[a-z][a-z0-9-]*")


def _tokenize(text: str) -> List[str]:
    return _TOKEN_RE.findall((text or "").lower())


def _expand(tokens: Iterable[str]) -> set:
    out = set()
    for t in tokens:
        out.add(t)
        out.update(_SYNONYMS.get(t, []))
        # Stems: "differentiation" → "different", etc.
        if len(t) > 6:
            out.add(t[:6])
    return out


def _overlap_score(query_tokens: set, doc_tokens: set) -> float:
    """Jaccard-ish overlap, weighted by relative coverage of query tokens."""
    if not query_tokens or not doc_tokens:
        return 0.0
    hit = len(query_tokens & doc_tokens)
    if hit == 0:
        return 0.0
    # Coverage of the query — penalizes queries that share only stopwords.
    return hit / (len(query_tokens) ** 0.5)


@dataclass
class ScoredPattern:
    pattern: Pattern
    score: float


@dataclass
class ScoredChain:
    name: str
    display_name: str
    domain: str
    description: str
    steps: List[Dict]
    score: float


def retrieve_patterns(
    query: str,
    patterns: Optional[List[Pattern]] = None,
    top_k: int = 3,
) -> List[ScoredPattern]:
    """Return up to top_k patterns most relevant to the query."""
    patterns = patterns if patterns is not None else load_patterns()
    if not patterns:
        return []
    q_tokens = _expand(_tokenize(query))
    scored: List[ScoredPattern] = []
    for p in patterns:
        d_tokens = _expand(_tokenize(p.search_text()))
        s = _overlap_score(q_tokens, d_tokens)
        if s > 0:
            scored.append(ScoredPattern(pattern=p, score=s))
    scored.sort(key=lambda x: x.score, reverse=True)
    return scored[:top_k]


def retrieve_curated_chains(
    query: str,
    db_path: Optional[Path] = None,
    top_k: int = 3,
) -> List[ScoredChain]:
    """Return top_k curated chains for similarity-as-exemplars purposes.

    Filters out `bioc_reactive` chains — those are post-completion suggestions,
    not upfront exemplars (matches the intent_hint=true filter in production).
    """
    db_path = db_path or _DEFAULT_DB
    if not db_path.exists():
        return []
    q_tokens = _expand(_tokenize(query))
    conn = sqlite3.connect(str(db_path))
    try:
        rows = conn.execute(
            "SELECT name, display_name, domain, description, steps "
            "FROM workflow_chains "
            "WHERE source IS NULL OR source != 'bioc_reactive'"
        ).fetchall()
    finally:
        conn.close()

    scored: List[ScoredChain] = []
    for name, display_name, domain, description, steps_json in rows:
        try:
            steps = json.loads(steps_json or "[]")
        except Exception:
            steps = []
        doc_text = " ".join(filter(None, [name, display_name, domain, description]))
        d_tokens = _expand(_tokenize(doc_text))
        s = _overlap_score(q_tokens, d_tokens)
        if s > 0:
            scored.append(
                ScoredChain(
                    name=name,
                    display_name=display_name or name,
                    domain=domain or "",
                    description=description or "",
                    steps=steps,
                    score=s,
                )
            )
    scored.sort(key=lambda x: x.score, reverse=True)
    return scored[:top_k]
