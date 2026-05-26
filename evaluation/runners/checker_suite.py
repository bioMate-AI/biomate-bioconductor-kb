"""Registry for the 9 regulatory checkers used in the unified eval.

Each checker is a callable `(generated_text, example) -> CheckerResult`.
The orchestrator runs all 9 against every generation and aggregates the
pass-rate per checker per model.

Lightweight inline implementations are provided here; the planning doc
(docs/20260521_UNIFIED_5MODEL_EVAL_PLAN.md) lists where the production
checker logic lives. Each function here intentionally mirrors what the
production checker measures so the eval numbers are aligned with the
checker-pass-rate the customer experiences in the IND Report UI.
"""
from __future__ import annotations

import re
from dataclasses import dataclass
from typing import Callable

from .corpus import Example


@dataclass
class CheckerResult:
    name: str
    passed: bool
    detail: str = ""
    score: float = 1.0   # 1.0 = pass; partial credit when applicable


Checker = Callable[[str, Example], CheckerResult]


# ---------------------------------------------------------------------------
# 1) MRSD calc — FDA 2005 guidance grounding
# ---------------------------------------------------------------------------

_MRSD_SIGNALS = (
    r"\bMRSD\b",
    r"maximum\s+recommended\s+starting\s+dose",
    r"safety\s+factor\b",
    r"BSA\s+conversion",
    r"NOAEL\s*[×*x]\s*",
    r"HED\b|human\s+equivalent\s+dose",
)


def _check_mrsd(text: str, ex: Example) -> CheckerResult:
    if ex.section_type not in ("tox_overview", "overview"):
        return CheckerResult("mrsd_calc", True, detail="n/a for section_type")
    hits = sum(1 for p in _MRSD_SIGNALS if re.search(p, text, re.I))
    return CheckerResult(
        "mrsd_calc", passed=hits >= 1,
        detail=f"{hits}/{len(_MRSD_SIGNALS)} MRSD signals",
        score=min(1.0, hits / 2),
    )


# ---------------------------------------------------------------------------
# 2) Adversity tense — past tense, attributed to dose group, no overclaims
# ---------------------------------------------------------------------------

_OVERCLAIM_PHRASES = [
    "well tolerated",
    "no adverse effects observed",
    "is safe",
    "demonstrates safety",
    "no toxicity",
]


def _check_adversity_tense(text: str, ex: Example) -> CheckerResult:
    if ex.section_type not in ("tox_overview", "tox_genotox", "tox_cardiac"):
        return CheckerResult("adversity_tense", True, detail="n/a")
    misses = [p for p in _OVERCLAIM_PHRASES if p in text.lower()]
    return CheckerResult(
        "adversity_tense", passed=len(misses) == 0,
        detail=("ok" if not misses else f"overclaim phrases: {misses}"),
    )


# ---------------------------------------------------------------------------
# 3) Phase gating — PBPK section must cite EMA criterion or within-2-fold
# ---------------------------------------------------------------------------

def _check_phase_gating(text: str, ex: Example) -> CheckerResult:
    if ex.section_type != "pbpk":
        return CheckerResult("phase_gating", True, detail="n/a")
    signals = ["within-2-fold", "within 2-fold", "ema", "67%", "80%",
               "criterion", "qualification", "EMA/CHMP"]
    hits = sum(1 for s in signals if s.lower() in text.lower())
    return CheckerResult(
        "phase_gating", passed=hits >= 1,
        detail=f"{hits}/{len(signals)} gating signals",
        score=min(1.0, hits / 2),
    )


# ---------------------------------------------------------------------------
# 4) Tabulated ↔ prose — numbers in prompt should appear in narrative
# ---------------------------------------------------------------------------

def _check_tabulated_vs_prose(text: str, ex: Example) -> CheckerResult:
    nums_in_prompt = set(re.findall(r"\b\d+(?:\.\d+)?\b", ex.user_prompt))
    if not nums_in_prompt:
        return CheckerResult("tabulated_vs_prose", True, detail="no numbers in prompt")
    nums_in_text = set(re.findall(r"\b\d+(?:\.\d+)?\b", text))
    preserved = nums_in_prompt & nums_in_text
    coverage = len(preserved) / max(1, len(nums_in_prompt))
    return CheckerResult(
        "tabulated_vs_prose",
        passed=coverage >= 0.5,
        score=coverage,
        detail=f"preserved {len(preserved)}/{len(nums_in_prompt)}",
    )


# ---------------------------------------------------------------------------
# 5) Citation accuracy — section-appropriate ICH/EMA/region guideline cited
# ---------------------------------------------------------------------------

_SECTION_CITATIONS: dict[str, list[str]] = {
    "tox_overview": ["ICH M3", "ICH S1", "ICH S7", "FDA 2005"],
    "tox_genotox":  ["ICH S2"],
    "tox_cardiac":  ["ICH S7B", "ICH S7"],
    "pbpk":         ["EMA/CHMP/EWP/37498/2011", "PBPK"],
    "admet":        ["ICH M4S"],
    "pk_overview":  ["ICH M3", "ICH E5"],
    "overview":     ["21 CFR Part 312", "ICH M4S", "ICH M3"],
}


def _check_citation_accuracy(text: str, ex: Example) -> CheckerResult:
    expected = _SECTION_CITATIONS.get(ex.section_type, [])
    if not expected:
        return CheckerResult("citation_accuracy", True, detail="no expected citation")
    hit = any(c.lower() in text.lower() for c in expected)
    return CheckerResult(
        "citation_accuracy", passed=hit,
        detail=f"expected one of {expected}",
    )


# ---------------------------------------------------------------------------
# 6) Hedge language — no over-confident absolute claims
# ---------------------------------------------------------------------------

_OVERCONFIDENT = [
    "proves",
    "demonstrates that",
    "shows definitively",
    "guarantees",
    "absolutely safe",
    "no risk",
]


def _check_hedge_language(text: str, ex: Example) -> CheckerResult:
    hits = [w for w in _OVERCONFIDENT if w in text.lower()]
    return CheckerResult(
        "hedge_language", passed=len(hits) == 0,
        detail=("ok" if not hits else f"overclaim words: {hits}"),
    )


# ---------------------------------------------------------------------------
# 7) Structural validator — min length + sentence shape + paragraph form
# ---------------------------------------------------------------------------

def _check_structural(text: str, ex: Example) -> CheckerResult:
    stripped = text.strip()
    if len(stripped) < 40:
        return CheckerResult("structural", False, detail=f"too short ({len(stripped)} chars)")
    if not re.search(r"[.!?]\s", stripped + " "):
        return CheckerResult("structural", False, detail="no sentence terminators")
    # disallow runs of 5+ identical tokens (looping degeneration)
    if re.search(r"(\b\w+\b)(?:\s+\1){4,}", stripped):
        return CheckerResult("structural", False, detail="degenerate repetition")
    return CheckerResult("structural", True, detail=f"{len(stripped)} chars")


# ---------------------------------------------------------------------------
# 8) Numeric ranges — half-life / clearance / dose plausibility
# ---------------------------------------------------------------------------

def _check_numeric_ranges(text: str, ex: Example) -> CheckerResult:
    suspicious: list[str] = []

    # Half-life sanity (small molecule typically < ~30d)
    for m in re.finditer(
        r"(half[- ]?life|t1/2|t½)\s*(?:=|of|is|was|≈|~)?\s*([\d.]+)\s*(h|hr|hours?|d|day|days)",
        text, re.I,
    ):
        val = float(m.group(2))
        unit = m.group(3).lower()
        hours = val * (24 if unit.startswith("d") else 1)
        if hours <= 0 or hours > 720:
            suspicious.append(f"half-life {val}{unit}")

    # Bioavailability must be in [0, 100]
    for m in re.finditer(r"(bioavailability|F)\s*(?:=|of|is|was|≈|~)?\s*([\d.]+)\s*%", text, re.I):
        v = float(m.group(2))
        if v < 0 or v > 100:
            suspicious.append(f"F={v}%")

    return CheckerResult(
        "numeric_ranges", passed=len(suspicious) == 0,
        detail=("ok" if not suspicious else f"suspicious: {suspicious}"),
    )


# ---------------------------------------------------------------------------
# 9) Cross-section consistency — compound mentioned in prompt is referenced
# ---------------------------------------------------------------------------

def _check_cross_section(text: str, ex: Example) -> CheckerResult:
    m = re.search(r"\b(BM-\d{4}(?:-\d+)?|[A-Z]{2,4}\d{3,5})\b", ex.user_prompt)
    if not m:
        return CheckerResult("cross_section_consistency", True, detail="no compound id in prompt")
    compound = m.group(0)
    referenced = (
        compound in text
        or "investigational compound" in text.lower()
        or "the compound" in text.lower()
    )
    return CheckerResult(
        "cross_section_consistency", passed=referenced,
        detail=f"compound={compound} referenced={referenced}",
    )


# ---------------------------------------------------------------------------
# Registry
# ---------------------------------------------------------------------------

CHECKERS: dict[str, Checker] = {
    "mrsd_calc":                  _check_mrsd,
    "adversity_tense":            _check_adversity_tense,
    "phase_gating":               _check_phase_gating,
    "tabulated_vs_prose":         _check_tabulated_vs_prose,
    "citation_accuracy":          _check_citation_accuracy,
    "hedge_language":             _check_hedge_language,
    "structural":                 _check_structural,
    "numeric_ranges":             _check_numeric_ranges,
    "cross_section_consistency":  _check_cross_section,
}


def run_all(text: str, example: Example) -> list[CheckerResult]:
    return [fn(text, example) for fn in CHECKERS.values()]


def all_checker_names() -> list[str]:
    return list(CHECKERS.keys())
