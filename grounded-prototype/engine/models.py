"""
Grounded Standards Assistant — core data model.

This module encodes the two product principles the prototype exists to prove:

1. EVIDENCE DEPTH WITH HONEST BOUNDARIES
   A regulated-domain answer is only as good as the source it can point at.
   Every factual claim carries the *tier* of source that supports it, and the
   assistant is required to mark the point at which the authoritative record
   runs out (e.g. "the standard specifies 0.95 but the primary experimental
   justification for that exact value is not in the retrievable literature").

2. PROVENANCE + TENANT ISOLATION
   One user's unverified working notes must never be served to another user as
   if they were established fact. Sources are tiered by trust, scoped by owner,
   and the assistant never lets a Tier-D (personal, unverified) source support a
   confirmed claim.

Python 3.9 compatible (no PEP 604 unions): the BioMate backend pins 3.9.
"""

from __future__ import annotations

import enum
from dataclasses import dataclass, field
from typing import List, Optional


class SourceTier(enum.IntEnum):
    """Trust tiers, ordered: lower value == higher authority.

    The ordering matters: when assembling an answer we prefer the most
    authoritative tier that supports a claim, and we refuse to let a
    low-authority tier stand in for a high-authority one.
    """

    NORMATIVE_PRIMARY = 1   # A: the standard / regulation / pharmacopoeia text itself
    PEER_REVIEWED = 2       # B: peer-reviewed literature, experimental studies
    ORG_VALIDATED = 3       # C: company SOPs / validation reports that passed QA review
    UNVERIFIED_PERSONAL = 4 # D: personal notes, drafts, uploads, chat history — never "fact"

    @property
    def label(self) -> str:
        return {
            SourceTier.NORMATIVE_PRIMARY: "Normative (primary standard/regulation)",
            SourceTier.PEER_REVIEWED: "Peer-reviewed literature",
            SourceTier.ORG_VALIDATED: "Organisation-validated (QA-approved)",
            SourceTier.UNVERIFIED_PERSONAL: "Unverified personal note",
        }[self]

    @property
    def short(self) -> str:
        return {
            SourceTier.NORMATIVE_PRIMARY: "A",
            SourceTier.PEER_REVIEWED: "B",
            SourceTier.ORG_VALIDATED: "C",
            SourceTier.UNVERIFIED_PERSONAL: "D",
        }[self]

    @property
    def is_authoritative(self) -> bool:
        """Tiers that may support a *confirmed* claim."""
        return self in (
            SourceTier.NORMATIVE_PRIMARY,
            SourceTier.PEER_REVIEWED,
            SourceTier.ORG_VALIDATED,
        )


class QuestionType(enum.Enum):
    """What kind of answer the user is actually asking for.

    The blogger's key observation: AI answers NORMATIVE and INVESTIGATION
    questions well, but collapses on RATIONALE questions ("why that number,
    what experiments"). We classify so the assembler can apply the right
    evidence bar and surface the right boundary.
    """

    NORMATIVE = "normative"        # "what does the standard require?"
    RATIONALE = "rationale"        # "why that value? what experiments justify it?"
    INVESTIGATION = "investigation" # "my test failed — what do I check?"
    DEFINITION = "definition"      # "what is dryness value / superheat?"
    UNKNOWN = "unknown"


class EvidenceGrade(enum.Enum):
    """GRADE-style confidence for the answer as a whole."""

    HIGH = "high"                   # normative text or strong experimental basis
    MODERATE = "moderate"           # supported, but indirect or single-source
    LOW = "low"                     # weak / tangential support only
    NOT_ESTABLISHED = "not_established"  # the authoritative record does not answer this


@dataclass(frozen=True)
class Source:
    """One retrievable unit of knowledge with full provenance.

    `owner` is the tenant that owns the source. `None` == shared/global
    (standards, literature, QA-approved org knowledge). A personal note is
    owned by exactly one user and is visible only to that user.
    """

    id: str
    tier: SourceTier
    title: str
    citation: str            # clause number, DOI, SOP id — a human can go verify this
    text: str
    owner: Optional[str] = None     # tenant id; None == shared
    verified: bool = True           # QA/editorial sign-off; personal notes start False
    locator: Optional[str] = None   # URL / document path for the reader to open
    keywords: List[str] = field(default_factory=list)

    @property
    def is_personal(self) -> bool:
        return self.tier == SourceTier.UNVERIFIED_PERSONAL


@dataclass
class ScoredSource:
    source: Source
    score: float


@dataclass
class Claim:
    """A single statement in the answer, bound to the evidence behind it."""

    text: str
    supporting: List[Source] = field(default_factory=list)

    @property
    def best_tier(self) -> Optional[SourceTier]:
        if not self.supporting:
            return None
        return min(s.tier for s in self.supporting)

    @property
    def is_grounded(self) -> bool:
        """A claim is grounded only if an authoritative tier supports it."""
        return any(s.tier.is_authoritative for s in self.supporting)


@dataclass
class Boundary:
    """The honest edge of what the retrievable record can support.

    This is the heart of the prototype: instead of confabulating past the
    evidence, the assistant names the gap and points at the humans who hold
    the answer (standards-committee members, PDA/ISPE/SPE working groups).
    """

    question_fragment: str      # the part of the ask we could NOT ground
    reason: str                 # why the record stops here
    escalate_to: List[str] = field(default_factory=list)  # who to actually ask
    suggested_questions: List[str] = field(default_factory=list)


@dataclass
class IsolationAudit:
    """What the retrieval layer let in and kept out, for this request.

    Surfaced in the answer so the trust property is observable, not implicit.
    """

    requesting_user: str
    shared_sources_used: int = 0
    own_personal_sources_used: int = 0
    other_tenant_personal_blocked: int = 0
    unverified_demoted: int = 0


@dataclass
class GroundedAnswer:
    question: str
    question_type: QuestionType
    grade: EvidenceGrade
    claims: List[Claim] = field(default_factory=list)
    boundaries: List[Boundary] = field(default_factory=list)
    isolation: Optional[IsolationAudit] = None

    @property
    def summary(self) -> str:
        grounded = sum(1 for c in self.claims if c.is_grounded)
        return (
            f"{self.question_type.value} question · grade={self.grade.value} · "
            f"{grounded}/{len(self.claims)} claims grounded · "
            f"{len(self.boundaries)} boundary note(s)"
        )
