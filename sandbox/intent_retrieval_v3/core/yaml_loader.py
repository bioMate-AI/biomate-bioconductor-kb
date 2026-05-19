"""
Cached YAML loader for intent-retrieval data files.

Both family_dedup.py and workflow_intent.py reimplement essentially the same
YAML-loading boilerplate (lru_cache, fallback to empty dict on missing file,
graceful degradation when pyyaml isn't installed). Factor it out here.

Two loaders are provided:

  load_intent_map(yaml_path)
      For YAMLs whose top-level dict maps `intent_id -> {canonical, trigger_terms,
      disqualified_if_present, pipeline_intent_required, ...}`. Returns the parsed
      list of intent entries (one per top-level key).

  load_alias_map(yaml_path)
      For YAMLs whose top-level dict maps `canonical_id -> [fragment_1, fragment_2, ...]`.
      Returns a flat dict mapping fragment -> canonical, with transitive chain
      resolution and cycle detection (matches family_dedup.py exactly).
"""
from __future__ import annotations

import logging
import os
from functools import lru_cache
from pathlib import Path
from typing import Any, Dict, List, Optional

logger = logging.getLogger(__name__)


def _safe_load_yaml(path: Path) -> Optional[Any]:
    """Read a YAML file; return None on any failure (logged at WARNING)."""
    if not path.exists():
        logger.warning("YAML not found at %s", path)
        return None
    try:
        import yaml
    except ImportError:
        logger.warning("pyyaml not installed; loader returning empty")
        return None
    try:
        return yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    except Exception as exc:
        logger.warning("failed to parse %s: %s", path, exc)
        return None


@lru_cache(maxsize=8)
def load_intent_map(yaml_path: str) -> List[Dict[str, Any]]:
    """Load intent-map YAML — produces a list of {intent_id, canonical, ...}.

    Schema expected at top level:
        intent_id_1:
          canonical: <resource_id>
          trigger_terms: [...]
          disqualified_if_present: [...]
          pipeline_intent_required: bool  (optional, default False)
          # any additional domain-specific fields are preserved verbatim

    Returns [] on missing / unparseable YAML.
    """
    raw = _safe_load_yaml(Path(yaml_path))
    if not raw:
        return []

    out: List[Dict[str, Any]] = []
    for intent_id, entry in raw.items():
        if not entry or not entry.get("canonical"):
            continue
        normalized = {
            "intent_id": intent_id,
            "canonical": str(entry["canonical"]).strip(),
            "trigger_terms": [str(t).lower().strip()
                              for t in (entry.get("trigger_terms") or []) if t],
            "disqualified_if_present": [str(t).lower().strip()
                                          for t in (entry.get("disqualified_if_present") or []) if t],
            "pipeline_intent_required": bool(entry.get("pipeline_intent_required", False)),
        }
        # Preserve any extra fields the adapter may need (e.g. "domain", "workflow_mode")
        for k, v in entry.items():
            if k not in normalized and k not in ("trigger_terms", "disqualified_if_present",
                                                  "pipeline_intent_required", "canonical"):
                normalized[k] = v
        out.append(normalized)
    logger.info("loaded %d intent entries from %s", len(out), yaml_path)
    return out


@lru_cache(maxsize=8)
def load_alias_map(yaml_path: str) -> Dict[str, str]:
    """Load alias-map YAML — produces flat dict `fragment_lc -> canonical_lc`.

    Schema expected at top level:
        canonical_a:
          - fragment_1
          - fragment_2
        canonical_b:
          - fragment_3

    Transitive chains are resolved (a -> b, b -> c becomes a -> c). Cycles
    are detected and bounded to prevent infinite loops.

    Returns {} on missing / unparseable YAML.
    """
    raw = _safe_load_yaml(Path(yaml_path))
    if not raw:
        return {}

    flat: Dict[str, str] = {}
    for canonical, fragments in raw.items():
        if not canonical:
            continue
        canon_lc = str(canonical).lower().strip()
        for frag in (fragments or []):
            frag_lc = str(frag).lower().strip()
            if frag_lc and frag_lc != canon_lc:
                flat[frag_lc] = canon_lc

    # Resolve transitive chains, bounded depth, cycle-safe
    for k in list(flat.keys()):
        seen = {k}
        v = flat[k]
        steps = 0
        while v in flat and v not in seen and steps < 8:
            seen.add(v)
            v = flat[v]
            steps += 1
        if v != flat[k]:
            flat[k] = v
    logger.info("loaded %d alias mappings from %s", len(flat), yaml_path)
    return flat


def reset_loader_cache() -> None:
    """Clear all loader caches. Useful in tests."""
    load_intent_map.cache_clear()
    load_alias_map.cache_clear()
