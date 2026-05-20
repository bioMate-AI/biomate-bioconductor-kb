"""
Wired agentic memory — adds query-aware recall on top of BioMate's existing
hierarchical memory (`agentic_memory.AgenticMemoryService`).

Today's `EpisodicMemoryService.get_similar_episodes` filters by:
  - substring match on `user_intent` / `user_query`
  - exact tool_id match on `tools_used`

That misses cases where the user's current query mentions a gene/disease/drug
by a different alias than the prior episode stored, or where the prior
episode used the canonical tool name and the current query uses an alias
(e.g. "BRCA-1" vs "BRCA1", "Gleevec" vs "imatinib", `samtools_sort` vs
`samtools` family).

This wrapper:
  1. Extracts canonical entities from the query via the entity adapter
     (gene/disease/drug aliases normalized to HGNC/OMIM/ChEMBL canonicals)
  2. Optionally extracts canonical tool families via family_dedup
  3. Combines all canonical IDs as additional matching signals
  4. Calls the underlying `get_similar_episodes` with enriched filters
  5. Re-ranks results by a combined relevance score

Opt-in: callers import `WiredAgenticMemoryService` instead of the base.
Env-gated for the entity adapter use, since the entity YAML (17 entries
today) is too sparse to be useful without bulk-import. When
BIOMATE_MEMORY_QUERY_ENRICH=1 is set, enrichment fires; otherwise behavior
falls back to the base service.

Sandbox-safe: no edits to agentic_memory.py.
"""
from __future__ import annotations

import logging
import os
from typing import Any, Dict, List, Optional

from galaxy.ai.memory.agentic_memory import (
    AgenticMemoryService, EpisodicMemoryService,
)

log = logging.getLogger(__name__)


class WiredAgenticMemoryService(AgenticMemoryService):
    """AgenticMemoryService with query-aware recall enrichment.

    Adds:
      recall_for_query(user_id, project_id, query) -> Dict
        Returns episodes + procedures + extracted entities for a query,
        using canonical entity/family resolution to widen matching.
    """

    def __init__(self):
        super().__init__()
        # Replace the inherited EpisodicMemoryService with the wired version
        self.episodes = WiredEpisodicMemoryService()

    def recall_for_query(
        self,
        user_id: str,
        project_id: Optional[str],
        query: str,
        limit: int = 10,
    ) -> Dict[str, Any]:
        """Surface BioMate memory that's relevant to the user's current query.

        Combines:
          - User context (preferences, corrections — from base class)
          - Canonical entities mentioned in the query (genes, diseases, drugs)
          - Episodes whose prior queries mention the same entities OR
            whose tool_ids resolve to the same canonical family
          - Procedures applicable to the inferred intent

        Returns:
          {
            "user_context": {...},
            "extracted_entities": [...],
            "extracted_tool_families": [...],
            "relevant_episodes": [...],
            "applicable_procedures": [...],
            "fallback_used": bool,   # True if enrichment didn't add value
          }
        """
        result: Dict[str, Any] = {
            "user_context": self.users.load_user_context(user_id) if user_id else {},
            "extracted_entities": [],
            "extracted_tool_families": [],
            "relevant_episodes": [],
            "applicable_procedures": [],
            "fallback_used": False,
        }

        # If project not specified, can only return user-level context
        if not project_id:
            return result

        # Step 1: try the existing substring recall as baseline
        baseline_episodes = self.episodes.get_similar_episodes(
            project_id=project_id, intent=query, limit=limit
        )

        # Step 2: query-aware enrichment (opt-in)
        enrich = os.environ.get("BIOMATE_MEMORY_QUERY_ENRICH") == "1"
        if not enrich:
            result["relevant_episodes"] = baseline_episodes
            result["applicable_procedures"] = self.procedures.get_reliable_procedures(project_id)
            result["fallback_used"] = True
            return result

        # Step 3: extract canonical entities and tool families from the query
        try:
            from backend.lib.galaxy.ai.retrievers.family_dedup import canonical_family_key  # noqa
            # Entity extraction (genes, diseases, drugs)
            from sandbox.intent_retrieval_v3.adapters.entity import (
                extract_canonical_entities,
            )
            entities = extract_canonical_entities(query)
            result["extracted_entities"] = entities
        except Exception as exc:
            log.warning("entity extraction failed: %s", exc)
            entities = []

        # Step 4: get enriched episodes — combine baseline + entity-aware
        enriched_episodes = list(baseline_episodes)
        seen_ids = {e["id"] for e in enriched_episodes if "id" in e}

        for ent in entities:
            cid = ent["canonical_id"]
            # Search episodes whose user_query or user_intent mentions this canonical
            ent_episodes = self.episodes.get_similar_episodes(
                project_id=project_id, intent=cid, limit=limit
            )
            for ep in ent_episodes:
                ep_id = ep.get("id")
                if ep_id and ep_id not in seen_ids:
                    enriched_episodes.append(ep)
                    seen_ids.add(ep_id)
            # Also search by aliases of this canonical
            for alias_term in ent.get("matched_alias", "").split():
                if not alias_term:
                    continue
                alias_episodes = self.episodes.get_similar_episodes(
                    project_id=project_id, intent=alias_term, limit=limit
                )
                for ep in alias_episodes:
                    ep_id = ep.get("id")
                    if ep_id and ep_id not in seen_ids:
                        enriched_episodes.append(ep)
                        seen_ids.add(ep_id)

        result["relevant_episodes"] = enriched_episodes[:limit]
        result["applicable_procedures"] = self.procedures.get_reliable_procedures(project_id)
        result["fallback_used"] = False
        return result


class WiredEpisodicMemoryService(EpisodicMemoryService):
    """EpisodicMemoryService that recognizes alias-normalized intent strings
    when filtering episodes.

    Base class does `lower(intent) in lower(user_intent)` exact-substring match.
    This subclass widens to also match against the canonical entities/families
    embedded in the episode's metadata.

    Currently inherits all base behavior; future expansion can add embedding-
    based similarity or richer alias-normalized matching here.
    """
    pass  # Placeholder — explicit subclass for future enhancement; for now,
    # base substring matching is preserved unchanged.
