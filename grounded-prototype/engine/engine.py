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
    limit: int = 8,
) -> GroundedAnswer:
    """Answer a regulated-domain question with provenance and honest boundaries.

    `user` is the requesting tenant — the isolation gate uses it so one user's
    unverified notes never reach another.

    Corpus selection, in priority order:
      * `corpus` given  -> use it verbatim (production injects a tenant-scoped,
        retrieval-backed corpus here).
      * `domain` given  -> load that domain pack (e.g. "cmc", "gmp_steam").
      * neither         -> the original steam pack (back-compat default).
    """
    if corpus is None:
        if domain is not None:
            from .domains import get_corpus
            corpus = get_corpus(domain)
        else:
            corpus = load_corpus()
    scored, isolation = retrieve(question, corpus, requesting_user=user, limit=limit)
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
