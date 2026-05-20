"""
Generic alias-to-canonical resolver. Differs from intent_matcher in shape:

  intent_matcher: query → match an intent → return ONE canonical resource
  canonical_resolver: query → extract entities → return list of canonical IDs

Both share the same YAML loader. The resolver tokenizes/scans the query for
alias occurrences (case-insensitive, word-boundary respecting) and returns
all matches with their canonical IDs, types, and metadata.

Used by adapters/entity.py. Pure function. Cache-loaded YAML.
"""
from __future__ import annotations

import logging
import os
import re
from functools import lru_cache
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

logger = logging.getLogger(__name__)


@lru_cache(maxsize=8)
def load_canonical_map(yaml_path: str) -> Dict[str, Dict[str, Any]]:
    """Load entity-canonical YAML — returns {canonical_id: {entity_type, aliases, ...}}.

    Schema (per top-level key):
        canonical_id:
          entity_type: gene | disease | drug | pathway | ...
          aliases: [...]
          disqualified_if_present: [...]   (optional)
          metadata: {...}                  (optional)

    Returns {} on missing / unparseable YAML.
    """
    path = Path(yaml_path)
    if not path.exists():
        logger.warning("entity YAML not found at %s", path)
        return {}
    try:
        import yaml
    except ImportError:
        logger.warning("pyyaml unavailable; canonical resolver disabled")
        return {}
    try:
        raw = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    except Exception as exc:
        logger.warning("failed to parse %s: %s", path, exc)
        return {}
    out: Dict[str, Dict[str, Any]] = {}
    for cid, entry in raw.items():
        if not entry:
            continue
        out[cid] = {
            "canonical_id": cid,
            "entity_type": entry.get("entity_type", "unknown"),
            "aliases": [str(a).lower().strip() for a in (entry.get("aliases") or []) if a],
            "disqualified_if_present": [str(d).lower().strip()
                                          for d in (entry.get("disqualified_if_present") or []) if d],
            "metadata": entry.get("metadata") or {},
        }
    logger.info("loaded %d canonical entities from %s", len(out), path)
    return out


def _match_alias(query_lc: str, alias_lc: str) -> bool:
    """Word-boundary respecting substring match.

    'brca1' should match 'BRCA1 mutations' but not 'ARLBRCA1X'.
    Hyphens / spaces in the alias must match as-is.
    """
    if not alias_lc:
        return False
    # Build a regex with non-greedy word boundaries on each end.
    # For multi-word aliases ('brca-1'), use literal substring with surrounding
    # non-alphanumeric guards.
    pattern = re.compile(
        r"(?:^|(?<=[^a-zA-Z0-9]))"
        + re.escape(alias_lc)
        + r"(?:$|(?=[^a-zA-Z0-9]))",
        re.IGNORECASE,
    )
    return bool(pattern.search(query_lc))


def resolve_entities(query: str, entity_map: Dict[str, Dict[str, Any]]
                       ) -> List[Dict[str, Any]]:
    """Extract canonical entities mentioned in the query.

    Returns a list of dicts, one per matched entity:
      {canonical_id, entity_type, matched_alias, metadata}

    Honors per-entity `disqualified_if_present`. De-duplicates per canonical_id
    (returns at most one entry per canonical entity even if multiple aliases
    match the same query).
    """
    if not query or not entity_map:
        return []
    q_lc = query.lower()
    out: List[Dict[str, Any]] = []
    seen: set = set()
    for cid, entry in entity_map.items():
        # Check disqualifiers first
        if any(dq in q_lc for dq in entry["disqualified_if_present"]):
            continue
        # Find longest matching alias (prevents 'brca' matching when 'brca1' is the real hit)
        matched_alias = None
        for alias in sorted(entry["aliases"], key=len, reverse=True):
            if _match_alias(q_lc, alias):
                matched_alias = alias
                break
        if matched_alias and cid not in seen:
            seen.add(cid)
            out.append({
                "canonical_id": cid,
                "entity_type": entry["entity_type"],
                "matched_alias": matched_alias,
                "metadata": entry["metadata"],
            })
    return out


def reset_canonical_cache() -> None:
    load_canonical_map.cache_clear()
