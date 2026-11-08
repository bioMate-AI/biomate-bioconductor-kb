"""
Tenant-isolated, tier-aware retrieval.

This is where the SECOND boundary from the video lives: one user's unverified
notes must never reach another user. The isolation rule is enforced here, once,
and the :class:`IsolationAudit` records exactly what was admitted and blocked so
the property is observable in the answer rather than taken on faith.

Scoring is a transparent keyword/word-overlap score — deliberately simple and
inspectable for the prototype. In production this becomes BioMate's existing
dense-vector retrieval (UnifiedWorkflowSearch / VectorToolSearch), but the
isolation filter stays exactly here and stays the same shape.
"""

from __future__ import annotations

import re
from typing import List, Tuple

from .models import IsolationAudit, ScoredSource, Source, SourceTier

_WORD = re.compile(r"[a-z0-9.]+")

# Content-word scoring: common function words carry no topical signal and, left
# in, let an off-topic query ("what colour should the sterilizer be painted")
# score on incidental "the"/"be" overlap. Dropped before overlap is computed.
_STOPWORDS = frozenset(
    "the a an of to for in on and or that this it is are was were be been being "
    "do does did what which who whom how why when where should would could can "
    "may might will shall we i you they he she our your its their my me us".split()
)


def _tokens(text: str) -> List[str]:
    return [t for t in _WORD.findall(text.lower()) if t not in _STOPWORDS and len(t) > 1]


def _score(query: str, source: Source) -> float:
    q = set(_tokens(query))
    if not q:
        return 0.0
    kw = set(k.lower() for k in source.keywords)
    body = set(_tokens(source.title + " " + source.text))

    # Keyword hits are worth more than body hits; title/body overlap fills in.
    kw_hits = len(q & kw)
    body_hits = len(q & body)
    score = 2.0 * kw_hits + 0.5 * body_hits

    # Numeric-threshold queries ("why 0.95") should privilege sources that carry
    # the number — this is the "rooted / provenance of the number" case.
    numbers = {t for t in q if any(c.isdigit() for c in t)}
    if numbers and (numbers & (kw | body)):
        score += 1.5
    return score


def retrieve(
    query: str,
    corpus: List[Source],
    requesting_user: str,
    limit: int = 8,
    min_score: float = 1.0,
) -> Tuple[List[ScoredSource], IsolationAudit]:
    """Return (ranked sources visible to this user, isolation audit).

    Visibility rule (the invariant):
      * Shared sources (owner is None) are visible to everyone.
      * A personal/unverified source is visible ONLY to its owner.
      * Nothing else is ever visible.

    The rule is applied before scoring, so an out-of-tenant personal note can
    never even be ranked, let alone surfaced.
    """
    audit = IsolationAudit(requesting_user=requesting_user)
    visible: List[ScoredSource] = []

    for src in corpus:
        # ── isolation gate ────────────────────────────────────────────────
        if src.owner is not None and src.owner != requesting_user:
            # Another tenant's private content. Never visible. Count the block.
            if src.tier == SourceTier.UNVERIFIED_PERSONAL:
                audit.other_tenant_personal_blocked += 1
            continue

        score = _score(query, src)
        if score < min_score:
            # Below the relevance floor: an incidental single-word overlap is
            # noise, not an answer. Dropping it is what stops the assembler from
            # dressing up a loosely-related standard as if it answered the ask.
            continue

        if src.owner == requesting_user and src.tier == SourceTier.UNVERIFIED_PERSONAL:
            audit.own_personal_sources_used += 1
        elif src.owner is None:
            audit.shared_sources_used += 1

        if src.tier == SourceTier.UNVERIFIED_PERSONAL or not src.verified:
            audit.unverified_demoted += 1

        visible.append(ScoredSource(source=src, score=score))

    # Rank by score, then by tier authority (lower tier int == more authoritative)
    # so that at equal relevance the standard beats the SOP beats the note.
    visible.sort(key=lambda s: (-s.score, s.source.tier.value))
    return visible[:limit], audit
