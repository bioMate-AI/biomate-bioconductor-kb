"""
Grounded Standards Assistant — evidence-tiered, provenance-honest answering for
regulated domains (GMP / standards / pharmacopoeia).

Public API:
    ask(question, user)        -> GroundedAnswer
    to_markdown(answer)        -> str
    to_dict(answer)            -> dict
    load_corpus()              -> List[Source]
"""

from .engine import ask, to_dict, to_markdown, to_solicitation
from .corpus import load_corpus
from .retrievers import (
    Retriever,
    CorpusRetriever,
    CompositeRetriever,
    LiteratureRetriever,
    FirmRecordRetriever,
    literature_item_to_source,
)
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
    "to_solicitation",
    "load_corpus",
    "Retriever",
    "CorpusRetriever",
    "CompositeRetriever",
    "LiteratureRetriever",
    "FirmRecordRetriever",
    "literature_item_to_source",
    "Boundary",
    "Claim",
    "EvidenceGrade",
    "GroundedAnswer",
    "IsolationAudit",
    "QuestionType",
    "Source",
    "SourceTier",
]
