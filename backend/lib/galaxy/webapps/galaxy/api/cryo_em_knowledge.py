"""
cryo_em_knowledge.py — REST endpoints for cryo-EM protocol knowledge retrieval.

Auto-registered by Galaxy's router scanner (same pattern as billing_lite.py,
enhanced_ai_assistant.py, etc.).

Endpoints
=========
POST /api/cryo_em/context
    Body: {query, sample_class?, max_tokens?}
    Returns combined structured + RAG context for a cryo-EM query.
    Used by galaxy-assistant.ts when domain='cryo_em'.

GET  /api/cryo_em/parameter
    Query: context=mw_lt50&parameter=pixel_size_angstrom
    Returns a single parameter value. Zero LLM cost.

GET  /api/cryo_em/protocol/{sample_class}
    Returns compact protocol JSON for a sample class.

GET  /api/cryo_em/rag/status
    Returns index build status and chunk counts.

POST /api/cryo_em/rag/build
    (Re-)build the RAG index from docs/cryo_em_skills/*.md.
    Requires VOYAGE_API_KEY or OPENAI_API_KEY for semantic quality.
"""

from __future__ import annotations

import os
from typing import Optional

from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel

router = APIRouter(tags=["cryo_em_knowledge"])

# Lazy singleton — avoids import cost at module load time
_retriever = None


def _get_retriever():
    global _retriever
    if _retriever is None:
        import sys
        sys.path.insert(0, os.path.join(os.path.dirname(__file__), "../../../../.."))
        from galaxy.ai.cryo_em_knowledge import get_retriever
        db_path = os.environ.get(
            "GALAXY_AI_DB_PATH",
            os.path.join(os.path.dirname(__file__), "../../../../../database/galaxy_ai_tools.db")
        )
        _retriever = get_retriever(os.path.abspath(db_path))
    return _retriever


# ── Request/response models ───────────────────────────────────────────────────

class ContextRequest(BaseModel):
    query: str
    sample_class: Optional[str] = None
    max_tokens: int = 500


class ContextResponse(BaseModel):
    context: str
    sample_class_detected: Optional[str]
    token_estimate: int
    has_rag: bool
    has_protocol: bool


class ParameterResponse(BaseModel):
    context: str
    parameter: str
    value: Optional[str]
    unit: Optional[str]
    rationale: Optional[str]


class RagStatusResponse(BaseModel):
    available: bool
    total_chunks: int
    vec_indexed: int
    by_type: dict


class RagBuildResponse(BaseModel):
    chunks_indexed: int
    message: str


# ── Endpoints ─────────────────────────────────────────────────────────────────

@router.post("/api/cryo_em/context", response_model=ContextResponse)
def get_cryo_em_context(req: ContextRequest):
    """
    Return combined structured + semantic RAG context for a cryo-EM query.
    This is the main endpoint called by galaxy-assistant.ts for cryo-EM queries.
    """
    r = _get_retriever()

    # Auto-detect sample class if not provided
    sc = req.sample_class
    if not sc:
        sc = r.detect_sample_class(req.query)

    ctx = r.get_full_context(
        query=req.query,
        sample_class=sc,
        max_rag_tokens=req.max_tokens,
    )

    return ContextResponse(
        context=ctx,
        sample_class_detected=sc,
        token_estimate=len(ctx) // 4,
        has_rag="<cryo_em_knowledge>" in ctx,
        has_protocol="<cryo_em_protocol>" in ctx,
    )


@router.get("/api/cryo_em/parameter")
def get_parameter(
    context: str = Query(..., description="e.g. mw_lt50 or saposin_nanodisc"),
    parameter: str = Query(..., description="e.g. pixel_size_angstrom"),
):
    """Single parameter lookup. Zero LLM cost."""
    r = _get_retriever()
    detail = r.get_parameter_with_detail(context, parameter)
    if not detail:
        raise HTTPException(status_code=404, detail=f"No parameter '{parameter}' for context '{context}'")
    return detail


@router.get("/api/cryo_em/parameters/mw")
def get_parameters_for_mw(mw_kda: float = Query(..., description="Molecular weight in kDa")):
    """All parameters for a given MW."""
    r = _get_retriever()
    return r.get_parameters_for_mw(mw_kda)


@router.get("/api/cryo_em/protocol/{sample_class}")
def get_protocol(sample_class: str):
    """Compact protocol JSON for a sample class."""
    r = _get_retriever()
    compact = r.get_compact_context(sample_class)
    import json
    obj = json.loads(compact)
    if "error" in obj:
        raise HTTPException(status_code=404, detail=obj["error"])
    return obj


@router.get("/api/cryo_em/protocols")
def list_protocols():
    """List all available sample classes."""
    r = _get_retriever()
    return r.list_protocols()


@router.get("/api/cryo_em/tools/gaps")
def get_tool_gaps():
    """Return BioMate tool gap summary (have/partial/missing)."""
    r = _get_retriever()
    return r.get_gap_summary()


@router.get("/api/cryo_em/rag/status", response_model=RagStatusResponse)
def rag_status():
    """Return RAG index build status."""
    r = _get_retriever()
    s = r.get_rag_status()
    return RagStatusResponse(
        available=s.get("available", False),
        total_chunks=s.get("total_chunks", 0),
        vec_indexed=s.get("vec_indexed", 0),
        by_type=s.get("by_type", {}),
    )


@router.post("/api/cryo_em/rag/search")
def rag_search(
    query: str = Query(...),
    top_k: int = Query(5, ge=1, le=20),
    sample_class: Optional[str] = Query(None),
    chunk_type: Optional[str] = Query(None),
):
    """Direct semantic search over RAG index. For testing/debugging."""
    r = _get_retriever()
    results = r.semantic_search(
        query=query, top_k=top_k,
        sample_class=sample_class, chunk_type=chunk_type,
    )
    return {"query": query, "results": results, "count": len(results)}


@router.post("/api/cryo_em/rag/build", response_model=RagBuildResponse)
def build_rag_index(
    force: bool = Query(False, description="Rebuild even if already built"),
    docs_dir: str = Query(
        "/home/yzhang/biomate/docs/cryo_em_skills",
        description="Directory containing cryo-EM skill markdown files"
    ),
):
    """
    Build (or rebuild) the semantic RAG index.
    Set VOYAGE_API_KEY or OPENAI_API_KEY for high-quality embeddings.
    """
    from galaxy.ai.cryo_em_knowledge import build_rag_index as _build
    db_path = os.environ.get(
        "GALAXY_AI_DB_PATH",
        os.path.join(os.path.dirname(__file__), "../../../../../database/galaxy_ai_tools.db")
    )
    n = _build(docs_dir=docs_dir, db_path=os.path.abspath(db_path), force=force)
    return RagBuildResponse(
        chunks_indexed=n,
        message=f"RAG index built with {n} chunks. "
                f"{'Using hash fallback (no API key).' if not os.environ.get('VOYAGE_API_KEY') and not os.environ.get('OPENAI_API_KEY') else 'Using API embeddings.'}"
    )
