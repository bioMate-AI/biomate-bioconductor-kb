"""
Procedure-widening helper — extracts canonical entities from a query and
uses them to widen procedure recall beyond `ProceduralMemoryService.
get_reliable_procedures` (which is not query-aware).

Designed as a STANDALONE composable helper so any caller can use it without
modifying `wired_agentic_memory.py` (which gets edited by parallel Claude
sessions and reverts collisions).

Usage:

    from backend.lib.galaxy.ai.retrievers.procedure_widener import (
        widen_procedures_by_entities,
    )

    # Caller has its own AgenticMemoryService or ProceduralMemoryService
    baseline = service.procedures.get_reliable_procedures(project_id)
    out = widen_procedures_by_entities(
        procedures_service=service.procedures,
        project_id=project_id,
        query=user_query,
        baseline_procedures=baseline,
        limit=10,
    )
    # out = {"applicable_procedures": [...], "extracted_entities": [...]}

Pure helper:
  - No DB connection of its own (uses the service the caller passes in)
  - Opt-in via env BIOMATE_MEMORY_QUERY_ENRICH=1
  - Gracefully degrades to baseline_procedures on any error
"""
from __future__ import annotations

import logging
import os
from typing import Any, Dict, List, Optional

logger = logging.getLogger(__name__)


def widen_procedures_by_entities(
    procedures_service: Any,
    project_id: Optional[str],
    query: str,
    *,
    baseline_procedures: Optional[List[Dict[str, Any]]] = None,
    limit: int = 10,
) -> Dict[str, Any]:
    """Widen procedure recall by also calling `find_matching_procedures` once
    per canonical entity extracted from the query.

    Args:
        procedures_service: An object with a `find_matching_procedures(
            project_id=..., trigger=...) -> List[Dict]` method. Typically
            this is the `ProceduralMemoryService` from `agentic_memory`,
            but any duck-typed object works.
        project_id: BioMate project identifier; None disables widening.
        query: User's natural-language query.
        baseline_procedures: Procedures already retrieved (e.g. from
            `get_reliable_procedures`). Included in the output unchanged
            at the head, plus dedup against entity-matched additions.
        limit: Max procedures to return.

    Returns:
        Dict with keys:
          applicable_procedures: List of procedure dicts (baseline + widened)
          extracted_entities:    List of {canonical_id, entity_type, matched_alias}

    Failure modes (all return baseline silently):
      - project_id is None / empty
      - query is empty
      - BIOMATE_MEMORY_QUERY_ENRICH != "1"
      - Entity extractor unavailable or raises
      - procedures_service.find_matching_procedures raises
    """
    baseline = list(baseline_procedures or [])
    if not project_id or not query:
        return {"applicable_procedures": baseline[:limit], "extracted_entities": []}

    if os.environ.get("BIOMATE_MEMORY_QUERY_ENRICH") != "1":
        return {"applicable_procedures": baseline[:limit], "extracted_entities": []}

    # Extract canonical entities — defensive: never let the entity adapter
    # crash the recall pipeline.
    try:
        from sandbox.intent_retrieval_v3.adapters.entity import (
            extract_canonical_entities,
        )
        entities = extract_canonical_entities(query)
    except Exception as exc:
        logger.warning("entity extraction failed: %s", exc)
        return {"applicable_procedures": baseline[:limit], "extracted_entities": []}

    if not entities:
        return {"applicable_procedures": baseline[:limit], "extracted_entities": []}

    # Widen — call find_matching_procedures once per canonical, dedup by id
    enriched = list(baseline)
    seen_ids = {p.get("id") for p in enriched if p.get("id") is not None}
    for ent in entities:
        cid = ent["canonical_id"]
        try:
            extra = procedures_service.find_matching_procedures(
                project_id=project_id, trigger=cid
            )
        except Exception as exc:
            logger.warning("find_matching_procedures(trigger=%s) failed: %s", cid, exc)
            continue
        for p in extra or []:
            pid = p.get("id")
            if pid is None:
                # Procedure with no id — keep it but don't dedup
                enriched.append(p)
                continue
            if pid not in seen_ids:
                enriched.append(p)
                seen_ids.add(pid)

    return {
        "applicable_procedures": enriched[:limit],
        "extracted_entities": entities,
    }
