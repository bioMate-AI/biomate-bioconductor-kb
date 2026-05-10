"""
Structural validator — checker A from FDA reviewer checklist v2.

Verifies that a generated ICH M4S(R2) section contains all required subsections
in the required order. Pure regex / heading-tree parse.

Reference: ICH M4S(R2), Module 2.6 Nonclinical Written Summaries.
"""
from __future__ import annotations

import re
from dataclasses import dataclass

# Required subsection headings per ICH M4S(R2). Order matters.
REQUIRED_SUBSECTIONS: dict[str, list[str]] = {
    "2.6.2": [  # Pharmacology Written Summary
        "brief summary",
        "primary pharmacodynamics",
        "secondary pharmacodynamics",
        "safety pharmacology",
        "pharmacodynamic drug interactions",
        "discussion and conclusions",
    ],
    "2.6.4": [  # Pharmacokinetics Written Summary
        "brief summary",
        "methods of analysis",
        "absorption",
        "distribution",
        "metabolism",
        "excretion",
        "pharmacokinetic drug interactions",
        "other pharmacokinetic studies",
        "discussion",
    ],
    "2.6.6": [  # Toxicology Written Summary
        "brief summary",
        "single-dose toxicity",
        "repeat-dose toxicity",
        "genotoxicity",
        "carcinogenicity",
        "reproductive and developmental toxicity",
        "local tolerance",
        "other toxicity studies",
        "discussion and conclusions",
    ],
}

# Genotoxicity ordering rule: in vitro before in vivo (ICH M4S(R2) explicit).
_INVITRO_RE = re.compile(r"\bin\s*vitro\b", re.IGNORECASE)
_INVIVO_RE = re.compile(r"\bin\s*vivo\b", re.IGNORECASE)


@dataclass
class StructuralResult:
    section_id: str
    missing: list[str]
    out_of_order: list[tuple[str, str]]   # (heading_a, heading_b) — a should come before b
    invitro_invivo_violation: bool
    found_headings: list[str]

    @property
    def passed(self) -> bool:
        return (not self.missing
                and not self.out_of_order
                and not self.invitro_invivo_violation)


def _find_heading_positions(text: str, heading: str) -> int:
    """Return earliest character index where heading appears, or -1."""
    pattern = re.compile(re.escape(heading), re.IGNORECASE)
    m = pattern.search(text)
    return m.start() if m else -1


def validate_structure(text: str, section_id: str) -> StructuralResult:
    required = REQUIRED_SUBSECTIONS.get(section_id)
    if required is None:
        raise ValueError(f"No required-subsection list for section {section_id}")

    positions: list[tuple[str, int]] = []
    missing: list[str] = []
    for h in required:
        pos = _find_heading_positions(text, h)
        if pos < 0:
            missing.append(h)
        else:
            positions.append((h, pos))

    # Check ordering: positions should be monotonically increasing in the order of `required`.
    out_of_order: list[tuple[str, str]] = []
    found_in_required_order = [(h, p) for (h, p) in positions]
    for i in range(len(found_in_required_order) - 1):
        h_a, p_a = found_in_required_order[i]
        h_b, p_b = found_in_required_order[i + 1]
        if p_a > p_b:
            out_of_order.append((h_a, h_b))

    # In vitro vs in vivo ordering (only meaningful for §2.6.6 genotox subsection).
    invitro_invivo_violation = False
    if section_id == "2.6.6":
        invitro_pos = _INVITRO_RE.search(text)
        invivo_pos = _INVIVO_RE.search(text)
        if invitro_pos and invivo_pos and invitro_pos.start() > invivo_pos.start():
            invitro_invivo_violation = True

    return StructuralResult(
        section_id=section_id,
        missing=missing,
        out_of_order=out_of_order,
        invitro_invivo_violation=invitro_invivo_violation,
        found_headings=[h for h, _ in positions],
    )


if __name__ == "__main__":
    good = """
    Brief Summary. The compound was evaluated in a battery of toxicity studies.
    Single-Dose Toxicity. No mortality at 2000 mg/kg.
    Repeat-Dose Toxicity. NOAEL 100 mg/kg/day in rats.
    Genotoxicity. In vitro Ames negative. In vivo micronucleus negative.
    Carcinogenicity. Not yet conducted.
    Reproductive and Developmental Toxicity. Studies pending.
    Local Tolerance. No irritation observed.
    Other Toxicity Studies. None.
    Discussion and Conclusions. The safety profile supports Phase I.
    """
    missing_subs = """
    Brief Summary. Drug X.
    Repeat-Dose Toxicity. NOAEL 100 mg/kg.
    Discussion and Conclusions. Acceptable.
    """
    bad_order = """
    Brief Summary. X.
    Repeat-Dose Toxicity. Y.
    Single-Dose Toxicity. Z.
    Genotoxicity. In vivo first. Then in vitro.
    Carcinogenicity. None.
    Reproductive and Developmental Toxicity. None.
    Local Tolerance. None.
    Other Toxicity Studies. None.
    Discussion and Conclusions. End.
    """
    for label, text in [("good", good), ("missing", missing_subs), ("bad_order", bad_order)]:
        r = validate_structure(text, "2.6.6")
        print(f"[{label}] passed={r.passed} missing={r.missing} "
              f"out_of_order={r.out_of_order} invitro_violation={r.invitro_invivo_violation}")
