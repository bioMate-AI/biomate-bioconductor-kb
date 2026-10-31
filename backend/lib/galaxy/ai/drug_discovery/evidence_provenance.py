"""
Shared provenance detection for study-report text.

Used by the wet-lab text ingester and the PDF study-report extractor so that
species, GLP status and measured-vs-predicted evidence are derived from what
the document actually states. Absent evidence is reported as unknown
(``None`` / ``"unspecified"``); nothing defaults to human, GLP-compliant or
measured.
"""
from __future__ import annotations

import re
from typing import Optional

UNSPECIFIED_SPECIES = "unspecified"

# Nonclinical species and common strains (normalised by normalise_species).
SPECIES_PATTERN = re.compile(
    r"\b(sprague.?dawley|wistar|fischer|cd.?1|balb/c|c57|beagle|cynomolgus|"
    r"rat|rats|mouse|mice|dog|dogs|monkey|monkeys|rabbit|rabbits|hamster|"
    r"guinea pig|minipig|pig)\b",
    re.I,
)
HUMAN_PATTERN = re.compile(
    r"\b(humans?|healthy\s+(?:adult\s+)?(?:male\s+|female\s+)?(?:volunteers|subjects))\b",
    re.I,
)

_SPECIES_MAP = {
    "sprague": "rat", "wistar": "rat", "fischer": "rat", "rat": "rat",
    "mouse": "mouse", "mice": "mouse", "balb": "mouse", "c57": "mouse", "cd-1": "mouse",
    "cd1": "mouse",
    "beagle": "dog", "dog": "dog",
    "cynomolgus": "monkey", "monkey": "monkey",
    "rabbit": "rabbit", "hamster": "hamster",
    "guinea": "guinea pig", "minipig": "minipig", "pig": "pig",
    "human": "human", "volunteer": "human", "subject": "human",
}


def normalise_species(raw: str) -> str:
    raw = raw.lower()
    for key, norm in _SPECIES_MAP.items():
        if key in raw:
            return norm
    return raw.strip()


def species_mentioned(text: str) -> set[str]:
    """All distinct species (nonclinical or human) named in ``text``."""
    found = {normalise_species(m.group(1)) for m in SPECIES_PATTERN.finditer(text)}
    found |= {normalise_species(m.group(1)) for m in HUMAN_PATTERN.finditer(text)}
    return found


def resolve_species(context: str, document: str) -> str:
    """Species for one extracted value.

    The value's own line wins if it names exactly one species; otherwise the
    document is used if it names exactly one. Anything else is unspecified.
    """
    for scope in (context, document):
        found = species_mentioned(scope)
        if len(found) == 1:
            return next(iter(found))
        if len(found) > 1:
            return UNSPECIFIED_SPECIES
    return UNSPECIFIED_SPECIES


# ── GLP status ──────────────────────────────────────────────────────────────

_GLP_TERM = r"(?:GLP|Good\s+Laboratory\s+Practices?)"
_GLP_NEGATIVE = re.compile(
    r"\bnon[- ]?GLP\b"
    r"|\bnot\s+(?:a\s+)?(?:[\w-]+\s+){0,4}?" + _GLP_TERM +
    r"|\bnot\s+(?:been\s+)?(?:conducted|performed|carried\s+out|compliant)\b[^.\n]{0,40}?" + _GLP_TERM +
    r"|\bwithout\s+" + _GLP_TERM +
    r"|\bno\s+" + _GLP_TERM,
    re.I,
)
_GLP_POSITIVE = re.compile(
    r"\bGLP[- ]?compliant\b"
    r"|\b(?:conducted|performed|carried\s+out)\b[^.\n]{0,40}?" + _GLP_TERM +
    r"|\bin\s+(?:compliance|accordance)\s+with\b[^.\n]{0,40}?" + _GLP_TERM +
    r"|\b21\s*CFR\s*(?:Part\s*)?58\b"
    r"|\bGood\s+Laboratory\s+Practices?\b",
    re.I,
)


def detect_glp_status(text: str) -> Optional[bool]:
    """True only on an affirmative GLP statement, False on an explicit
    non-GLP statement, None when the text says nothing either way."""
    if _GLP_NEGATIVE.search(text):
        return False
    if _GLP_POSITIVE.search(text):
        return True
    return None


def parse_glp_flag(value) -> Optional[bool]:
    """Interpret an explicitly supplied GLP field; anything else is unknown."""
    if isinstance(value, bool):
        return value
    if isinstance(value, str):
        v = value.strip().lower()
        if v in {"true", "yes", "y", "glp", "glp-compliant", "compliant"}:
            return True
        if v in {"false", "no", "n", "non-glp", "not glp", "non-compliant"}:
            return False
    return None


# ── Measured vs predicted evidence ──────────────────────────────────────────

_PREDICTION_ONLY = re.compile(
    r"\b(?:predictions?|predicted|in[- ]silico|computational|simulations?|modell?ed)\s+only\b"
    r"|\bno\s+(?:wet[- ]lab\s+|experimental\s+|in\s+vivo\s+|in\s+vitro\s+)?"
    r"(?:measurements?|data|experiments?)\s+(?:were|was|have\s+been|has\s+been)\s+"
    r"(?:collected|made|performed|taken|obtained|conducted|generated)\b",
    re.I,
)
_PREDICTION_LANGUAGE = re.compile(
    r"\b(?:predicted|predictions?|in[- ]silico|computational(?:ly)?|simulated|simulations?|"
    r"QSAR|PBPK[- ]predicted|model[- ](?:predicted|based|derived)|modell?ed|extrapolated)\b",
    re.I,
)
_MEASUREMENT_LANGUAGE = re.compile(
    r"\b(?:measured|observed|determined|experimental(?:ly)?|assayed)\b", re.I,
)


def is_prediction_only(text: str) -> bool:
    """Document explicitly states it contains predictions, not measurements."""
    return bool(_PREDICTION_ONLY.search(text))


def has_prediction_language(text: str) -> bool:
    return bool(_PREDICTION_LANGUAGE.search(text))


def has_measurement_language(text: str) -> bool:
    return bool(_MEASUREMENT_LANGUAGE.search(text))


def line_at(text: str, start: int, end: int) -> str:
    """The full line of ``text`` that contains the span [start, end)."""
    lo = text.rfind("\n", 0, start) + 1
    hi = text.find("\n", end)
    return text[lo:] if hi == -1 else text[lo:hi]
