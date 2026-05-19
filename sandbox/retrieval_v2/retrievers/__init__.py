"""
BioMate retrieval tools — external database + literature lookups exposed
to the production LLM via Anthropic tool-use.

These modules were lifted out of `evaluation/` during the Phase 1 productization
described in `docs/20260518_RETRIEVAL_TOOLS_PRODUCTIZATION_AND_USE_CASES.md`.

Public API:
    from backend.lib.galaxy.ai.retrievers import (
        fetch_literature_passage, search_literature,
        lookup_omim_gene,
        TOOL_SCHEMAS, dispatch_tool,
    )
"""
from .europe_pmc import fetch_literature_passage, search_literature
from .omim import lookup_omim_gene
from .tools import TOOL_SCHEMAS, dispatch_tool

__all__ = [
    "fetch_literature_passage",
    "search_literature",
    "lookup_omim_gene",
    "TOOL_SCHEMAS",
    "dispatch_tool",
]
