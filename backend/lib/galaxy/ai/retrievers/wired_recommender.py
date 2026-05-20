"""
Wired tool-parameter recommender — opt-in wrapper around the existing
`ToolParameterRecommender` that adds the `family_dedup` library on top
without modifying the original class.

Callers that want the family-prioritized behavior import this wrapper
instead of the base class. Existing call sites of
`ToolParameterRecommender` stay bit-identical — no protected-file edits.

Usage:
    from backend.lib.galaxy.ai.retrievers.wired_recommender import (
        WiredToolParameterRecommender,
    )
    rec = WiredToolParameterRecommender(db_path=...)
    # Same API as the base class. search_tools is now family-prioritized
    # when BIOMATE_FAMILY_PRIORITIZE=1 is set (default: bit-identical to base).
    tools = rec.search_tools("samtools", limit=5)
"""
from __future__ import annotations

import logging
import os
from typing import List

from galaxy.ai.workflow_ops.autofix.tool_parameter_recommender import (
    ToolParameterRecommender, ToolInfo,
)

log = logging.getLogger(__name__)


class WiredToolParameterRecommender(ToolParameterRecommender):
    """ToolParameterRecommender with optional family_dedup priority layer.

    When `BIOMATE_FAMILY_PRIORITIZE=1` is set in the environment, the
    `search_tools` method fetches `limit * 10` results from FTS, then
    applies `prioritize_query_family` to promote the canonical wrapper
    of the matching family to position 1.

    When the env flag is unset, behavior is identical to the base class
    (no fetch-limit change, no prioritization).

    All other base-class methods (`get_tool_by_name`, `recommend_parameters`,
    etc.) inherit unchanged.
    """

    def search_tools(self, query: str, limit: int = 10) -> List[ToolInfo]:
        if os.environ.get("BIOMATE_FAMILY_PRIORITIZE") != "1":
            # Flag off — pure passthrough, bit-identical to base class
            return super().search_tools(query, limit=limit)

        # Flag on — fetch wider, prioritize, trim
        if not self.conn:
            return []
        raw = super().search_tools(query, limit=limit * 10)
        if not raw:
            return raw
        try:
            from backend.lib.galaxy.ai.retrievers import prioritize_query_family
            as_dicts = [
                {"tool_id": t.tool_id, "name": t.name, "_idx": i}
                for i, t in enumerate(raw)
            ]
            reordered = prioritize_query_family(query, as_dicts)
            return [raw[d["_idx"]] for d in reordered[:limit]]
        except Exception as exc:
            log.warning("family-prioritize failed, falling back: %s", exc)
            return raw[:limit]
