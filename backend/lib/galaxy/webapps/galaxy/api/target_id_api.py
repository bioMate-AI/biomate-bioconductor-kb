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
    tables: Optional[List[Dict[str, Any]]] = None  # server-side evidence tables; only paths inside TARGET_ID_TABLE_ROOT are accepted
    client_tables: Optional[List[Dict[str, Any]]] = None  # the hospital's own analysis results, rows sent inline (see client_data.ADAPTERS)
    run_outputs: Optional[List[Dict[str, Any]]] = None    # completed analysis outputs to read from TARGET_ID_RUN_OUTPUT_ROOT: {path, name?, label?, source_run_id?, kind?, columns?}
    use_llm: bool = True                           # on by default (2026-10-25): LLM-reasoned is the strongest target-ID channel; falls back to None if no LLM configured
    include_network: bool = True                   # STRING (and pathway, if configured) channels, seeded from the Open Targets top genes
    ranking_mode: str = "auto"                     # "auto": Open Targets-primary when available; "integrated": all channels incl. client data weighted
    validate: bool = False                         # also return, for the top targets, the BioMate workflows that would test them
    validate_top_n: int = 5
    top_k: int = 25
    z_thresh: float = 2.0
    max_concurrent: int = 8


_RANKING_MODES = ("auto", "integrated")


@router.get("/api/target-id/status", summary="Which target-ID channels are configured, and which hosts they need")
async def target_id_status() -> Dict[str, Any]:
    """Configuration only (no network calls): what a deployment must allow-list, and what works offline."""
    from galaxy.ai.target_id.client_data import ADAPTERS
    from galaxy.ai.target_id.data_channels import list_snapshots, offline_mode, snapshot_dir
    from galaxy.ai.target_id.table_policy import run_output_root, table_root

    off = offline_mode()
    hosts = [] if off else [
        {"host": "api.platform.opentargets.org", "used_by": "genetics_ot", "needed_for": "Open Targets associations (or a local snapshot)"},
        {"host": "string-db.org", "used_by": "ppi_string", "needed_for": "protein-interaction network (live only; skipped offline)"},
    ]
    return {
        "offline": off,
        "snapshot_dir_configured": bool(snapshot_dir()),
        "snapshots": list_snapshots(snapshot_dir()),
        "server_tables_enabled": bool(table_root()),
        "run_outputs_enabled": bool(run_output_root()),
        "client_table_kinds": sorted(ADAPTERS),
        "external_hosts": hosts,
        "language_model": "uses the configured LLM provider; its endpoint is whatever the deployment sets (a local endpoint in on-premises mode)",
        "ranking_modes": list(_RANKING_MODES),
    }


@router.post("/api/target-id/identify", summary="Identify + rank drug targets across evidence channels")
async def identify_targets(request: IdentifyTargetsRequest) -> Dict[str, Any]:
    if not request.query:
        raise HTTPException(status_code=400, detail="query required")
    if request.ranking_mode not in _RANKING_MODES:
        raise HTTPException(status_code=400, detail="ranking_mode must be one of %s" % ", ".join(_RANKING_MODES))

    from galaxy.ai.target_id import HarmonicSumArbiter, TargetIDOrchestrator, default_channels
    from galaxy.ai.target_id.analysis_outputs import specs_from_run_outputs
    from galaxy.ai.target_id.table_policy import safe_table_specs

    llm = None
    if request.use_llm:
        try:
            from galaxy.ai.config import AIConfig
            from galaxy.ai.llm_client import LLMClient
            llm = LLMClient(AIConfig())
        except Exception as exc:  # LLM is optional — never fail the request on it
            log.warning("target-id: LLM channel unavailable, continuing without it: %s", exc)
            llm = None

    try:
        tables = safe_table_specs(request.tables)
        client_tables = list(request.client_tables or []) + specs_from_run_outputs(request.run_outputs)
        channels = default_channels(disease_id=request.disease_id, tables=tables, llm_client=llm,
                                    client_tables=client_tables, include_network=request.include_network)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    if not channels:
        raise HTTPException(
            status_code=400,
            detail="no evidence channels available — provide disease_id, client_tables, or use_llm=true",
        )

    ctx: Dict[str, Any] = {"query": request.query, "disease_id": request.disease_id, "disease": request.disease}
    if request.candidate_targets:
        ctx["candidate_targets"] = [str(g).upper() for g in request.candidate_targets]

    # "auto" keeps the orchestrator's audited default (Open Targets-primary when that channel is available).
    # "integrated" ranks across every channel, including the hospital's own data, with reliability weights.
    arbiter = HarmonicSumArbiter(primary_channel=None) if request.ranking_mode == "integrated" else None
    orch = TargetIDOrchestrator(
        channels,
        arbiter=arbiter,
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
    if request.validate:
        try:
            from galaxy.ai.target_id import validation_plan
            top_n = max(1, min(int(request.validate_top_n), 10))
            out["validation_plan"] = await asyncio.get_event_loop().run_in_executor(
                None, lambda: validation_plan(result.targets, top_n=top_n))
        except Exception as exc:  # the ranking is still valid without the plan
            log.warning("target-id: validation plan unavailable: %s", exc)
            out["validation_plan"] = {"error": "%s: %s" % (type(exc).__name__, exc)}
    return out
