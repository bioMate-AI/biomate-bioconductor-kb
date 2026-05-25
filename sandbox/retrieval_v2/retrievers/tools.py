"""
Anthropic tool-use schemas + dispatch for BioMate retrievers.

These schemas are designed to be passed verbatim into the Anthropic Messages
API `tools` parameter. The dispatch table maps `tool_use_input["name"]` →
implementation, allowing the production LLM to invoke retrievers at chat /
research_agent / auto-loop time.

This module is intentionally standalone — it does NOT import from
`research_agent.py` or `galaxy-assistant.ts`. Wiring into those entry points
is a separate PR; this PR ships the tools as a reusable library + tests.
"""
from __future__ import annotations

import logging
from typing import Any, Dict, List

from .europe_pmc import fetch_literature_passage, search_literature
from .omim import lookup_omim_gene

logger = logging.getLogger(__name__)


TOOL_SCHEMAS: List[Dict[str, Any]] = [
    {
        "name": "search_literature",
        "description": (
            "Search Europe PMC (PubMed + PMC) for papers matching a free-text "
            "biomedical query. Use when the user asks 'what's known about X' or "
            "needs evidence/citations for a claim. Returns up to 5 papers with "
            "PMID, DOI, title, abstract, and citation count."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "query": {
                    "type": "string",
                    "description": "Free-text biomedical query (gene, disease, mechanism, drug, etc.)",
                },
                "year_min": {
                    "type": "integer",
                    "description": "Restrict results to papers published in this year or later. Optional.",
                },
                "max_results": {
                    "type": "integer",
                    "description": "Max papers to return (1–10). Default 5.",
                    "default": 5,
                },
            },
            "required": ["query"],
        },
    },
    {
        "name": "fetch_literature_passage",
        "description": (
            "Fetch the most query-relevant passage from a specific paper, given "
            "its DOI or PMID. Use when the user references a particular paper "
            "('the paper says X', 'PMID 12345', 'doi:...') or when you have a "
            "citation from search_literature and want the supporting passage."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "query": {
                    "type": "string",
                    "description": "What you're looking for in the paper (used for passage ranking).",
                },
                "doi": {
                    "type": "string",
                    "description": "DOI of the paper (e.g. '10.1038/s41586-022-04657-6'). Provide this OR pmid.",
                },
                "pmid": {
                    "type": "string",
                    "description": "PubMed ID (e.g. '36287100'). Provide this OR doi.",
                },
                "max_chars": {
                    "type": "integer",
                    "description": "Max passage length in characters (default 2000).",
                    "default": 2000,
                },
            },
            "required": ["query"],
        },
    },
    {
        "name": "lookup_omim_gene",
        "description": (
            "Look up OMIM disease associations for a human gene. Returns gene "
            "name, function summary, and list of associated Mendelian disease "
            "entries with their OMIM IDs. Use for any gene→disease question, "
            "rare-disease diagnosis, or target-validation evidence."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "gene_symbol": {
                    "type": "string",
                    "description": "HGNC gene symbol (e.g. 'BRCA1', 'ARL6IP1', 'BRD4').",
                },
            },
            "required": ["gene_symbol"],
        },
    },
]


def dispatch_tool(name: str, tool_input: Dict[str, Any]) -> Dict[str, Any]:
    """
    Execute a retriever tool by name. Returns a dict suitable for serializing
    as the Anthropic `tool_result` content. Never raises — errors are returned
    as `{"error": "..."}`.
    """
    try:
        if name == "search_literature":
            results = search_literature(
                query=tool_input["query"],
                year_min=tool_input.get("year_min"),
                max_results=tool_input.get("max_results", 5),
            )
            return {"results": results}

        if name == "fetch_literature_passage":
            doi = tool_input.get("doi")
            pmid = tool_input.get("pmid")
            if not (doi or pmid):
                return {"error": "Must provide either `doi` or `pmid`."}
            passage = fetch_literature_passage(
                query=tool_input["query"],
                doi=doi, pmid=pmid,
                max_chars=tool_input.get("max_chars", 2000),
            )
            return {"passage": passage, "found": bool(passage)}

        if name == "lookup_omim_gene":
            return lookup_omim_gene(tool_input["gene_symbol"])

        return {"error": f"Unknown tool: {name}"}
    except KeyError as exc:
        return {"error": f"Missing required input: {exc}"}
    except Exception as exc:
        logger.exception("Tool dispatch crashed for %s", name)
        return {"error": f"{type(exc).__name__}: {exc}"}
