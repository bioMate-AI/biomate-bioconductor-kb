"""
Entity canonical resolution adapter — Opportunity 4 from the session-review.

Use case: before calling OMIM / PubMed / ChEMBL retrievers, normalize the
gene/disease/drug entities the user mentioned to their canonical IDs. This
prevents wasted API calls (BRCA1 vs BRCA-1 vs brca1) and ensures retrievers
see the right query terms.

This adapter is shape-different from workflow/memory: it doesn't rerank
candidates — it RETURNS entities to act upon. Demonstrates the framework's
core primitives (YAML load + scan) generalize to non-ranking shapes.
"""
from __future__ import annotations

from pathlib import Path
from typing import Any, Dict, List, Optional

from sandbox.intent_retrieval_v3.core.canonical_resolver import (
    load_canonical_map, resolve_entities,
)

_DEFAULT_YAML = Path(__file__).resolve().parents[1] / "data" / "entity_canonicals.yaml"


def extract_canonical_entities(query: str,
                                  entity_type: Optional[str] = None,
                                  yaml_path: Optional[str] = None,
                                  ) -> List[Dict[str, Any]]:
    """Find and canonicalize biological entities mentioned in the query.

    Args:
      query: natural-language text from the user.
      entity_type: optional filter — only return matches of this type
        ('gene', 'disease', 'drug', 'cell_line', ...). When None, returns all.
      yaml_path: override the default canonical-map YAML.

    Returns:
      List of {canonical_id, entity_type, matched_alias, metadata} dicts.
      Empty list when no entities match. Order is roughly first-mentioned-
      first but is not strictly stable (depends on iteration order of YAML).
    """
    if not query:
        return []
    emap = load_canonical_map(str(yaml_path or _DEFAULT_YAML))
    if not emap:
        return []
    results = resolve_entities(query, emap)
    if entity_type:
        results = [r for r in results if r["entity_type"] == entity_type]
    return results
