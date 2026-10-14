"""
Answer assembly with provenance, GRADE-style confidence, and honest boundaries.

The two behaviours that make this different from a generic chatbot:

  * For a RATIONALE question about a numeric threshold, it builds a PROVENANCE
    CHAIN — what the number is (normative) → how it was set (committee/drafting)
    → the experimental science behind it (literature) → and then explicitly
    NAMES THE GAP where "why exactly this value" leaves the retrievable record,
    routing the user to the humans who actually hold that answer.

  * Unverified personal notes are never allowed to support a confirmed claim;
    the user's own note can be shown, but only flagged as their own unverified
    working note.
"""

from __future__ import annotations

from typing import List, Optional

from .classify import classify
from .models import (
    Boundary,
    Claim,
    EvidenceGrade,
    GroundedAnswer,
    IsolationAudit,
    QuestionType,
    ScoredSource,
    Source,
    SourceTier,
)

# Where to send a user when the public record stops. Generic, honest, and the
# names the blogger herself named: the standards committee and the professional
# societies whose working groups actually set and debate these limits.
_DEFAULT_ESCALATION = [
    "The standard's issuing body / technical committee or secretariat (e.g. the "
    "ICH expert working group, the relevant pharmacopoeia, or CEN) — request the "
    "rationale/derivation annex or the bibliography for this clause",
    "The relevant professional-society working groups (e.g. PDA or ISPE for "
    "manufacturing topics)",
    "A subject-matter expert or working-group member who participated in drafting "
    "the standard",
    "Your internal QA / regulatory-affairs function, weighed against the product's "
    "own validated records",
]


# Generic keywords carry no threshold identity, so they don't establish that two
# sources are about the SAME spec/threshold. Used only for boundary linkage.
_GENERIC_KW = frozenset({
    "threshold", "limit", "why", "impurity", "value", "acceptance", "standard",
    "specification", "mechanism", "load", "basis", "origin", "derivation",
    "rationale", "cutoff", "requirement",
})


def _linked_sources(sources: List[Source], primary: Optional[Source]) -> List[Source]:
    """Sources about the same threshold as `primary` (share a distinctive keyword)."""
    if primary is None:
        return list(sources)
    pk = {k for k in primary.keywords if k not in _GENERIC_KW}
    out = []
    for s in sources:
        if s is primary:
            out.append(s)
            continue
        if {k for k in s.keywords if k not in _GENERIC_KW} & pk:
            out.append(s)
    return out


def _by_tier(sources: List[Source], tier: SourceTier) -> List[Source]:
    return [s for s in sources if s.tier == tier]


def _authoritative(sources: List[Source]) -> List[Source]:
    return [s for s in sources if s.tier.is_authoritative]


def _grade(claims: List[Claim], boundaries: List[Boundary]) -> EvidenceGrade:
    grounded = [c for c in claims if c.is_grounded]
    if not grounded:
        return EvidenceGrade.NOT_ESTABLISHED
    has_primary = any(
        s.tier == SourceTier.NORMATIVE_PRIMARY for c in grounded for s in c.supporting
    )
    # A boundary means the central ask ("why this exact number") is not fully
    # grounded — cap the headline confidence at MODERATE even if the normative
    # and mechanistic pieces are strong. Honesty over a green checkmark.
    if boundaries:
        return EvidenceGrade.MODERATE if has_primary else EvidenceGrade.LOW
    return EvidenceGrade.HIGH if has_primary else EvidenceGrade.MODERATE


def _personal_aside(sources: List[Source], user: str) -> List[Claim]:
    """The user's OWN unverified notes, surfaced but clearly demoted."""
    out: List[Claim] = []
    for s in sources:
        if s.tier == SourceTier.UNVERIFIED_PERSONAL and s.owner == user:
            out.append(
                Claim(
                    text=(
                        f"Your own working note (UNVERIFIED — not evidence): “{s.text}” "
                        f"Treat as a hypothesis to confirm, not a confirmed result."
                    ),
                    supporting=[s],
                )
            )
    return out


def assemble(
    question: str,
    scored: List[ScoredSource],
    isolation: IsolationAudit,
    requesting_user: str,
) -> GroundedAnswer:
    qtype, _conf = classify(question)
    sources = [s.source for s in scored]
    claims: List[Claim] = []
    boundaries: List[Boundary] = []

    normative = _by_tier(sources, SourceTier.NORMATIVE_PRIMARY)
    literature = _by_tier(sources, SourceTier.PEER_REVIEWED)
    org = _by_tier(sources, SourceTier.ORG_VALIDATED)

    # Split normative sources into "the limit itself" vs "the drafting basis"
    # using a keyword marker on the source — keeps the chain explicit.
    drafting = [s for s in normative if "committee" in s.keywords or "derivation" in s.keywords]
    limit_clause = [s for s in normative if s not in drafting]

    if qtype == QuestionType.RATIONALE:
        # ── 1. What the number IS (normative) ────────────────────────────
        if limit_clause:
            claims.append(Claim(
                text=(
                    "What the standard states (the requirement itself): "
                    + limit_clause[0].text
                ),
                supporting=limit_clause,
            ))
        # ── 2. The SCIENCE behind it (mechanism; literature) ─────────────
        if literature:
            claims.append(Claim(
                text=(
                    "Why a limit of this kind exists (documented mechanism): "
                    + literature[0].text
                ),
                supporting=literature,
            ))
            if len(literature) > 1:
                claims.append(Claim(
                    text="Further experimental evidence: " + literature[1].text,
                    supporting=[literature[1]],
                ))
        # ── 3. HOW the figure was set (committee / drafting record) ──────
        if drafting:
            claims.append(Claim(
                text=(
                    "How the specific figure was arrived at (process, not a "
                    "re-derivation): " + drafting[0].text
                ),
                supporting=drafting,
            ))
        # ── 4. The BOUNDARY — the honest edge ────────────────────────────
        # Two distinct honest edges, driven by explicit source markers:
        #   * no `exact_derivation` source  -> the exact figure is pragmatic/
        #     convention (steam EN 285, ICH Q3A %): name that it is not derived.
        #   * an `exact_derivation` source AND a `critique` source -> the figure
        #     IS derived but the derivation is actively contested (ICH M7 TTC):
        #     surface the debate instead of a false "settled" HIGH.
        # A derived, uncontested figure (would be) returned with no boundary.
        # Assess the boundary only against sources about the SAME threshold as
        # the top (primary) result — a derivation marker on an unrelated
        # threshold in the same domain must not suppress another's boundary.
        # Linkage = sharing a distinctive (non-generic) keyword with the primary.
        primary = sources[0] if sources else None
        linked = _linked_sources(sources, primary)
        exact_derivation = any("exact_derivation" in s.keywords for s in linked)
        contested = any(
            ("critique" in s.keywords or "contested" in s.keywords) for s in linked
        )
        if not exact_derivation:
            boundaries.append(Boundary(
                question_fragment=(
                    "the primary justification for the EXACT numeric value "
                    "(as opposed to the existence and direction of the limit)"
                ),
                reason=(
                    "The retrievable record supports the mechanism and the "
                    "existence of the limit, but it indicates the exact figure is a "
                    "harmonized expert/working-group convention (set pragmatically, "
                    "from accumulated experience and an accepted risk/qualification "
                    "burden) rather than derived to a specific number from a single "
                    "controlled study. A first-principles derivation of the exact "
                    "cut-off is not in the retrieved record; anyone asserting that "
                    "precise derivation from memory is speculating."
                ),
                escalate_to=list(_DEFAULT_ESCALATION),
                suggested_questions=[
                    "Does the standard have a published rationale annex or a "
                    "bibliography for this clause?",
                    "Which revision introduced this figure, and what changed from "
                    "the prior edition?",
                    "What risk/qualification model (dose, exposure, safety margin) "
                    "did the working group use to fix this value?",
                    "Are there inter-laboratory or round-robin studies cited in the "
                    "background record?",
                ],
            ))
        elif contested:
            boundaries.append(Boundary(
                question_fragment=(
                    "whether the derivation of this figure is settled (it is "
                    "documented, but actively contested)"
                ),
                reason=(
                    "Unlike a pragmatic limit, this figure HAS a documented "
                    "quantitative derivation — but that derivation is actively "
                    "debated in the peer-reviewed literature (a critique was "
                    "retrieved above). Treat the figure as the current harmonized "
                    "position, not as settled science: the derivation and its "
                    "published critique must be weighed together, not one asserted "
                    "as final."
                ),
                escalate_to=[
                    "The guideline's expert working group (e.g. the ICH EWG) — "
                    "confirm the current status of the derivation and any revision",
                    "Weigh the primary derivation against the peer-reviewed critique "
                    "before relying on the exact value",
                    "Your internal toxicology / regulatory-affairs function for a "
                    "compound-specific risk assessment where justified",
                ],
                suggested_questions=[
                    "What assumptions in the derivation does the critique challenge, "
                    "and do they apply to this compound/class?",
                    "Is a compound-specific or structural-class-based limit "
                    "justifiable instead of the default figure?",
                ],
            ))

    elif qtype == QuestionType.NORMATIVE:
        if limit_clause or org:
            support = (limit_clause or org)
            # Attach only the top (primary) source: a normative "what is the
            # requirement" answer is grounded by the single most-relevant clause,
            # not by every clause in the domain.
            claims.append(Claim(
                text="The applicable requirement: " + support[0].text,
                supporting=support[:1],
            ))
        if org:
            claims.append(Claim(
                text="How we apply it on site: " + org[0].text,
                supporting=org,
            ))

    elif qtype == QuestionType.INVESTIGATION:
        if org:
            claims.append(Claim(
                text="Validated procedure / acceptance basis to check first: " + org[0].text,
                supporting=org,
            ))
        if normative:
            claims.append(Claim(
                text="The limit the result is judged against: " + normative[0].text,
                supporting=normative,
            ))
        if literature:
            claims.append(Claim(
                text="Mechanistic directions for root cause: " + literature[0].text,
                supporting=literature,
            ))

    else:  # DEFINITION / UNKNOWN
        best = _authoritative(sources)
        if best:
            claims.append(Claim(text=best[0].text, supporting=best[:1]))
        else:
            boundaries.append(Boundary(
                question_fragment="this question",
                reason=(
                    "No authoritative source (standard, peer-reviewed study, or "
                    "QA-approved document) was retrieved for this question, so the "
                    "assistant will not answer from memory."
                ),
                escalate_to=list(_DEFAULT_ESCALATION),
            ))

    # Always surface the user's own unverified notes — clearly demoted, never
    # as support for the claims above.
    claims.extend(_personal_aside(sources, requesting_user))

    grade = _grade([c for c in claims if c.is_grounded or c.supporting], boundaries)

    return GroundedAnswer(
        question=question,
        question_type=qtype,
        grade=grade,
        claims=claims,
        boundaries=boundaries,
        isolation=isolation,
    )
