"""
Grounded Standards Assistant — evidence-tiered, provenance-honest answering for
regulated domains (GMP / standards / pharmacopoeia).

Public API:
    ask(question, user)        -> GroundedAnswer
    to_markdown(answer)        -> str
    to_dict(answer)            -> dict
    load_corpus()              -> List[Source]
"""

from .engine import ask, to_dict, to_markdown
from .corpus import load_corpus
from .models import (
    Boundary,
    Claim,
    EvidenceGrade,
    GroundedAnswer,
    IsolationAudit,
    QuestionType,
    Source,
    SourceTier,
)

__all__ = [
    "ask",
    "to_dict",
    "to_markdown",
    "load_corpus",
    "Boundary",
    "Claim",
    "EvidenceGrade",
    "GroundedAnswer",
    "IsolationAudit",
    "QuestionType",
    "Source",
    "SourceTier",
]
