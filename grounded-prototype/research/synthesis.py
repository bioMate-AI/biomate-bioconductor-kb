"""
Research synthesis — turn gathered multi-source evidence into a structured,
grounded, multi-claim answer.

The Grounded engine's `assemble()` is tuned for a SINGLE threshold/clause
question (its branches emit one or two claims). A deep-research question is
multi-part, so synthesis here produces one grounded claim PER authoritative piece
of evidence, labelled by the sub-question it answered and ordered by trust tier
(normative A -> peer-reviewed B -> org-validated C), then adds:
  * a boundary for any sub-question still UNRESOLVED when the budget ran out;
  * the requesting user's own unverified notes, clearly demoted;
  * the provenance/isolation audit.

Reuses the Grounded models + grade logic, so it renders through the same
to_markdown()/to_dict().
"""

from __future__ import annotations

from typing import Dict, List, Optional, Set

from engine.answer import _grade
from engine.models import (
    Boundary, Claim, GroundedAnswer, IsolationAudit, QuestionType, Source, SourceTier,
)

_ESCALATE = [
    "Widen the search budget or add a higher-authority source for this sub-question",
    "A subject-matter expert / the standard's issuing body for the unresolved point",
]


def synthesize(
    question: str,
    sources: List[Source],
    isolation: Optional[IsolationAudit],
    *,
    requesting_user: str = "anonymous",
    open_gaps: Optional[List[str]] = None,
    provenance: Optional[Dict[str, Set[str]]] = None,
) -> GroundedAnswer:
    provenance = provenance or {}
    authoritative = [s for s in sources if s.tier.is_authoritative]
    own_personal = [
        s for s in sources
        if s.tier == SourceTier.UNVERIFIED_PERSONAL and s.owner == requesting_user
    ]

    # Order by trust tier, then keep a stable order; dedup by id.
    seen: Set[str] = set()
    ordered: List[Source] = []
    for s in sorted(authoritative, key=lambda s: s.tier.value):
        if s.id not in seen:
            seen.add(s.id); ordered.append(s)

    claims: List[Claim] = []
    for s in ordered:
        subqs = provenance.get(s.id) or set()
        theme = f"[{sorted(subqs)[0][:60]}] " if subqs else ""
        claims.append(Claim(text=theme + s.text, supporting=[s]))

    boundaries: List[Boundary] = []
    if open_gaps:
        boundaries.append(Boundary(
            question_fragment="; ".join(open_gaps),
            reason=("these sub-questions were still unresolved when the research "
                    "budget was reached — not grounded to sufficiency, so treat as open."),
            escalate_to=list(_ESCALATE),
            suggested_questions=list(open_gaps),
        ))
    if not claims:
        boundaries.append(Boundary(
            question_fragment=question,
            reason=("no authoritative evidence was gathered; the assistant will not "
                    "answer this from memory."),
            escalate_to=list(_ESCALATE),
        ))

    # Demoted: the user's own unverified notes (never grounding a claim).
    for s in own_personal:
        claims.append(Claim(
            text=f"Your unverified note (not evidence): {s.text}",
            supporting=[s],
        ))

    grade = _grade([c for c in claims if c.is_grounded], boundaries)
    return GroundedAnswer(
        question=question,
        question_type=QuestionType.UNKNOWN,   # multi-part research question
        grade=grade,
        claims=claims,
        boundaries=boundaries,
        isolation=isolation,
    )
