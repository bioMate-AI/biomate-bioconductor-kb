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

from typing import List

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
    "The standard's technical committee / secretariat (e.g. CEN/TC 102 for EN 285) "
    "— request the rationale annex or the working-group background references",
    "PDA (Parenteral Drug Association) technical-report working groups",
    "ISPE (sterilization / utilities) communities of practice",
    "A member of the standards working group or an SME who participated in drafting",
]


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
        # ── 4. The BOUNDARY — the part we cannot ground ──────────────────
        # This fires whenever the exact numeric derivation isn't itself a
        # retrievable primary study. For the prototype corpus that is always
        # true (by design), which is the realistic case the blogger hit.
        exact_value_grounded = any(
            "derivation" in s.keywords and s.tier == SourceTier.PEER_REVIEWED
            for s in sources
        )
        if not exact_value_grounded:
            boundaries.append(Boundary(
                question_fragment=(
                    "the primary justification for the EXACT numeric value "
                    "(as opposed to the existence and direction of the limit)"
                ),
                reason=(
                    "The retrievable record supports the mechanism and the "
                    "existence of the limit, but the published sources indicate the "
                    "exact figure was 'established pragmatically' by the originating "
                    "working groups (for EN 285 steam quality: the UK NHS lineage "
                    "HTM 101 -> HTM 2010 -> SHTM 2010/2031) rather than derived to a "
                    "specific number from a single controlled experiment. The fullest "
                    "available rationale is the derivation paper and the committee "
                    "history; a first-principles experimental derivation of the exact "
                    "cut-off is not in the retrieved record. Anyone asserting that "
                    "precise derivation from memory is speculating."
                ),
                escalate_to=list(_DEFAULT_ESCALATION),
                suggested_questions=[
                    "Does the standard have a published rationale annex or a "
                    "bibliography for this clause?",
                    "Which revision introduced this figure, and what changed from "
                    "the prior edition?",
                    "What acceptance-risk model (load type, bioburden, safety "
                    "margin) did the committee use to fix this value?",
                    "Are there round-robin or inter-laboratory studies cited in "
                    "the committee record?",
                ],
            ))

    elif qtype == QuestionType.NORMATIVE:
        if limit_clause or org:
            support = (limit_clause or org)
            claims.append(Claim(
                text="The applicable requirement: " + support[0].text,
                supporting=support,
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
