"""
Generic candidate-list operations: reorder + inject.

Adapters call `prioritize_candidates(...)` with their own `key_fn` (extracts
the candidate's identifier — `name`, `tool_id`, `file_path`, etc.) and an
optional `inject_synthesizer` (builds a synthetic candidate for the
canonical when it's missing from the input list).

This is the heart of the framework — both family_dedup.prioritize_query_family
and workflow_intent.prioritize_workflow_by_intent become thin wrappers
around this primitive.
"""
from __future__ import annotations

import copy
from typing import Any, Callable, Dict, List, Optional


def _default_key(c: Any) -> str:
    if isinstance(c, dict):
        return str(c.get("name") or c.get("id") or "")
    return str(getattr(c, "name", None) or getattr(c, "id", "") or "")


def default_synthesizer(template: Any, canonical_id: str) -> Any:
    """Build a synthetic candidate from a template by overwriting its name field.

    Adapters can pass their own synthesizer to add more fields (e.g. fetch
    full row from DB when injecting workflow candidates).
    """
    try:
        new = copy.copy(template)
        if hasattr(new, "__dict__"):
            new.__dict__["name"] = canonical_id
            return new
        if isinstance(new, dict):
            new["name"] = canonical_id
            return new
    except Exception:
        pass

    class _Synth: pass
    s = _Synth()
    s.name = canonical_id
    return s


def prioritize_candidates(candidates: List[Any],
                           canonical_id: str,
                           *,
                           key_fn: Callable[[Any], str] = _default_key,
                           inject_if_missing: bool = False,
                           inject_synthesizer: Optional[Callable[[Any, str], Any]] = None,
                           ) -> List[Any]:
    """Promote the candidate whose `key_fn(c)` matches `canonical_id` to position 0.

    Args:
      candidates: ranked input list. Not mutated.
      canonical_id: the resource to promote.
      key_fn: extracts a comparable identifier from each candidate.
      inject_if_missing: if True and canonical isn't in candidates,
        synthesize one (via inject_synthesizer or default_synthesizer)
        and prepend it.
      inject_synthesizer: callable(template_candidate, canonical_id) → synthetic.

    Returns a new list; never mutates input.
    """
    if not candidates:
        if inject_if_missing:
            # No template available to copy from; build via default synthesizer
            return [default_synthesizer({}, canonical_id)]
        return []

    canonical_id_lc = canonical_id.lower()
    found_idx = None
    for i, c in enumerate(candidates):
        if key_fn(c).lower() == canonical_id_lc:
            found_idx = i
            break

    if found_idx is None:
        if not inject_if_missing:
            return list(candidates)
        synth = (inject_synthesizer or default_synthesizer)(candidates[0], canonical_id)
        return [synth] + list(candidates)

    if found_idx == 0:
        return list(candidates)
    out = list(candidates)
    chosen = out.pop(found_idx)
    out.insert(0, chosen)
    return out


def partition_and_prioritize(candidates: List[Any],
                               target_group_key: str,
                               canonical_id: Optional[str],
                               group_fn: Callable[[Any], str],
                               *,
                               key_fn: Callable[[Any], str] = _default_key,
                               ) -> List[Any]:
    """Move all members of a target group to the head of the list, preserving
    relative order within each group. Then promote the canonical within the
    target group if specified.

    Used by family_dedup.prioritize_query_family — when the user query maps to
    a tool-family (e.g. 'bwa'), all bwa-family wrappers should rank above
    unrelated wrappers, and the canonical bwa wrapper should be top of the
    bwa slice.

    Args:
      candidates: ranked list.
      target_group_key: group identifier the user is asking about (e.g. 'bwa').
      canonical_id: optional canonical resource within the group.
      group_fn: callable(candidate) -> group_key (lowercase string).
      key_fn: callable(candidate) -> identifier (for canonical promotion).

    Returns a new list; never mutates input.
    """
    if not candidates:
        return []
    target_lc = target_group_key.lower()
    in_group, others = [], []
    for c in candidates:
        if group_fn(c).lower() == target_lc:
            in_group.append(c)
        else:
            others.append(c)
    if canonical_id and in_group:
        in_group = prioritize_candidates(in_group, canonical_id, key_fn=key_fn)
    return in_group + others


def dedup_by_group(candidates: List[Any],
                     group_fn: Callable[[Any], str],
                     ) -> List[Any]:
    """Keep the first occurrence of each group_fn(candidate); drop subsequent
    duplicates. Annotates kept items with `_group_member_count` (number of
    candidates that collapsed into this slot).

    Returns a new list; never mutates input.
    """
    seen: Dict[str, int] = {}      # group_key → index in out
    out: List[Any] = []
    for c in candidates:
        g = group_fn(c)
        if not g:
            out.append(_copy_with_tag(c, group_member_count=1))
            continue
        if g in seen:
            # Bump the previously-kept item's count
            prev = out[seen[g]]
            _bump_count(prev)
        else:
            seen[g] = len(out)
            out.append(_copy_with_tag(c, canonical_group=g, group_member_count=1))
    return out


def _copy_with_tag(c: Any, **tags) -> Any:
    """Return a shallow copy of c with extra attributes/keys set."""
    if isinstance(c, dict):
        new = dict(c)
        new.update(tags)
        return new
    new = copy.copy(c)
    for k, v in tags.items():
        setattr(new, k, v)
    return new


def _bump_count(c: Any) -> None:
    if isinstance(c, dict):
        c["group_member_count"] = c.get("group_member_count", 1) + 1
    else:
        setattr(c, "group_member_count", getattr(c, "group_member_count", 1) + 1)
