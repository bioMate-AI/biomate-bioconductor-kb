"""Target identification API — auto-discovered by include_all_package_routers().

POST /api/target-id/identify — run the multi-channel, tabular-arbitered target-ID orchestrator
(galaxy.ai.target_id) and return ranked, confidence-tiered targets with per-channel provenance.
This is the first-class reachable surface for the capability (see
docs/20261020_INNOVATION_DEMONSTRATION_PROTOCOL.md). The MCP `identify_targets` tool proxies here.

PEP 604 union footgun: `from __future__ import annotations` keeps this import-safe on the dev
gunicorn Python 3.9 (same guard as generation.py / nextflow_executor.py).
"""
from __future__ import annotations

import asyncio
import logging
from typing import Any, Dict, List, Optional

from fastapi import HTTPException
from pydantic import BaseModel

from galaxy.webapps.galaxy.api import Router

log = logging.getLogger(__name__)

router = Router(tags=["target-id"])


class IdentifyTargetsRequest(BaseModel):
    query: str
    disease_id: Optional[str] = None               # EFO/MONDO id for the OpenTargets genetics channel
    disease: Optional[str] = None
    candidate_targets: Optional[List[str]] = None
    tables: Optional[List[Dict[str, Any]]] = None  # cached-evidence TableChannel kwargs (path, name, ...)
    use_llm: bool = True                           # on by default (2026-10-25): LLM-reasoned is the strongest target-ID channel; falls back to None if no LLM configured
    top_k: int = 25
    z_thresh: float = 2.0
    max_concurrent: int = 8


@router.post("/api/target-id/identify", summary="Identify + rank drug targets across evidence channels")
async def identify_targets(request: IdentifyTargetsRequest) -> Dict[str, Any]:
    if not request.query:
        raise HTTPException(status_code=400, detail="query required")

    from galaxy.ai.target_id import TargetIDOrchestrator, default_channels

    llm = None
    if request.use_llm:
        try:
            from galaxy.ai.config import AIConfig
            from galaxy.ai.llm_client import LLMClient
            llm = LLMClient(AIConfig())
        except Exception as exc:  # LLM is optional — never fail the request on it
            log.warning("target-id: LLM channel unavailable, continuing without it: %s", exc)
            llm = None

    channels = default_channels(disease_id=request.disease_id, tables=request.tables, llm_client=llm)
    if not channels:
        raise HTTPException(
            status_code=400,
            detail="no evidence channels available — provide disease_id, tables, or use_llm=true",
        )

    ctx: Dict[str, Any] = {"query": request.query, "disease_id": request.disease_id, "disease": request.disease}
    if request.candidate_targets:
        ctx["candidate_targets"] = [str(g).upper() for g in request.candidate_targets]

    orch = TargetIDOrchestrator(
        channels,
        # Use the orchestrator's audited default: OpenTargets-primary when that
        # channel is available, with explicit fallback metadata when it fails.
        llm_client=llm,
        max_concurrent=request.max_concurrent,
    )

    # The channels do blocking network I/O (OpenTargets) + CPU fusion — run off the event loop.
    try:
        result = await asyncio.get_event_loop().run_in_executor(
            None, lambda: orch.identify(request.query, context=ctx)
        )
    except Exception as exc:
        log.exception("target-id identify failed")
        raise HTTPException(status_code=500, detail="identify failed: %s" % exc)

    out = result.to_dict()
    out["targets"] = out["targets"][: int(request.top_k)]
    out["n_targets_total"] = len(result.targets)
    return out
