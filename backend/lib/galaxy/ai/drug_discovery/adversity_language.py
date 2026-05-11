"""
ICH adversity-language verifier — checker B4 from FDA reviewer checklist v2.

FDA/ICH use a precise vocabulary to describe nonclinical findings. The phrases
"no findings", "no adverse findings", "no test-article-related findings", and
"NOAEL not established" are legally distinct. This checker:

  1. Parses an output statement for the adversity phrase used.
  2. Verifies it matches the source-conclusion adversity category.

Reference: ICH M3(R2); FDA OND practice on adverse-effect characterization;
Kale et al. 2022 (Practical Considerations in Determining Adversity).
"""
from __future__ import annotations

import re
from dataclasses import dataclass
from typing import Literal

AdversityCategory = Literal[
    "no_findings",                  # no observations of any kind
    "non_adverse_findings",         # findings present but judged non-adverse
    "no_test_article_related",      # findings present but not test-article-related
    "adverse_findings",             # adverse findings identified, NOAEL established
    "noael_not_established",        # adverse at all doses tested
]

CATEGORY_PATTERNS: dict[AdversityCategory, list[str]] = {
    "no_findings": [
        r"\bno findings\b",
        r"\bno observations\b",
        r"\bunremarkable\b",
    ],
    "non_adverse_findings": [
        r"\bnon[- ]adverse\b",
        r"\bnot considered adverse\b",
        r"\bno adverse findings\b",
        r"\bno adverse effects?\b",
    ],
    "no_test_article_related": [
        r"\bno test[- ]article[- ]related findings\b",
        r"\bno treatment[- ]related findings\b",
        r"\bnot test[- ]article[- ]related\b",
        r"\bunrelated to (?:test article|treatment)\b",
    ],
    "adverse_findings": [
        r"\badverse findings? (?:were |was )?identified\b",
        r"\bNOAEL (?:of|was|=|:) ?\d+",
        r"\bidentified an? NOAEL\b",
    ],
    "noael_not_established": [
        r"\bNOAEL (?:was )?not established\b",
        r"\bNOAEL could not be (?:established|determined)\b",
        r"\badverse (?:effects|findings) (?:at|were observed at) all dose levels\b",
    ],
}


@dataclass
class AdversityResult:
    detected: AdversityCategory | None
    matched_phrases: list[str]

    def matches(self, target: AdversityCategory) -> bool:
        return self.detected == target


def detect_adversity(text: str) -> AdversityResult:
    """Return the adversity category present in text (most-specific match wins)."""
    text_lower = text.lower()
    matches: list[tuple[AdversityCategory, str]] = []
    for cat, patterns in CATEGORY_PATTERNS.items():
        for p in patterns:
            m = re.search(p, text_lower, re.IGNORECASE)
            if m:
                matches.append((cat, m.group(0)))

    if not matches:
        return AdversityResult(detected=None, matched_phrases=[])

    # Priority: most specific (NOAEL not established > no_test_article_related >
    # non_adverse > adverse > no_findings)
    priority = [
        "noael_not_established",
        "no_test_article_related",
        "non_adverse_findings",
        "adverse_findings",
        "no_findings",
    ]
    matches.sort(key=lambda x: priority.index(x[0]))
    return AdversityResult(
        detected=matches[0][0],
        matched_phrases=[m[1] for m in matches],
    )


if __name__ == "__main__":
    for label, t in [
        ("no_findings",         "The study revealed no findings."),
        ("non_adverse",         "Salivation was observed but considered non-adverse."),
        ("no_TA_related",       "No test-article-related findings were observed."),
        ("adverse_w_noael",     "Adverse findings identified; NOAEL of 100 mg/kg/day."),
        ("noael_not_established", "Adverse effects at all dose levels; NOAEL was not established."),
    ]:
        r = detect_adversity(t)
        print(f"[{label}] detected={r.detected}, matched={r.matched_phrases}")
