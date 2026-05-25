"""
Tool-catalog retriever — 3-level (suite → function → wrapper) interface to
the canonical tool DB built by `scripts/build_canonical_db.py`.

Three public entry points designed to be exposed as Anthropic-shape tool
schemas (see `retrievers/tools.py`):

  search_tool_suites(query, top_k=10, category=None)
      → list[{suite_id, display_name, description, top_category,
              wrapper_count, function_count, score}]

  list_functions(suite_id, top_k=50)
      → list[{function_id, display_name, wrapper_count}]

  resolve_wrapper(suite_id, function_id=None, platform_preference=None)
      → {wrapper_tool_id, suite_id, function_id, confidence}
        or None

All read-only against `output/tool_canonical.db`. Stdlib only.
"""
from __future__ import annotations

import logging
import os
import re
import sqlite3
from pathlib import Path
from typing import Any, Dict, List, Optional

logger = logging.getLogger(__name__)

_DEFAULT_DB = Path(__file__).resolve().parents[1] / "output" / "tool_canonical.db"
_DB_PATH = Path(os.environ.get("BIOMATE_TOOL_CANONICAL_DB", _DEFAULT_DB))


def _connect() -> sqlite3.Connection:
    if not _DB_PATH.exists():
        raise FileNotFoundError(
            f"Canonical tool DB not found at {_DB_PATH}. "
            f"Run `python -m sandbox.retrieval_v2.scripts.build_canonical_db` first."
        )
    conn = sqlite3.connect(f"file:{_DB_PATH}?mode=ro", uri=True)
    conn.row_factory = sqlite3.Row
    return conn


_FTS_SAFE_PAT = re.compile(r"[^a-zA-Z0-9_ ]+")


def _fts_query(query: str) -> str:
    """Sanitize a free-text query for FTS5 MATCH.

    FTS5 reserves operators like AND/OR/NOT and special characters including
    hyphens (which it treats as NOT). We strip non-alphanumeric chars to
    space, drop tiny tokens, and OR the rest together.
    """
    # Replace ALL non-alphanumeric (including hyphens, which FTS5 treats as
    # NOT-operator) with space. Underscores stay (used in our suite_ids).
    cleaned = _FTS_SAFE_PAT.sub(" ", query or "").strip()
    tokens = [t for t in cleaned.split() if len(t) >= 2]
    if not tokens:
        return '""'
    if len(tokens) == 1:
        return tokens[0]
    # OR-join so any term match counts; BM25 ranks by overall relevance
    return " OR ".join(tokens)


def search_tool_suites(query: str, top_k: int = 10,
                        category: Optional[str] = None) -> List[Dict[str, Any]]:
    """
    Search canonical tool suites by free-text query.

    Returns up to `top_k` suite records ranked by FTS5 BM25 relevance. Pass
    `category` to filter (e.g. "RNA", "Variant Analysis", "Metagenomics").
    """
    if not query or not query.strip():
        return []

    fts_q = _fts_query(query)
    sql = """
        SELECT s.suite_id, s.display_name, s.description, s.top_category,
               s.edam_operation, s.wrapper_count, s.function_count,
               bm25(suites_fts) AS bm25_score
        FROM suites_fts
        JOIN tool_suites s USING(suite_id)
        WHERE suites_fts MATCH ?
    """
    params: List[Any] = [fts_q]
    if category:
        sql += " AND s.top_category = ? "
        params.append(category)
    sql += " ORDER BY bm25_score LIMIT ?"
    params.append(top_k)

    with _connect() as conn:
        try:
            rows = conn.execute(sql, params).fetchall()
        except sqlite3.OperationalError as exc:
            logger.warning("FTS query failed for %r: %s", query, exc)
            return []

    # bm25 returns negative numbers (lower = more relevant); convert to a
    # 0..1 score for nicer downstream consumption.
    if not rows:
        return []
    raw_scores = [r["bm25_score"] for r in rows]
    lo, hi = min(raw_scores), max(raw_scores)
    span = (hi - lo) or 1.0

    out = []
    for r in rows:
        out.append({
            "suite_id": r["suite_id"],
            "display_name": r["display_name"],
            "description": r["description"] or "",
            "top_category": r["top_category"] or "",
            "edam_operation": r["edam_operation"] or "",
            "wrapper_count": r["wrapper_count"],
            "function_count": r["function_count"],
            "score": round(1.0 - ((r["bm25_score"] - lo) / span), 4),
        })
    return out


def list_functions(suite_id: str, top_k: int = 50) -> List[Dict[str, Any]]:
    """Return all functions inside a given suite, sorted by wrapper_count."""
    if not suite_id:
        return []
    sql = """
        SELECT function_id, display_name, wrapper_count
        FROM tool_functions
        WHERE suite_id = ?
        ORDER BY wrapper_count DESC, display_name ASC
        LIMIT ?
    """
    with _connect() as conn:
        rows = conn.execute(sql, (suite_id, top_k)).fetchall()
    return [
        {"function_id": r["function_id"],
         "display_name": r["display_name"],
         "wrapper_count": r["wrapper_count"]}
        for r in rows
    ]


def resolve_wrapper(suite_id: str, function_id: Optional[str] = None,
                     platform_preference: Optional[str] = None) -> Optional[Dict[str, Any]]:
    """
    Pick a wrapper for (suite, function). When function_id is None, returns
    the most-popular function's preferred wrapper.

    platform_preference: 'galaxy' | 'nfcore' | 'biomate' | None
      Filters wrappers by tool_id prefix; if no match, falls back to the
      highest-confidence wrapper across all platforms.

    Returns None if no wrapper exists.
    """
    if not suite_id:
        return None

    # Resolve function: if not provided, pick the suite's most-used function.
    if function_id is None:
        fns = list_functions(suite_id, top_k=1)
        if not fns:
            return None
        function_id = fns[0]["function_id"]

    sql = """
        SELECT wrapper_tool_id, suite_id, function_id, confidence
        FROM tool_wrapper_mapping
        WHERE suite_id = ? AND function_id = ?
        ORDER BY confidence DESC, wrapper_tool_id ASC
    """
    with _connect() as conn:
        rows = conn.execute(sql, (suite_id, function_id)).fetchall()
    if not rows:
        return None

    if platform_preference:
        platform_prefixes = {
            "galaxy": "toolshed.",
            "nfcore": "nfcore/",
            "biomate": "biomate/",
        }
        prefix = platform_prefixes.get(platform_preference.lower())
        if prefix:
            for r in rows:
                if r["wrapper_tool_id"].startswith(prefix):
                    return {
                        "wrapper_tool_id": r["wrapper_tool_id"],
                        "suite_id": r["suite_id"],
                        "function_id": r["function_id"],
                        "confidence": r["confidence"],
                    }
    # Fall back to the highest-confidence wrapper.
    r = rows[0]
    return {
        "wrapper_tool_id": r["wrapper_tool_id"],
        "suite_id": r["suite_id"],
        "function_id": r["function_id"],
        "confidence": r["confidence"],
    }
