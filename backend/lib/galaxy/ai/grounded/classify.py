"""
Question classification.

The blogger's core observation is that an AI handles NORMATIVE and INVESTIGATION
questions fine but collapses on RATIONALE questions — "why is the threshold this
number, what work produced it." We classify so the answer assembler can apply
the right evidence bar and raise the right boundary.

Prototype uses deterministic rules (zero-cost, testable). In production this is
the rule-first / LLM-fallback hybrid the BioMate extraction layer already uses:
rules catch the clear cases; an LLM disambiguates genuinely ambiguous prose.
"""

from __future__ import annotations

import re
from typing import List, Tuple

from .models import QuestionType

# Signals that a user is asking WHY a value/threshold is what it is, or how it
# was derived — the hard case. Ordered roughly by strength.
_RATIONALE_PATTERNS = [
    r"\bwhy\b",
    r"how (was|were|did).{0,30}(derived|arrived|chosen|set|decided|determined)",
    r"what (experiment|experiments|studies|study|data|evidence|work|testing)",
    r"\b(scientific )?(basis|rationale|justification|reasoning)\b",
    r"\bwhere does .{0,20}(number|value|limit|threshold) come from\b",
    r"\bon what (basis|grounds)\b",
    r"\b(origin|provenance) of (the )?(number|value|limit|threshold)\b",
    r"what (led|lead) to",
    r"\bbehind the (number|value|standard|limit|threshold)\b",
]

_NORMATIVE_PATTERNS = [
    r"\bwhat .{0,50}(require|requirement|limit|specif|acceptance|allow|value|criteria|minimum|maximum)",
    r"\b(acceptance criteria|acceptance limit|required value|minimum|maximum)\b",
    r"\bdoes .{0,40}(require|specify|allow|state|say|mandate|permit)\b",
    r"\bis .{0,30}(compliant|within spec|acceptable)\b",
]

_INVESTIGATION_PATTERNS = [
    r"\b(fail|failed|failing|out of spec|oos|deviation|investigat|troubleshoot)\b",
    r"\bwhat (should|do) (i|we) (check|do|look)\b",
    r"\b(root cause|corrective action|capa)\b",
]

_DEFINITION_PATTERNS = [
    r"\bwhat (is|are|does) .{0,30}(mean|definition|defined)\b",
    r"\bdefine\b",
    r"\bwhat is (a |an |the )?[a-z ]{2,30}\?",
]


def _matches(patterns: List[str], text: str) -> int:
    return sum(1 for p in patterns if re.search(p, text))


def classify(question: str) -> Tuple[QuestionType, float]:
    """Return (type, confidence 0..1).

    RATIONALE is checked with priority: a question that is phrased as "what does
    the standard require AND why" is routed to RATIONALE, because that is the
    path that carries the honest-boundary logic. Under-serving a rationale ask is
    the failure mode we exist to fix.
    """
    q = question.lower().strip()

    scores = {
        QuestionType.RATIONALE: _matches(_RATIONALE_PATTERNS, q),
        QuestionType.NORMATIVE: _matches(_NORMATIVE_PATTERNS, q),
        QuestionType.INVESTIGATION: _matches(_INVESTIGATION_PATTERNS, q),
        QuestionType.DEFINITION: _matches(_DEFINITION_PATTERNS, q),
    }

    # Priority tie-break: rationale > investigation > normative > definition.
    # A "why" signal dominates even when normative phrasing is also present,
    # because the user wants the derivation, not a restatement of the limit.
    if scores[QuestionType.RATIONALE] > 0:
        total = sum(scores.values()) or 1
        conf = min(1.0, 0.5 + 0.1 * scores[QuestionType.RATIONALE])
        return QuestionType.RATIONALE, conf

    best = max(scores, key=lambda k: scores[k])
    if scores[best] == 0:
        return QuestionType.UNKNOWN, 0.3

    order = [QuestionType.INVESTIGATION, QuestionType.NORMATIVE, QuestionType.DEFINITION]
    for t in order:
        if scores[t] == scores[best]:
            best = t
            break

    total = sum(scores.values()) or 1
    conf = min(1.0, 0.4 + scores[best] / (total + 1))
    return best, conf
