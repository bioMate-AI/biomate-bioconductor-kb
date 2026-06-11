"""Retrieval over patterns and curated chains.

Uses BM25 (Okapi BM25, pure Python, no deps) with light biological-synonym
expansion, plus an optional entity-overlap boost when query entities are
provided. The interface matches what a future BGE-backed retriever would
expose, so the swap is one-function-call away when we wire L2 into production.
"""

from __future__ import annotations

import json
import math
import os
import re
import sqlite3
from collections import Counter
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Sequence, Set, Tuple

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
    """Jaccard-ish overlap, weighted by relative coverage of query tokens.

    Kept for backward compat / unit tests. New scorers use BM25 below.
    """
    if not query_tokens or not doc_tokens:
        return 0.0
    hit = len(query_tokens & doc_tokens)
    if hit == 0:
        return 0.0
    return hit / (len(query_tokens) ** 0.5)


# Common English/biology stopwords. Keep tight — over-pruning kills recall.
_STOPWORDS = frozenset({
    "a", "an", "the", "of", "for", "and", "or", "to", "in", "on", "at",
    "is", "are", "was", "were", "be", "with", "from", "by", "as", "this",
    "that", "it", "do", "i", "we", "you", "want", "need", "would", "like",
    "into", "via", "then", "next", "some", "any", "all", "my", "our",
    "data", "analysis", "study", "samples",
})


def _tokenize_bm25(text: str) -> List[str]:
    """Tokens for BM25 — same as _tokenize but stopword-filtered."""
    return [t for t in _tokenize(text) if t not in _STOPWORDS]


def _bm25_score(
    query_terms: Sequence[str],
    doc_terms: Sequence[str],
    avgdl: float,
    df: Dict[str, int],
    n_docs: int,
    k1: float = 1.5,
    b: float = 0.75,
) -> float:
    """Okapi BM25. Standard parameters. Returns a non-negative score."""
    if not query_terms or not doc_terms:
        return 0.0
    tf = Counter(doc_terms)
    dl = len(doc_terms)
    score = 0.0
    for q in set(query_terms):
        n_q = df.get(q, 0)
        if n_q == 0:
            continue
        # idf with the +0.5 smoothing variant; max(0, ...) avoids negatives for very common terms.
        idf = max(0.0, math.log((n_docs - n_q + 0.5) / (n_q + 0.5) + 1.0))
        f = tf.get(q, 0)
        if f == 0:
            continue
        denom = f + k1 * (1 - b + b * dl / max(avgdl, 1.0))
        score += idf * (f * (k1 + 1.0)) / denom
    return score


@dataclass
class _BM25Index:
    """Pre-tokenized + expanded docs ready for BM25 scoring."""
    docs: List[Tuple[str, List[str]]]  # (doc_id, terms)
    df: Dict[str, int]
    avgdl: float

    @classmethod
    def build(cls, docs: List[Tuple[str, str]]) -> "_BM25Index":
        """Build index from `(doc_id, raw_text)` pairs."""
        out_docs: List[Tuple[str, List[str]]] = []
        df: Dict[str, int] = {}
        total = 0
        for did, text in docs:
            terms = list(_expand(_tokenize_bm25(text)))
            out_docs.append((did, terms))
            total += len(terms)
            for t in set(terms):
                df[t] = df.get(t, 0) + 1
        avgdl = total / max(len(out_docs), 1)
        return cls(docs=out_docs, df=df, avgdl=avgdl)

    def score_all(self, query_terms: List[str]) -> List[Tuple[str, float]]:
        n = len(self.docs)
        scored: List[Tuple[str, float]] = []
        for did, dterms in self.docs:
            s = _bm25_score(query_terms, dterms, self.avgdl, self.df, n)
            scored.append((did, s))
        return scored


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


@dataclass
class ScoredWorkflow:
    name: str
    domain: str
    description: str
    score: float


def _entity_boost(doc_text: str, entity_terms: Sequence[str]) -> float:
    """Each entity term found verbatim (lowercased substring) → +0.5 boost.
    Bounded so entities can't dominate completely — keep retrieval grounded
    in textual relevance.
    """
    if not entity_terms:
        return 0.0
    text = (doc_text or "").lower()
    hits = sum(1 for e in entity_terms if e and e in text)
    return min(3.0, 0.5 * hits)


def retrieve_patterns(
    query: str,
    patterns: Optional[List[Pattern]] = None,
    top_k: int = 3,
    entity_terms: Optional[Sequence[str]] = None,
) -> List[ScoredPattern]:
    """Return up to top_k patterns most relevant to the query.

    Uses BM25 over the pattern's `name + when + pitfall` text. When
    `entity_terms` (from NER) are provided, adds a small boost for verbatim
    matches in the same text.
    """
    patterns = patterns if patterns is not None else load_patterns()
    if not patterns:
        return []

    index = _BM25Index.build([(p.name, p.search_text()) for p in patterns])
    q_terms = list(_expand(_tokenize_bm25(query)))
    scored_raw = index.score_all(q_terms)
    by_name = {p.name: p for p in patterns}

    scored: List[ScoredPattern] = []
    for name, base in scored_raw:
        boost = _entity_boost(by_name[name].search_text(), entity_terms or [])
        total = base + boost
        if total > 0:
            scored.append(ScoredPattern(pattern=by_name[name], score=total))
    scored.sort(key=lambda x: x.score, reverse=True)
    return scored[:top_k]


# ─────────────────────────────────────────────────────────────────────────
# Workflow catalog retrieval (top-K candidate workflow names for the LLM).
#
# The catalog has ~3K rows; building the BM25 index every call wastes ~50ms.
# Cache the index keyed on (db_path, mtime) so concurrent prototype calls
# reuse the same index but a refreshed DB invalidates correctly.
# ─────────────────────────────────────────────────────────────────────────

_WF_INDEX_CACHE: Dict[Tuple[str, float], Tuple["_BM25Index", Dict[str, "ScoredWorkflow"]]] = {}

# Type-flow adjacency cache keyed on the same (db_path, mtime) tuple.
# Built lazily on first call to retrieve_downstream_via_types().
_TYPEFLOW_CACHE: Dict[Tuple[str, float], Dict[str, List[str]]] = {}


# Regex patterns for canonical input tokens hiding inside Bioc's freeform
# input_types descriptions. Keeps the type-flow graph from missing the
# entire Bioc-consumer subspace (where input_types is prose, not flat tokens).
_BIOC_INPUT_PATTERNS = [
    (re.compile(r"\bcounts?\b.*\bmatrix\b|\braw\s+counts?\b|counts?\.(?:tsv|csv|txt)", re.I), "counts_matrix"),
    (re.compile(r"\bexpression\s+matrix\b|\bexpressionset\b|\bnormalized\s+expression", re.I), "expression_matrix"),
    (re.compile(r"\bsingle\s*cell\s+experiment\b|\bsingle\s*-?\s*cell\b|\bsce\s+object\b|\bh5ad\b", re.I), "singlecellexperiment"),
    (re.compile(r"\bseurat\s+object\b", re.I), "seurat_object"),
    (re.compile(r"\bsummarizedexperiment\b|\bSE\s+object\b", re.I), "summarizedexperiment"),
    (re.compile(r"\bvcf\b|\bvariant\s+call", re.I), "vcf"),
    (re.compile(r"\bbam\b|\baligned\s+(?:reads|bam)\b", re.I), "bam"),
    (re.compile(r"\bfasta\b|\bgenome\s+sequence\b", re.I), "fasta"),
    (re.compile(r"\bgwas\b|\bsummary\s+statistics\b|\bassociation\s+test", re.I), "gwas_summary_statistics"),
    (re.compile(r"\bgene\s+list\b|\bDEGs?\b|\bsignificant\s+genes\b", re.I), "gene_list"),
    (re.compile(r"\bmicroarray\b|\baffymetrix\b|\baffybatch\b|\bcel\s+file", re.I), "expression_matrix"),
]

# Cross-edges for new Bioc-flavored output kinds → likely downstream input
# kinds. Extends the existing _PLANNER_ALIASES at the type-flow layer.
_TYPEFLOW_OUT_ALIASES = {
    "de_table":              ["de_table", "gene_list", "differential_expression"],
    "expression_matrix":     ["expression_matrix", "counts_matrix"],
    "counts_matrix":         ["counts_matrix", "counts"],
    "summarizedexperiment":  ["summarizedexperiment", "se"],
    "singlecellexperiment":  ["singlecellexperiment", "sce", "h5ad"],
    "enrichment_results":    ["enrichment_results", "gene_list"],
    "pathway_results":       ["pathway_results"],
    "gwas_summary_statistics": ["gwas_summary_statistics"],
    "copy_number_segments":  ["copy_number_segments"],
    "mutational_signatures": ["mutational_signatures"],
    "normalized_data":       ["normalized_data"],
    "cluster_assignments":   ["cluster_assignments"],
    "vcf":                   ["vcf"],
    "annotated_vcf":         ["annotated_vcf", "vcf"],
}


def _canonical_inputs_from_freeform(raw: List[Any]) -> List[str]:
    """Extract canonical input-type tokens from a workflow's input_types list,
    including freeform Bioc descriptions like "counts.tsv (matrix of raw...)"."""
    out = set()
    for t in raw:
        if not isinstance(t, str):
            continue
        s = t.strip()
        if not s:
            continue
        # Direct canonical hit
        if len(s) < 35 and "(" not in s:
            out.add(s.lower())
            continue
        # Freeform — pattern-match
        for pat, label in _BIOC_INPUT_PATTERNS:
            if pat.search(s):
                out.add(label)
    return sorted(out)


def _load_typeflow_adjacency(db_path: Path) -> Dict[str, List[str]]:
    """Build a workflow → downstream-consumers adjacency map via typed edges.

    Returns {source_workflow_name: [downstream_workflow_name, ...]}. Cached
    on (db_path, mtime) — same invalidation policy as the workflow index.

    Only workflows with both real output_types AND extractable canonical
    inputs participate. Excludes:
    - empty/null typed I/O
    - Bioc stub outputs (table/csv + plot/pdf + object/rds with no other kinds)
    """
    key = (str(db_path), db_path.stat().st_mtime)
    cached = _TYPEFLOW_CACHE.get(key)
    if cached is not None:
        return cached

    conn = sqlite3.connect(str(db_path))
    try:
        rows = conn.execute(
            "SELECT name, input_types, output_types "
            "FROM workflows WHERE executable=1 "
            "AND input_types NOT IN ('','[]') AND output_types NOT IN ('','[]')"
        ).fetchall()
    finally:
        conn.close()

    bioc_stub = sorted(["table/csv", "plot/pdf", "object/rds"])
    nodes: Dict[str, Dict[str, List[str]]] = {}
    for name, in_raw, out_raw in rows:
        try:
            ins_raw = json.loads(in_raw or "[]")
            outs_raw = json.loads(out_raw or "[]")
        except Exception:
            continue
        # Skip pure-stub Bioc rows that haven't been re-inferred
        outs_clean = [t for t in outs_raw if isinstance(t, str) and len(t) < 35 and "(" not in t]
        if not outs_clean or sorted(outs_clean) == bioc_stub:
            continue
        ins_canonical = _canonical_inputs_from_freeform(ins_raw)
        if not ins_canonical:
            continue
        nodes[name] = {"ins": ins_canonical, "outs": [o.lower() for o in outs_clean]}

    # Build input-token → workflows index
    by_input: Dict[str, List[str]] = {}
    for name, info in nodes.items():
        for t in info["ins"]:
            by_input.setdefault(t, []).append(name)

    # Build adjacency: src → [dst...] when any of src.outs satisfies any of dst.ins.
    # First pass: collect raw adjacency. Second pass: rank downstream by their
    # total in-degree (workflows that consume the most upstream are most
    # broadly applicable — surface them first in the prompt).
    raw_adj: Dict[str, Set[str]] = {}
    for src_name, src in nodes.items():
        downstream_set: Set[str] = set()
        for o in src["outs"]:
            for cand in [o] + _TYPEFLOW_OUT_ALIASES.get(o, []):
                downstream_set.update(by_input.get(cand, []))
        downstream_set.discard(src_name)
        if downstream_set:
            raw_adj[src_name] = downstream_set

    # Compute global in-degree across the graph for ranking
    in_degree: Dict[str, int] = {}
    for src_name, dsts in raw_adj.items():
        for d in dsts:
            in_degree[d] = in_degree.get(d, 0) + 1

    # Rank each adjacency list by (in_degree desc, name asc) so popular
    # consumers surface first but the order stays deterministic.
    adjacency: Dict[str, List[str]] = {}
    for src_name, dsts in raw_adj.items():
        adjacency[src_name] = sorted(
            dsts, key=lambda n: (-in_degree.get(n, 0), n)
        )

    _TYPEFLOW_CACHE[key] = adjacency
    return adjacency


def retrieve_downstream_via_types(
    upstream_workflow_names: Sequence[str],
    db_path: Optional[Path] = None,
    top_k: int = 5,
) -> Dict[str, List[str]]:
    """For each upstream workflow name, return up to top_k downstream consumers
    reachable via canonical typed edges. Empty list when no typed downstream
    exists in the graph.

    Returns a dict: {upstream_name: [downstream_name, ...]} preserving order
    of the input list, dropping upstream names not in the type-flow graph.

    Used by the composer to surface natural-chain options to the LLM at
    prompt-construction time.
    """
    db_path = db_path or _DEFAULT_DB
    if not db_path.exists():
        return {}
    adj = _load_typeflow_adjacency(db_path)
    out: Dict[str, List[str]] = {}
    for name in upstream_workflow_names:
        downstream = adj.get(name)
        if downstream:
            out[name] = downstream[:top_k]
    return out


def _extract_v2_signal(annotation_v2: str) -> str:
    """Extract just the high-signal portions of annotation_v2 for retrieval.

    Returns a concatenation of:
    - the `alternatives` field's named tools (multi_method_consensus tokens)
    - the first short fragment of `when_to_use` (semantic-intent phrase)

    Skips `key_parameters` (jargon-heavy) and `pitfalls` (failure-mode prose)
    which add noise to BM25 ranking without changing the topical signal.
    """
    if not annotation_v2:
        return ""
    parts = []
    # alternatives names — these are explicit substitution tokens
    m = re.search(r"^- alternatives: (.+?)(?=\n- |\Z)", annotation_v2, re.MULTILINE | re.DOTALL)
    if m:
        # Names live before "=" markers in "Name=description ;; Name2=desc2"
        chunks = re.split(r";;|;", m.group(1))
        for chunk in chunks:
            lhs = chunk.split("=", 1)[0].strip()
            if lhs and len(lhs) <= 60:
                parts.append(lhs)
    # when_to_use — semantic intent (cap to 200 chars to avoid prose noise)
    m = re.search(r"^- when_to_use: (.+?)(?=\n- |\Z)", annotation_v2, re.MULTILINE | re.DOTALL)
    if m:
        parts.append(m.group(1)[:200])
    return " ".join(parts)


def _load_workflow_index(db_path: Path) -> Tuple["_BM25Index", Dict[str, "ScoredWorkflow"]]:
    """Return (index, by_name) for the workflow catalog, cached on mtime."""
    key = (str(db_path), db_path.stat().st_mtime)
    cached = _WF_INDEX_CACHE.get(key)
    if cached is not None:
        return cached

    conn = sqlite3.connect(str(db_path))
    try:
        rows = conn.execute(
            "SELECT name, COALESCE(domain,''), COALESCE(description,''), "
            "       COALESCE(tools_used,''), COALESCE(annotation,''), "
            "       COALESCE(annotation_v2,'') "
            "FROM workflows WHERE executable=1 AND name IS NOT NULL"
        ).fetchall()
    finally:
        conn.close()

    by_name: Dict[str, ScoredWorkflow] = {}
    docs: List[Tuple[str, str]] = []
    for name, domain, description, tools_used, annotation, annotation_v2 in rows:
        # Compose the searchable text. tools_used is a JSON array; annotation
        # is often the package's full description — useful for Bioc retrieval.
        try:
            tools = json.loads(tools_used or "[]")
            tools_text = " ".join(t for t in tools if isinstance(t, str))
        except Exception:
            tools_text = ""
        # Annotation can be very long (1-2 paragraphs for Bioc); cap to keep
        # BM25 dl reasonable. The first ~400 chars carry the topical signal.
        annotation = (annotation or "")[:400]
        # Extract just the HIGH-SIGNAL portions of annotation_v2:
        # - alternatives: the substitution-cluster member names (e.g.
        #   "edgeR, limma, DSS, EBSeq, baySeq" — multi_method_consensus tokens)
        # - when_to_use: short semantic-intent phrase
        # Skip key_parameters (jargon-heavy) and pitfalls (failure-mode prose).
        v2_signal = _extract_v2_signal(annotation_v2)
        doc_text = " ".join(filter(None, [name, domain, description, tools_text, annotation, v2_signal]))
        by_name[name] = ScoredWorkflow(
            name=name,
            domain=domain or "",
            description=description or "",
            score=0.0,
        )
        docs.append((name, doc_text))

    index = _BM25Index.build(docs)
    _WF_INDEX_CACHE[key] = (index, by_name)
    return index, by_name


def retrieve_workflows(
    query: str,
    db_path: Optional[Path] = None,
    top_k: int = 8,
    entity_terms: Optional[Sequence[str]] = None,
) -> List[ScoredWorkflow]:
    """Return top_k workflows most relevant to the query.

    Uses BM25 over (name + domain + description + tools + annotation) with
    optional entity-overlap boost. Cached per DB mtime so the prototype CLI
    doesn't rebuild the 3K-row index on every call.
    """
    db_path = db_path or _DEFAULT_DB
    if not db_path.exists():
        return []

    index, by_name = _load_workflow_index(db_path)
    q_terms = list(_expand(_tokenize_bm25(query)))
    scored_raw = index.score_all(q_terms)

    # Build the entity-boost text lookup from the same docs.
    # (We rebuilt the docs list inside _load_workflow_index; pull from cache.)
    # Simpler: re-derive doc text by joining the ScoredWorkflow fields.
    out: List[ScoredWorkflow] = []
    for name, base in scored_raw:
        wf = by_name[name]
        doc_text = " ".join(filter(None, [wf.name, wf.domain, wf.description]))
        boost = _entity_boost(doc_text, entity_terms or [])
        total = base + boost
        if total > 0:
            # Cloning so per-call mutation doesn't pollute the cache.
            out.append(
                ScoredWorkflow(
                    name=wf.name,
                    domain=wf.domain,
                    description=wf.description,
                    score=total,
                )
            )
    out.sort(key=lambda x: x.score, reverse=True)
    return out[:top_k]


def _load_proposed_chains() -> List[tuple]:
    """Load JSON chain files from chain_composer/proposed_chains/ when
    BIOMATE_INCLUDE_PROPOSED_CHAINS=1. Returns rows in the same shape as
    `workflow_chains` SELECT so they can be merged in retrieve_curated_chains.

    Used to measure the calibration impact of proposed chains BEFORE
    committing them to the live DB.
    """
    if not os.environ.get("BIOMATE_INCLUDE_PROPOSED_CHAINS"):
        return []
    proposed_dir = Path(__file__).resolve().parent / "proposed_chains"
    if not proposed_dir.exists():
        return []
    rows = []
    for f in sorted(proposed_dir.glob("*.json")):
        try:
            data = json.loads(f.read_text(encoding="utf-8"))
        except Exception:
            continue
        rows.append((
            data.get("name", f.stem),
            data.get("display_name", ""),
            data.get("domain", ""),
            data.get("description", ""),
            json.dumps(data.get("example_queries", [])),
            json.dumps(data.get("steps", [])),
        ))
    return rows


def retrieve_curated_chains(
    query: str,
    db_path: Optional[Path] = None,
    top_k: int = 3,
    entity_terms: Optional[Sequence[str]] = None,
) -> List[ScoredChain]:
    """Return top_k curated chains as exemplars.

    Filters out `bioc_reactive` chains — those are post-completion suggestions,
    not upfront exemplars (matches the intent_hint=true filter in production).
    Uses BM25 + entity boost.

    When BIOMATE_INCLUDE_PROPOSED_CHAINS=1, also includes any JSON files
    under `proposed_chains/` so we can measure their impact before committing.
    """
    db_path = db_path or _DEFAULT_DB
    if not db_path.exists():
        return []

    conn = sqlite3.connect(str(db_path))
    try:
        rows = conn.execute(
            "SELECT name, display_name, domain, description, example_queries, steps "
            "FROM workflow_chains "
            "WHERE source IS NULL OR source != 'bioc_reactive'"
        ).fetchall()
    finally:
        conn.close()
    rows = list(rows) + _load_proposed_chains()

    # Cache parsed rows so we can look them up by name after BM25.
    cache: Dict[str, ScoredChain] = {}
    docs: List[Tuple[str, str]] = []
    for name, display_name, domain, description, example_queries, steps_json in rows:
        try:
            steps = json.loads(steps_json or "[]")
        except Exception:
            steps = []
        try:
            examples = json.loads(example_queries or "[]")
            example_text = " ".join(examples) if isinstance(examples, list) else ""
        except Exception:
            example_text = ""
        doc_text = " ".join(filter(None, [name, display_name, domain, description, example_text]))
        cache[name] = ScoredChain(
            name=name,
            display_name=display_name or name,
            domain=domain or "",
            description=description or "",
            steps=steps,
            score=0.0,
        )
        docs.append((name, doc_text))

    index = _BM25Index.build(docs)
    q_terms = list(_expand(_tokenize_bm25(query)))
    scored_raw = index.score_all(q_terms)

    scored: List[ScoredChain] = []
    for name, base in scored_raw:
        # Re-derive doc text for the entity boost.
        doc_text = next((t for n, t in docs if n == name), "")
        boost = _entity_boost(doc_text, entity_terms or [])
        total = base + boost
        if total > 0:
            sc = cache[name]
            sc.score = total
            scored.append(sc)
    scored.sort(key=lambda x: x.score, reverse=True)
    return scored[:top_k]
