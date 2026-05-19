"""
Wrapper-level result dedup by canonical tool family.

Productized from `sandbox/retrieval_v2/`. The Phase 1.5 A/B benchmark
(docs/20260518_PHASE1_AB_RESULTS_AND_DECISION.md) showed that applying a
curated wrapper→canonical-family alias map to retrieval results lifts top-1
accuracy by ~16pp on the 30-query suite eval. This module is the
production-ready library form of that work.

Public API
----------

    load_alias_map(yaml_path=None) -> dict[str, str]
        Read `backend/database/tool_family_aliases.yaml` once at startup;
        return a flat dict mapping fragment family_key → canonical family_key.

    canonical_family_key(tool_id, name, alias_map) -> str
        Compute the canonical family key for a single wrapper, applying both
        path-regex extraction (matching the sandbox cluster_tools logic) and
        the alias map.

    dedup_results_by_family(results, alias_map, *, name_key='name',
                              tool_id_key='tool_id') -> list
        Given a list of result dicts (from any FTS/embedding search over the
        Galaxy tool catalog), deduplicate so each canonical family appears
        only once, preserving the highest-ranked wrapper as the representative.
        Adds two fields to each kept result:
          - `canonical_family_id`: the canonical family key
          - `family_member_count`: how many wrappers in this family were merged

This module has **no caller wiring**. Integration is opt-in — see
`docs/20260518_FAMILY_DEDUP_INTEGRATION_GUIDE.md` for which call sites
benefit and how to adopt.

The alias-map data file is at `backend/database/tool_family_aliases.yaml`;
edit it to add new families without code changes.
"""
from __future__ import annotations

import logging
import re
from functools import lru_cache
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

logger = logging.getLogger(__name__)

_DEFAULT_ALIAS_YAML = (
    Path(__file__).resolve().parents[4]
    / "config"
    / "tool_family_aliases.yaml"
)
_DEFAULT_CANONICAL_YAML = (
    Path(__file__).resolve().parents[4]
    / "config"
    / "tool_family_canonical.yaml"
)

# ─── Path-regex extraction (mirrors sandbox/retrieval_v2/scripts/cluster_tools)
# Kept verbatim so production behavior matches the validated A/B results.
_PLUGIN_PREFIXES: Tuple[str, ...] = (
    "data_manager_", "aurora_", "cp_", "ctat_", "enhanced_", "demo_",
)
_FUNCTION_SUFFIXES: Tuple[str, ...] = (
    "_index_builder", "_indexer", "_index", "_to_bed", "_to_bedgraph",
    "_to_peaks", "_to_sam", "_wrappers", "_wrapper", "_site",
)
_MAP_WITH_PAT = re.compile(r"^map[-_ ]with[-_ ]", re.IGNORECASE)
_VERSION_PAT = re.compile(r"[-_ ](v?\d+[\.\d]*(?:\+galaxy\d*)?)$", re.IGNORECASE)


def _strip_plugin_prefix(s: str) -> str:
    for p in _PLUGIN_PREFIXES:
        if s.startswith(p):
            return s[len(p):]
    return s


def _strip_function_suffix(s: str) -> str:
    for suf in _FUNCTION_SUFFIXES:
        if s.endswith(suf):
            return s[: -len(suf)]
    return s


def _normalize_family(raw: str) -> str:
    s = raw.lower()
    s = _MAP_WITH_PAT.sub("", s)
    s = _VERSION_PAT.sub("", s)
    s = _strip_plugin_prefix(s)
    s = _strip_function_suffix(s)
    s = s.strip("_-. ")
    return s or raw.lower()


def _extract_family_from_path(tool_id: str, name: str) -> str:
    """Mirror of sandbox's _extract_family_and_function (family only)."""
    tid = (tool_id or "").strip()

    if tid.startswith("toolshed."):
        parts = tid.split("/")
        if len(parts) >= 5 and parts[1] == "repos":
            return _normalize_family(parts[3])

    if tid.startswith("nfcore/"):
        parts = tid.split("/", 2)
        return _normalize_family(parts[1]) if len(parts) > 1 else "nfcore_unknown"

    if tid.startswith("biomate/"):
        parts = tid.split("/", 2)
        return _normalize_family(parts[1]) if len(parts) > 1 else "biomate_unknown"

    if tid.startswith("bioconductor/"):
        parts = tid.split("/", 1)
        return f"bioconductor:{_normalize_family(parts[1])}"

    base = name or (tid.split("/")[-1] if "/" in tid else tid)
    return _normalize_family(_strip_function_suffix(base))


# ─── Public API ─────────────────────────────────────────────────────────

@lru_cache(maxsize=4)
def load_alias_map(yaml_path: Optional[str] = None) -> Dict[str, str]:
    """Load fragment→canonical family alias map from YAML.

    Cached so subsequent calls are zero-cost. Pass an explicit path or set
    `BIOMATE_FAMILY_ALIASES` env var to override the default location.
    Returns an empty dict (degrading gracefully) if the file is missing
    or pyyaml is unavailable — callers always get a valid mapping object.
    """
    import os
    path = Path(yaml_path or os.environ.get(
        "BIOMATE_FAMILY_ALIASES", str(_DEFAULT_ALIAS_YAML)
    ))
    if not path.exists():
        logger.warning("family alias YAML not found at %s; using empty map", path)
        return {}
    try:
        import yaml
    except ImportError:
        logger.warning("pyyaml not installed; family aliasing disabled")
        return {}

    try:
        raw = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    except Exception as exc:
        logger.warning("failed to parse %s: %s", path, exc)
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

    # Resolve any transitive chains (a→b, b→c becomes a→c) up to a small
    # bound. Detects cycles and breaks them rather than looping forever.
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
        if v in seen and v != flat[k]:
            logger.warning("alias cycle detected for %s; using %s", k, v)

    logger.info("loaded %d family alias rules from %s", len(flat), path)
    return flat


def canonical_family_key(tool_id: str, name: str = "",
                           alias_map: Optional[Dict[str, str]] = None) -> str:
    """Return the canonical family_key for a single wrapper.

    Combines path-regex extraction with the alias map. If `alias_map` is
    None, loads the default map (cached).
    """
    if alias_map is None:
        alias_map = load_alias_map()
    raw = _extract_family_from_path(tool_id or "", name or "")
    return alias_map.get(raw.lower(), raw)


@lru_cache(maxsize=4)
def load_canonical_map(yaml_path: Optional[str] = None) -> Dict[str, str]:
    """Load family_id → canonical wrapper_tool_id map.

    The canonical wrapper for each family is the one that should outrank
    its same-family siblings in search results. Read once at startup;
    cached. Returns empty dict on missing file or parse error.
    """
    import os
    path = Path(yaml_path or os.environ.get(
        "BIOMATE_FAMILY_CANONICAL", str(_DEFAULT_CANONICAL_YAML)
    ))
    if not path.exists():
        logger.warning("canonical YAML not found at %s; reranker is a no-op", path)
        return {}
    try:
        import yaml
    except ImportError:
        logger.warning("pyyaml not installed; canonical reranker disabled")
        return {}
    try:
        raw = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    except Exception as exc:
        logger.warning("failed to parse %s: %s", path, exc)
        return {}
    # Flatten: family_id (lowercased) → wrapper_tool_id (unchanged).
    flat: Dict[str, str] = {}
    for fam, wid in raw.items():
        if fam and wid:
            flat[str(fam).lower().strip()] = str(wid).strip()
    logger.info("loaded %d canonical wrapper mappings from %s", len(flat), path)
    return flat


def rerank_to_canonical(results: List[Dict[str, Any]],
                          alias_map: Optional[Dict[str, str]] = None,
                          canonical_map: Optional[Dict[str, str]] = None,
                          *,
                          name_key: str = "name",
                          tool_id_key: str = "tool_id") -> List[Dict[str, Any]]:
    """Promote the canonical wrapper of each family to position 1 of its
    family group, preserving relative order between distinct families.

    Pure function: returns a new list, doesn't mutate inputs. Adds a
    `canonical_family_id` field to each item (tag-only; does NOT collapse
    duplicates — use dedup_results_by_family for that).

    Use case: when an FTS-ranked result list has the right family at the
    top but the wrong wrapper variant in position 1 (e.g. "Picard
    RevertSam" outranks "Picard MarkDuplicates"), the reranker swaps in
    the canonical wrapper if present anywhere in the result list.

    Does NOT add wrappers that weren't in the input list — i.e. it only
    reorders within what FTS returned.
    """
    if alias_map is None:
        alias_map = load_alias_map()
    if canonical_map is None:
        canonical_map = load_canonical_map()
    if not results or not canonical_map:
        # Pass through with family tags
        return [
            {**r, "canonical_family_id":
             canonical_family_key(str(r.get(tool_id_key) or ""),
                                  str(r.get(name_key) or ""), alias_map)}
            for r in results
        ]

    # Tag every result with its canonical family
    tagged: List[Dict[str, Any]] = []
    for r in results:
        tid = str(r.get(tool_id_key) or "")
        nm = str(r.get(name_key) or "")
        fam = canonical_family_key(tid, nm, alias_map)
        tagged.append({**r, "canonical_family_id": fam})

    # Within each family, move the canonical wrapper (if present) to the
    # head of that family's slice. Preserve inter-family order via stable
    # iteration over the original list.
    seen_family_first_idx: Dict[str, int] = {}
    for i, r in enumerate(tagged):
        fam = r["canonical_family_id"]
        if fam not in seen_family_first_idx:
            seen_family_first_idx[fam] = i

    # For each family that has a canonical mapping, find the canonical
    # wrapper in tagged[] and move it to the family's first-occurrence index.
    out = list(tagged)
    for fam, canonical_tid in canonical_map.items():
        if fam not in seen_family_first_idx:
            continue
        first_idx = seen_family_first_idx[fam]
        # Find the canonical wrapper anywhere in the result list
        canonical_idx = None
        for j, r in enumerate(out):
            if r["canonical_family_id"] == fam and \
               str(r.get(tool_id_key) or "") == canonical_tid:
                canonical_idx = j
                break
        if canonical_idx is None or canonical_idx == first_idx:
            continue  # canonical not in results, or already at the head
        # Swap: canonical goes to family-first-idx, current head shifts down
        out[first_idx], out[canonical_idx] = out[canonical_idx], out[first_idx]
    return out


def _infer_target_family(query: str, alias_map: Dict[str, str],
                          canonical_map: Dict[str, str]) -> Optional[str]:
    """Given a free-text query, guess which canonical family the user is asking for.

    Returns a family_id if the query contains a token that maps to a known
    family (via alias map or canonical map keys), else None.
    """
    if not query:
        return None
    tokens = re.findall(r"[a-zA-Z][a-zA-Z0-9_]+", query.lower())
    known_families = set(canonical_map.keys())
    # Direct token match against known families
    for tok in tokens:
        if tok in known_families:
            return tok
    # Try alias map: any token that maps to a canonical family
    for tok in tokens:
        canonical = alias_map.get(tok)
        if canonical and canonical in known_families:
            return canonical
    return None


def prioritize_query_family(query: str, results: List[Dict[str, Any]],
                              alias_map: Optional[Dict[str, str]] = None,
                              canonical_map: Optional[Dict[str, str]] = None,
                              *,
                              name_key: str = "name",
                              tool_id_key: str = "tool_id") -> List[Dict[str, Any]]:
    """Boost the query-matching family above unrelated families, then within
    that family promote the canonical wrapper to position 1.

    Use case: when a user types "samtools", they expect a samtools tool at
    rank 1 — not whatever unrelated tool BM25 happens to favor because it
    mentions samtools in its help_text.

    Algorithm:
      1. Identify the target family from the query (alias map / canonical map keys).
      2. Partition results into [target_family_members, other_results],
         preserving relative order within each group.
      3. Move the canonical wrapper of target_family to position 0 if present.

    No-op if the query doesn't match any known family. Pure function.
    """
    if alias_map is None:
        alias_map = load_alias_map()
    if canonical_map is None:
        canonical_map = load_canonical_map()
    if not results:
        return []

    target = _infer_target_family(query, alias_map, canonical_map)
    # Always tag with canonical_family_id for downstream consumers
    tagged = [
        {**r, "canonical_family_id":
         canonical_family_key(str(r.get(tool_id_key) or ""),
                              str(r.get(name_key) or ""), alias_map)}
        for r in results
    ]
    if target is None:
        return tagged

    # Partition: target-family first, others after (stable)
    target_results = [r for r in tagged if r["canonical_family_id"] == target]
    other_results = [r for r in tagged if r["canonical_family_id"] != target]

    # Within target_results, promote canonical wrapper if present
    canonical_tid = canonical_map.get(target)
    if canonical_tid:
        canonical_idx = None
        for i, r in enumerate(target_results):
            if str(r.get(tool_id_key) or "") == canonical_tid:
                canonical_idx = i
                break
        if canonical_idx is not None and canonical_idx > 0:
            chosen = target_results.pop(canonical_idx)
            target_results.insert(0, chosen)

    return target_results + other_results


def dedup_results_by_family(results: List[Dict[str, Any]],
                              alias_map: Optional[Dict[str, str]] = None,
                              *,
                              name_key: str = "name",
                              tool_id_key: str = "tool_id") -> List[Dict[str, Any]]:
    """Dedup a ranked list of search results by canonical family.

    Input: a list of result dicts in rank order (most relevant first). Each
    dict must contain at least `tool_id_key` and/or `name_key`.

    Output: same list with duplicates removed (keeping the highest-ranked
    representative of each family). Two new fields are added per kept result:
      - canonical_family_id
      - family_member_count (always ≥ 1)

    The function is non-destructive — original dicts are not mutated;
    shallow copies are returned. Items with no extractable family are kept
    verbatim (each treated as its own singleton family).
    """
    if alias_map is None:
        alias_map = load_alias_map()

    seen: Dict[str, int] = {}      # family_key → index in `out`
    out: List[Dict[str, Any]] = []

    for r in results:
        tid = str(r.get(tool_id_key) or "")
        nm = str(r.get(name_key) or "")
        if not tid and not nm:
            # Can't classify — keep as singleton without family tag
            keep = dict(r); keep.setdefault("canonical_family_id", None)
            keep.setdefault("family_member_count", 1)
            out.append(keep); continue
        family = canonical_family_key(tid, nm, alias_map)
        if family in seen:
            out[seen[family]]["family_member_count"] += 1
        else:
            keep = dict(r)
            keep["canonical_family_id"] = family
            keep["family_member_count"] = 1
            seen[family] = len(out)
            out.append(keep)
    return out
