"""
Top-level entrypoint: ask() ties classification → retrieval → assembly together,
and render helpers turn a GroundedAnswer into markdown (for chat/UI) or a plain
dict (for the MCP tool result and the frontend API).
"""

from __future__ import annotations

from typing import Dict, List, Optional

from .answer import assemble
from .corpus import load_corpus
from .models import GroundedAnswer, Source, SourceTier
from .retrieve import retrieve


def ask(
    question: str,
    user: str,
    corpus: Optional[List[Source]] = None,
    domain: Optional[str] = None,
    retriever: "Optional[object]" = None,
    limit: int = 8,
) -> GroundedAnswer:
    """Answer a regulated-domain question with provenance and honest boundaries.

    `user` is the requesting tenant — the isolation gate uses it so one user's
    unverified notes never reach another.

    Candidate-source selection, in priority order:
      * `retriever` given -> call retriever.fetch(question, user) for candidates
        (production passes a CompositeRetriever over BioMate's live literature +
        firm records + the curated normative pack; see galaxy.ai.grounded.live).
      * `corpus` given    -> use it verbatim.
      * `domain` given    -> load that domain pack (e.g. "cmc", "gmp_steam").
      * none of the above -> the original steam pack (back-compat default).

    Whatever the source, the SAME scoring + tenant-isolation gate runs over the
    candidates, so the isolation guarantee holds regardless of origin.
    """
    if retriever is not None:
        candidates = retriever.fetch(question, user)
    elif corpus is not None:
        candidates = corpus
    elif domain is not None:
        from .domains import get_corpus
        candidates = get_corpus(domain)
    else:
        candidates = load_corpus()
    scored, isolation = retrieve(question, candidates, requesting_user=user, limit=limit)
    return assemble(question, scored, isolation, requesting_user=user)


# ──────────────────────────────────────────────────────────────────────────────
# Renderers
# ──────────────────────────────────────────────────────────────────────────────

_GRADE_BADGE = {
    "high": "🟢 HIGH",
    "moderate": "🟡 MODERATE",
    "low": "🟠 LOW",
    "not_established": "⛔ NOT ESTABLISHED",
}


def _cite(src: Source) -> str:
    verified = "verified" if src.verified else "UNVERIFIED"
    return f"[{src.tier.short}·{verified}] {src.citation}"


def to_markdown(ans: GroundedAnswer) -> str:
    lines: List[str] = []
    lines.append(f"**Question type:** {ans.question_type.value}  ")
    lines.append(f"**Evidence grade:** {_GRADE_BADGE.get(ans.grade.value, ans.grade.value)}")
    lines.append("")

    grounded = [c for c in ans.claims if c.is_grounded]
    personal = [c for c in ans.claims if c.supporting and not c.is_grounded]

    if grounded:
        lines.append("### What the evidence supports")
        for c in grounded:
            lines.append(f"- {c.text}")
            for s in c.supporting:
                lines.append(f"    - source: {_cite(s)} · `{s.locator or 'n/a'}`")
        lines.append("")

    if ans.boundaries:
        lines.append("### ⚠️ Where the record stops (boundary — not answered from memory)")
        for b in ans.boundaries:
            lines.append(f"- **Not grounded:** {b.question_fragment}")
            lines.append(f"  - Why: {b.reason}")
            if b.escalate_to:
                lines.append("  - Ask the people who actually hold this answer:")
                for e in b.escalate_to:
                    lines.append(f"    - {e}")
            if b.suggested_questions:
                lines.append("  - Concrete questions to put to them:")
                for q in b.suggested_questions:
                    lines.append(f"    - {q}")
        lines.append("")

    if personal:
        lines.append("### Your unverified notes (shown to you only; not evidence)")
        for c in personal:
            lines.append(f"- {c.text}")
        lines.append("")

    if ans.isolation:
        iso = ans.isolation
        lines.append("### Provenance & isolation audit")
        lines.append(f"- requesting user: `{iso.requesting_user}`")
        lines.append(f"- shared/authoritative sources used: {iso.shared_sources_used}")
        lines.append(f"- your own personal notes used (demoted): {iso.own_personal_sources_used}")
        lines.append(
            f"- other users' private notes blocked: {iso.other_tenant_personal_blocked} "
            f"(these are never retrievable by you)"
        )

    return "\n".join(lines)


def to_solicitation(ans: GroundedAnswer, max_questions: int = 3) -> Dict:
    """Convert a GroundedAnswer into the SOLICIT-flow shape (ContextGatherer-compatible).

    This is the bridge between the two systems BioMate already has:
      * the parallel multi-agent SEARCH produces candidate sources;
      * the Grounded trust lattice decides what is actually grounded and where
        the record STOPS (the boundary);
      * when it stops, instead of fabricating, we SOLICIT — in exactly the shape
        `agents/context_gatherer.ContextGatherer.gather_context()` returns
        (`status` + `questions` + `gathered_so_far`), so the existing
        "assistant is soliciting missing information" UI renders it unchanged.

    No boundary -> 'context_complete'. A boundary -> 'need_more_context' with the
    concrete questions to put to a human/deeper search (capped like the solicit
    flow's "max 3 questions at a time"). This generalises the research agent's
    one hardcoded "Please provide…" refusal into a reusable, evidence-driven loop.
    """
    grounded = [c.text for c in ans.claims if c.is_grounded]
    if not ans.boundaries:
        return {
            "status": "context_complete",
            "questions": [],
            "gathered_so_far": grounded,
            "grade": ans.grade.value,
        }
    questions: List[str] = []
    escalate: List[str] = []
    gaps: List[str] = []
    for b in ans.boundaries:
        gaps.append(b.question_fragment)
        questions.extend(b.suggested_questions)
        escalate.extend(b.escalate_to)
    return {
        "status": "need_more_context",
        "reason": "The authoritative record stops at: " + "; ".join(gaps),
        "questions": questions[:max_questions],
        "escalate_to": escalate,
        "gathered_so_far": grounded,
        "grade": ans.grade.value,
    }


def to_dict(ans: GroundedAnswer) -> Dict:
    """Structured result for the MCP tool and the frontend API."""
    return {
        "question": ans.question,
        "question_type": ans.question_type.value,
        "grade": ans.grade.value,
        "summary": ans.summary,
        "claims": [
            {
                "text": c.text,
                "grounded": c.is_grounded,
                "best_tier": c.best_tier.short if c.best_tier else None,
                "sources": [
                    {
                        "id": s.id,
                        "tier": s.tier.short,
                        "tier_label": s.tier.label,
                        "title": s.title,
                        "citation": s.citation,
                        "verified": s.verified,
                        "locator": s.locator,
                    }
                    for s in c.supporting
                ],
            }
            for c in ans.claims
        ],
        "boundaries": [
            {
                "question_fragment": b.question_fragment,
                "reason": b.reason,
                "escalate_to": b.escalate_to,
                "suggested_questions": b.suggested_questions,
            }
            for b in ans.boundaries
        ],
        "isolation": None
        if ans.isolation is None
        else {
            "requesting_user": ans.isolation.requesting_user,
            "shared_sources_used": ans.isolation.shared_sources_used,
            "own_personal_sources_used": ans.isolation.own_personal_sources_used,
            "other_tenant_personal_blocked": ans.isolation.other_tenant_personal_blocked,
            "unverified_demoted": ans.isolation.unverified_demoted,
        },
    }
