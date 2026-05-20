"""
Wired workflow search — opt-in wrapper around `UnifiedWorkflowSearch`
that adds the workflow_intent priority layer (currently in
`sandbox/workflow_search_v2/`) without modifying the base class.

When `BIOMATE_WORKFLOW_INTENT_PRIORITIZE=1` is set, `search` reorders
candidates to promote the canonical workflow for the matching intent.
When `BIOMATE_WORKFLOW_INTENT_INJECT=1` is also set, missing canonicals
are injected into the result list.

Existing call sites of `UnifiedWorkflowSearch` stay bit-identical — no
edits to protected files.

Usage:
    from backend.lib.galaxy.ai.retrievers.wired_workflow_search import (
        WiredWorkflowSearch,
    )
    search = WiredWorkflowSearch()  # same constructor as UnifiedWorkflowSearch
    results = search.search("Run standard RNA-seq", limit=10)
"""
from __future__ import annotations

import logging
import os
from typing import Any, List, Optional

from galaxy.ai.unified_workflow_search import UnifiedWorkflowSearch, WorkflowMatch

log = logging.getLogger(__name__)


class WiredWorkflowSearch(UnifiedWorkflowSearch):
    """UnifiedWorkflowSearch with optional workflow_intent priority layer.

    Behavior gated by two env flags:
      - BIOMATE_WORKFLOW_INTENT_PRIORITIZE=1: enable the library
      - BIOMATE_WORKFLOW_INTENT_INJECT=1: also inject missing canonicals

    When neither flag is set, behavior is identical to the base class.
    """

    def search(self, query: str, *args, **kwargs) -> List[WorkflowMatch]:
        results = super().search(query, *args, **kwargs)

        if os.environ.get("BIOMATE_WORKFLOW_INTENT_PRIORITIZE") != "1":
            return results
        if not results:
            return results

        try:
            # Library still lives in sandbox; import path reflects that.
            # When the library is promoted to backend/lib, update this import.
            from sandbox.workflow_search_v2.library.workflow_intent import (
                prioritize_workflow_by_intent,
            )
            inject = os.environ.get("BIOMATE_WORKFLOW_INTENT_INJECT") == "1"
            return prioritize_workflow_by_intent(
                query, results, inject_canonical=inject,
            )
        except Exception as exc:
            log.warning("workflow-intent prioritize failed, falling back: %s", exc)
            return results
