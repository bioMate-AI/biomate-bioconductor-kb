"""
ProjectKnowledge recall helper — surfaces relevant entries from BioMate's
`project_knowledge` table for a user query.

Gap this addresses:
  `agentic_memory.py` defines the `ProjectKnowledge` model
  (title / content / knowledge_type / relevance_score / related_workflows)
  but provides NO service class to query it. The table exists but has no
  recall surface — the literal "not fully leveraged" hierarchy slice.

Same composable-helper pattern as `procedure_widener.py`:
  - Standalone module in a new file (no collision with parallel-session edits)
  - Takes a duck-typed SQLAlchemy session factory
  - Opt-in via BIOMATE_MEMORY_QUERY_ENRICH=1
  - Gracefully degrades on any error

API:

    from galaxy.ai.retrievers.knowledge_recall import (
        recall_project_knowledge,
    )

    out = recall_project_knowledge(
        project_id="proj_drug_discovery",
        query="What did we learn about BRCA-1 in breast cancer?",
        session_factory=get_db_session,    # from agentic_memory
        limit=10,
    )
    # out = {
    #   "entries": [...],
    #   "extracted_entities": [...],
    #   "fallback_used": bool,
    # }

The function returns project_knowledge rows as dicts. When the env flag
is set, additionally widens the substring search by canonical entities
extracted from the query.
"""
from __future__ import annotations

import logging
import os
from typing import Any, Callable, Dict, List, Optional

logger = logging.getLogger(__name__)


def _row_to_dict(row: Any) -> Dict[str, Any]:
    """Convert a ProjectKnowledge SQLAlchemy row (or dict) to a plain dict."""
    if isinstance(row, dict):
        return row
    return {
        "id": getattr(row, "id", None),
        "project_id": str(getattr(row, "project_id", "")),
        "knowledge_type": getattr(row, "knowledge_type", None),
        "title": getattr(row, "title", None),
        "content": getattr(row, "content", None),
        "source": getattr(row, "source", None),
        "relevance_score": getattr(row, "relevance_score", None),
    }


def _baseline_query(session: Any, project_id: str, query: str,
                      limit: int) -> List[Any]:
    """Run the substring + relevance-score baseline query.

    Mirrors the pattern used by `get_similar_episodes`: lowercase
    substring match against title + content, ordered by relevance_score.
    """
    try:
        from galaxy.ai.memory.agentic_memory import ProjectKnowledge
    except Exception as exc:
        logger.warning("ProjectKnowledge import failed: %s", exc)
        return []

    rows = session.query(ProjectKnowledge).filter(
        ProjectKnowledge.project_id == project_id,
    ).order_by(ProjectKnowledge.relevance_score.desc()).all()

    q_lower = (query or "").lower().strip()
    if not q_lower:
        return rows[:limit]

    matched = []
    for r in rows:
        title = (r.title or "").lower()
        content = (r.content or "").lower()
        if q_lower in title or q_lower in content:
            matched.append(r)
        elif title and title in q_lower:
            matched.append(r)
    return matched[:limit]


def _widen_by_entity(session: Any, project_id: str, canonical_id: str,
                      limit: int) -> List[Any]:
    """Search project_knowledge for entries mentioning a canonical entity."""
    try:
        from galaxy.ai.memory.agentic_memory import ProjectKnowledge
    except Exception:
        return []

    cid_lower = canonical_id.lower()
    rows = session.query(ProjectKnowledge).filter(
        ProjectKnowledge.project_id == project_id,
    ).order_by(ProjectKnowledge.relevance_score.desc()).all()

    matched = [
        r for r in rows
        if (r.title and cid_lower in r.title.lower())
        or (r.content and cid_lower in r.content.lower())
    ]
    return matched[:limit]


def recall_project_knowledge(
    project_id: Optional[str],
    query: str,
    *,
    session_factory: Optional[Callable[[], Any]] = None,
    limit: int = 10,
) -> Dict[str, Any]:
    """Surface project_knowledge entries relevant to a query.

    Args:
        project_id: BioMate project ID. None → return empty.
        query: Natural-language user query.
        session_factory: Callable returning a context-managed SQLAlchemy
            session. Defaults to agentic_memory.get_db_session if importable.
        limit: Max entries to return.

    Returns:
        Dict with:
          entries: List[Dict]    — project_knowledge rows as dicts
          extracted_entities: List[Dict] — canonical entities found in query
          fallback_used: bool    — True when only baseline (no widening)
    """
    result: Dict[str, Any] = {
        "entries": [], "extracted_entities": [], "fallback_used": False,
    }
    if not project_id or not query:
        return result

    if session_factory is None:
        try:
            from galaxy.ai.memory.agentic_memory import get_db_session
            session_factory = get_db_session
        except Exception as exc:
            logger.warning("session_factory unavailable: %s", exc)
            return result

    # Baseline: substring match in title + content
    try:
        with session_factory() as session:
            baseline_rows = _baseline_query(session, project_id, query, limit)
            baseline_dicts = [_row_to_dict(r) for r in baseline_rows]
    except Exception as exc:
        logger.warning("baseline knowledge query failed: %s", exc)
        return result

    # Decide enrichment
    enrich = os.environ.get("BIOMATE_MEMORY_QUERY_ENRICH") == "1"
    if not enrich:
        result["entries"] = baseline_dicts
        result["fallback_used"] = True
        return result

    # Entity extraction (defensive)
    try:
        from sandbox.intent_retrieval_v3.adapters.entity import (
            extract_canonical_entities,
        )
        entities = extract_canonical_entities(query)
    except Exception as exc:
        logger.warning("entity extraction failed in knowledge_recall: %s", exc)
        result["entries"] = baseline_dicts
        result["fallback_used"] = True
        return result

    result["extracted_entities"] = entities

    if not entities:
        result["entries"] = baseline_dicts
        return result

    # Widen: per canonical entity, search title + content
    enriched = list(baseline_dicts)
    seen = {e["id"] for e in enriched if e.get("id") is not None}
    try:
        with session_factory() as session:
            for ent in entities:
                cid = ent["canonical_id"]
                try:
                    rows = _widen_by_entity(session, project_id, cid, limit)
                except Exception as exc:
                    logger.warning("widen failed for %s: %s", cid, exc)
                    continue
                for r in rows:
                    d = _row_to_dict(r)
                    rid = d.get("id")
                    if rid is None:
                        enriched.append(d)
                        continue
                    if rid not in seen:
                        enriched.append(d)
                        seen.add(rid)
    except Exception as exc:
        logger.warning("session for widening failed: %s", exc)

    result["entries"] = enriched[:limit]
    return result
