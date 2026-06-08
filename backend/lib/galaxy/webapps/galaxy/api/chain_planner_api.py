"""
chain_planner_api.py — v3 typed-port chain planner endpoint.

Auto-registered by Galaxy's include_all_package_routers scanner (same pattern
as billing_lite.py). Wraps `galaxy.ai.chain_planner.plan_chains` so the v3
demo page can query candidate chains without going through chat.

Gated UX only — the v3 chrome (?ui=v3) is the only surface that calls this.
v1/v2 chat flow is untouched. See:
- docs/20260607_PARALLELISM_AND_CROSS_DOMAIN_CHAINING_PROPOSAL.md (C2)
- docs/20260607_PARALLELISM_CHAINING_IMPLEMENTATION_NOTES.md

Endpoint:
  GET /api/chain-planner/preview?start=fastq&start=samplesheet&goal=enrichment&goal_type=gsea_results&max_steps=4&top_k=3
"""

import logging
from typing import Any, Dict, List, Optional

from fastapi import APIRouter, HTTPException, Query

log = logging.getLogger(__name__)

router = APIRouter(prefix="/api/chain-planner", tags=["chain-planner"])


def _planner():
    """Lazy import to avoid pulling DB code into Galaxy startup if unused."""
    import importlib
    return importlib.import_module("galaxy.ai.chain_planner")


@router.get("/preview")
def preview_chain_plans(
    start: List[str] = Query(..., description="Starting input types, repeated (e.g. start=fastq&start=samplesheet)"),
    goal: Optional[str] = Query(None, description="Free-text goal keyword for scoring"),
    goal_type: Optional[List[str]] = Query(None, description="Terminate when these output types are reached"),
    max_steps: int = Query(4, ge=1, le=8),
    top_k: int = Query(3, ge=1, le=10),
) -> Dict[str, Any]:
    """Run the typed-port planner and return up to `top_k` candidate chains.

    Behavior is read-only — does not record a run, does not mutate state.
    Safe to call repeatedly from the v3 demo page.
    """
    try:
        cp = _planner()
        plans = cp.plan_chains(
            start_input_types=start,
            goal=goal,
            goal_output_types=goal_type,
            max_steps=max_steps,
            top_k=top_k,
        )
    except Exception as exc:
        log.exception("chain-planner: preview failed")
        raise HTTPException(status_code=500, detail=f"planner_error: {exc}")

    return {
        "plans": [p.to_dict() for p in plans],
        "query": {
            "start": start,
            "goal": goal,
            "goal_type": goal_type,
            "max_steps": max_steps,
            "top_k": top_k,
        },
        "source": "planner",  # provenance — UI uses this to render the v3 "Planned" badge
    }
