"""
MRSD / HED arithmetic verifier — checker C1 from FDA reviewer checklist v2.

Per Manning et al. (2020), MRSD calculation errors are the single most common
nonclinical clinical-hold cause. This module:

  1. Extracts (NOAEL, species, body weight, MRSD) tuples from generated text.
  2. Recomputes HED via FDA BSA-conversion factors and applies the 10× safety factor.
  3. Flags numerical disagreement with the stated MRSD (>10% relative error).

Reference: FDA "Estimating the Maximum Safe Starting Dose in Initial Clinical Trials
for Therapeutics in Adult Healthy Volunteers" (2005).

No model required. Pure regex + arithmetic.
"""
from __future__ import annotations

import math
import re
from dataclasses import dataclass
from typing import Optional

# FDA 2005 Table 1 — animal-to-human BSA conversion factors (km ratios).
# HED (mg/kg) = animal NOAEL (mg/kg) × (animal_km / human_km)
# Equivalently, the divisor below: HED = NOAEL / divisor.
BSA_DIVISOR: dict[str, float] = {
    "mouse":      12.3,
    "hamster":     7.4,
    "rat":         6.2,
    "ferret":      5.3,
    "guinea pig":  4.6,
    "rabbit":      3.1,
    "dog":         1.8,
    "monkey":      3.1,
    "marmoset":    6.2,
    "minipig":     1.5,
    "pig":         1.5,
}

DEFAULT_HUMAN_BW_KG = 60.0  # FDA guidance default
DEFAULT_SAFETY_FACTOR = 10.0
TOLERANCE_REL = 0.10  # 10% disagreement = fail

_NOAEL_RE = re.compile(
    r"NOAEL\s*(?:of|was|=|:)?\s*(\d+(?:\.\d+)?)\s*(mg/kg(?:/day)?|mg\s*kg-1)",
    re.IGNORECASE,
)
_SPECIES_RE = re.compile(
    r"\b(mouse|mice|rat|rats|dog|dogs|monkey|monkeys|cynomolgus|rabbit|rabbits|"
    r"minipig|minipigs|hamster|ferret|guinea pig)\b",
    re.IGNORECASE,
)
_MRSD_RE = re.compile(
    r"(?:MRSD|maximum\s+recommended\s+starting\s+dose|starting\s+dose)\s*"
    r"(?:of|was|=|:)?\s*(\d+(?:\.\d+)?)\s*(mg/kg(?:/day)?|mg|µg/kg|microgram/kg)",
    re.IGNORECASE,
)
_HED_RE = re.compile(
    r"HED\s*(?:of|=|:)?\s*(\d+(?:\.\d+)?)\s*(mg/kg(?:/day)?|mg)",
    re.IGNORECASE,
)
_SAFETY_FACTOR_RE = re.compile(
    r"safety\s+factor\s*(?:of)?\s*(\d+(?:\.\d+)?)",
    re.IGNORECASE,
)


def _normalize_species(s: str) -> Optional[str]:
    s = s.lower().rstrip("s")
    aliases = {
        "mouse": "mouse", "mice": "mouse",
        "rat": "rat",
        "dog": "dog",
        "monkey": "monkey", "cynomolgu": "monkey",
        "rabbit": "rabbit",
        "minipig": "minipig", "pig": "pig",
        "hamster": "hamster",
        "ferret": "ferret",
        "guinea pig": "guinea pig",
    }
    return aliases.get(s)


@dataclass
class MRSDFinding:
    species: Optional[str]
    noael_mg_per_kg: Optional[float]
    stated_hed_mg_per_kg: Optional[float]
    stated_mrsd_mg_per_kg: Optional[float]
    stated_safety_factor: Optional[float]
    computed_hed_mg_per_kg: Optional[float]
    computed_mrsd_mg_per_kg: Optional[float]
    grounded: bool
    issues: list[str]

    @property
    def passed(self) -> bool:
        return self.grounded and not self.issues


def verify_mrsd(text: str) -> MRSDFinding:
    """
    Extract NOAEL/species/MRSD/HED claims from text and verify the arithmetic.

    A "grounded" finding has at least NOAEL + species. If those aren't present,
    we cannot verify; returns grounded=False with no issues raised (this is
    expected for sections that don't discuss MRSD).
    """
    issues: list[str] = []

    species_m = _SPECIES_RE.search(text)
    species = _normalize_species(species_m.group(1)) if species_m else None

    noael_m = _NOAEL_RE.search(text)
    noael = float(noael_m.group(1)) if noael_m else None

    mrsd_m = _MRSD_RE.search(text)
    stated_mrsd = float(mrsd_m.group(1)) if mrsd_m else None

    hed_m = _HED_RE.search(text)
    stated_hed = float(hed_m.group(1)) if hed_m else None

    sf_m = _SAFETY_FACTOR_RE.search(text)
    stated_sf = float(sf_m.group(1)) if sf_m else None

    if species is None or noael is None:
        return MRSDFinding(
            species=species, noael_mg_per_kg=noael,
            stated_hed_mg_per_kg=stated_hed,
            stated_mrsd_mg_per_kg=stated_mrsd,
            stated_safety_factor=stated_sf,
            computed_hed_mg_per_kg=None,
            computed_mrsd_mg_per_kg=None,
            grounded=False, issues=[],
        )

    divisor = BSA_DIVISOR.get(species)
    if divisor is None:
        issues.append(f"unknown_species_for_bsa_conversion:{species}")
        return MRSDFinding(
            species, noael, stated_hed, stated_mrsd, stated_sf,
            None, None, grounded=True, issues=issues,
        )

    computed_hed = noael / divisor
    safety_factor = stated_sf if stated_sf else DEFAULT_SAFETY_FACTOR
    computed_mrsd = computed_hed / safety_factor

    if stated_hed is not None:
        rel_err = abs(stated_hed - computed_hed) / max(computed_hed, 1e-9)
        if rel_err > TOLERANCE_REL:
            issues.append(
                f"hed_mismatch:stated={stated_hed:.3f},computed={computed_hed:.3f},"
                f"rel_err={rel_err:.1%}"
            )

    if stated_mrsd is not None:
        rel_err = abs(stated_mrsd - computed_mrsd) / max(computed_mrsd, 1e-9)
        if rel_err > TOLERANCE_REL:
            issues.append(
                f"mrsd_mismatch:stated={stated_mrsd:.3f},computed={computed_mrsd:.3f},"
                f"rel_err={rel_err:.1%}"
            )

    if stated_sf is not None and not math.isclose(stated_sf, DEFAULT_SAFETY_FACTOR):
        if stated_sf < DEFAULT_SAFETY_FACTOR:
            issues.append(
                f"safety_factor_below_default:stated={stated_sf},default={DEFAULT_SAFETY_FACTOR}"
            )

    return MRSDFinding(
        species=species, noael_mg_per_kg=noael,
        stated_hed_mg_per_kg=stated_hed,
        stated_mrsd_mg_per_kg=stated_mrsd,
        stated_safety_factor=stated_sf,
        computed_hed_mg_per_kg=computed_hed,
        computed_mrsd_mg_per_kg=computed_mrsd,
        grounded=True, issues=issues,
    )


if __name__ == "__main__":
    examples = [
        # Correct: rat NOAEL 100 mg/kg → HED 16.13 → MRSD 1.61
        "In the 28-day repeat-dose study, the NOAEL of 100 mg/kg/day was identified in rats. "
        "The HED of 16.1 mg/kg was derived using a safety factor of 10, yielding an MRSD of 1.6 mg/kg.",
        # Wrong: dog NOAEL 50 → HED should be 27.78, not 8
        "A NOAEL of 50 mg/kg was established in dogs. HED of 8 mg/kg was calculated, "
        "and an MRSD of 0.8 mg/kg is proposed.",
        # No MRSD claim — should return grounded=False (skip)
        "The drug showed acceptable absorption in mice over 14 days.",
    ]
    for ex in examples:
        f = verify_mrsd(ex)
        print(f"passed={f.passed} grounded={f.grounded} issues={f.issues}")
        print(f"  computed HED={f.computed_hed_mg_per_kg}, MRSD={f.computed_mrsd_mg_per_kg}")
