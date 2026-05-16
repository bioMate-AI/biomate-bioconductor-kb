"""
Biologics MABEL verifier — ICH S6(R1) FIH dose derivation.

Per FDA 2005 + EMA 2017, biologics with high specificity, agonist activity,
or novel mechanism use the Minimum Anticipated Biological Effect Level
(MABEL) approach instead of the NOAEL-based MRSD path.

Three derivation methods, in increasing order of preference:
  M1. Receptor occupancy (RO) — dose producing a defined RO at target
      (typically 10-20% RO threshold). Calculation requires Kd, target
      receptor density, and dose-to-tissue exposure relationship.
  M2. In vitro pharmacological activity — fraction of EC20 or EC50 in
      the most sensitive in vitro assay.
  M3. PK-PD modeling — translation of an animal pharmacodynamic effect
      to a human dose via mechanistic PK-PD.

After MABEL is computed, a safety factor (typically 10-fold) is applied
to derive the FIH dose. EMA recommends comparing MABEL-derived dose to
the NOAEL-derived dose and selecting the lower (more conservative).

This checker:
  1. Extracts (method, MABEL_value, safety_factor, FIH_dose) from text
  2. Verifies the safety-factor arithmetic
  3. Flags missing safety-factor justification for novel-mechanism agonists
  4. When both MABEL and NOAEL/MRSD are stated, verifies that the lower
     was chosen (EMA conservatism rule)

Reference: FDA 2005 Estimating MRSD §6; EMA/CHMP/SWP/28367/07 Rev 1 (2017).
"""
from __future__ import annotations

import re
from dataclasses import dataclass
from typing import Literal

MABELMethod = Literal["receptor_occupancy", "in_vitro_activity", "pk_pd_model", "unknown"]

DEFAULT_SAFETY_FACTOR = 10.0
TOLERANCE_REL = 0.10

# Method-detection patterns. The RO pattern allows arbitrary intervening
# words between "receptor occupancy"/"target engagement" and the percentage,
# capped at ~60 chars to avoid matching a percentage from a different sentence.
_METHOD_RO_RE = re.compile(
    r"(?:receptor\s+occupancy|target\s+engagement|RO)\b[^.]{0,60}?(\d+(?:\.\d+)?)\s*%",
    re.IGNORECASE,
)
_METHOD_INVITRO_RE = re.compile(
    r"\b(?:in\s+vitro|EC\s*(?:20|50)|pharmacolog(?:ical|y))\b",
    re.IGNORECASE,
)
_METHOD_PKPD_RE = re.compile(
    r"\b(?:PK[/-]?PD|pharmacokinetic[/-]pharmacodynamic|mechanistic\s+model)\b",
    re.IGNORECASE,
)

# MABEL value: allow up to ~30 chars of intervening text (e.g. "MABEL via
# PK-PD modeling = 1 mg/kg") before the number.
_MABEL_VALUE_RE = re.compile(
    r"MABEL\b[^.]{0,40}?(\d+(?:\.\d+)?)\s*(mg/kg(?:/day)?|µg/kg|microgram/kg|ng/kg)",
    re.IGNORECASE,
)
_FIH_DOSE_RE = re.compile(
    r"(?:FIH\s+dose|first[- ]in[- ]human\s+dose|starting\s+dose)\s*"
    r"(?:of|was|=|:)?\s*(\d+(?:\.\d+)?)\s*(mg/kg(?:/day)?|µg/kg|microgram/kg|ng/kg)",
    re.IGNORECASE,
)
_SAFETY_FACTOR_RE = re.compile(
    r"safety\s+factor\s*(?:of)?\s*(\d+(?:\.\d+)?)",
    re.IGNORECASE,
)
_NOAEL_MRSD_RE = re.compile(
    r"(?:NOAEL[- ]derived\s+MRSD|MRSD\s+(?:from|via)\s+NOAEL)\s*"
    r"(?:of|was|=|:)?\s*(\d+(?:\.\d+)?)\s*(mg/kg(?:/day)?|µg/kg)",
    re.IGNORECASE,
)

# Unit normalization to mg/kg for arithmetic
_UNIT_TO_MGKG = {
    "mg/kg": 1.0, "mg/kg/day": 1.0,
    "µg/kg": 0.001, "microgram/kg": 0.001,
    "ng/kg": 1e-6,
}


def _normalize_to_mgkg(value: float, unit: str) -> float:
    return value * _UNIT_TO_MGKG.get(unit.lower(), 1.0)


@dataclass
class MABELFinding:
    method: MABELMethod
    mabel_value_mgkg: float | None
    fih_dose_mgkg: float | None
    safety_factor: float | None
    noael_mrsd_mgkg: float | None
    receptor_occupancy_pct: float | None
    grounded: bool
    issues: list[str]

    @property
    def passed(self) -> bool:
        return self.grounded and not self.issues


def verify_mabel(text: str) -> MABELFinding:
    """
    Extract MABEL claims from text and verify the derivation arithmetic
    and EMA "lower of MABEL vs MRSD" conservatism rule.

    Grounded = at least method + MABEL value + FIH dose present.
    Not grounded → returns grounded=False with no issues (text doesn't
    discuss MABEL; not an error).
    """
    issues: list[str] = []

    # Detect derivation method
    ro_match = _METHOD_RO_RE.search(text)
    ro_pct = float(ro_match.group(1)) if ro_match else None
    if ro_match:
        method: MABELMethod = "receptor_occupancy"
    elif _METHOD_INVITRO_RE.search(text):
        method = "in_vitro_activity"
    elif _METHOD_PKPD_RE.search(text):
        method = "pk_pd_model"
    else:
        method = "unknown"

    # Extract MABEL and FIH dose with units
    mabel_m = _MABEL_VALUE_RE.search(text)
    mabel_mgkg = (
        _normalize_to_mgkg(float(mabel_m.group(1)), mabel_m.group(2))
        if mabel_m else None
    )
    fih_m = _FIH_DOSE_RE.search(text)
    fih_mgkg = (
        _normalize_to_mgkg(float(fih_m.group(1)), fih_m.group(2))
        if fih_m else None
    )

    sf_m = _SAFETY_FACTOR_RE.search(text)
    stated_sf = float(sf_m.group(1)) if sf_m else None

    noael_m = _NOAEL_MRSD_RE.search(text)
    noael_mgkg = (
        _normalize_to_mgkg(float(noael_m.group(1)), noael_m.group(2))
        if noael_m else None
    )

    if mabel_mgkg is None or fih_mgkg is None:
        return MABELFinding(
            method=method, mabel_value_mgkg=mabel_mgkg, fih_dose_mgkg=fih_mgkg,
            safety_factor=stated_sf, noael_mrsd_mgkg=noael_mgkg,
            receptor_occupancy_pct=ro_pct,
            grounded=False, issues=[],
        )

    # Verify safety-factor arithmetic
    safety_factor = stated_sf if stated_sf is not None else DEFAULT_SAFETY_FACTOR
    computed_fih = mabel_mgkg / safety_factor
    rel_err = abs(fih_mgkg - computed_fih) / max(computed_fih, 1e-12)
    if rel_err > TOLERANCE_REL:
        issues.append(
            f"fih_arithmetic_mismatch: stated={fih_mgkg:.4g}, "
            f"computed={computed_fih:.4g}, rel_err={rel_err:.1%}"
        )

    # Method-specific checks
    if method == "receptor_occupancy" and ro_pct is not None:
        # EMA recommends 10-20% RO threshold for novel-mechanism agonists.
        # Higher RO at MABEL is acceptable for less-novel mechanisms but
        # should be justified. Flag thresholds >50% as needing justification.
        if ro_pct > 50:
            issues.append(
                f"high_ro_threshold:{ro_pct}%_needs_justification_per_EMA_2017"
            )

    # EMA conservatism rule: pick lower of MABEL vs NOAEL-derived dose
    if noael_mgkg is not None and noael_mgkg < fih_mgkg * 0.9:
        # FIH dose appears higher than NOAEL-derived; should have chosen lower
        issues.append(
            f"conservatism_violation: NOAEL-derived={noael_mgkg:.4g} mg/kg "
            f"is lower than chosen FIH={fih_mgkg:.4g} mg/kg "
            f"(EMA/CHMP/SWP/28367/07 §6.2)"
        )

    # Missing safety-factor justification when sf < default
    if stated_sf is not None and stated_sf < DEFAULT_SAFETY_FACTOR:
        issues.append(
            f"safety_factor_below_default:{stated_sf}_must_be_justified"
        )

    return MABELFinding(
        method=method, mabel_value_mgkg=mabel_mgkg, fih_dose_mgkg=fih_mgkg,
        safety_factor=stated_sf, noael_mrsd_mgkg=noael_mgkg,
        receptor_occupancy_pct=ro_pct,
        grounded=True, issues=issues,
    )


if __name__ == "__main__":
    examples = [
        # Correct RO-based MABEL with 10× safety factor
        "The MABEL was derived from receptor occupancy modeling, with the dose "
        "producing 10% target engagement. MABEL of 0.05 mg/kg was calculated. "
        "Applying a safety factor of 10, the FIH dose of 0.005 mg/kg is proposed "
        "per ICH S6(R1) and EMA/CHMP/SWP/28367/07.",

        # Wrong arithmetic: MABEL 0.1, SF 10 → FIH should be 0.01, not 0.05
        "In vitro EC20 was 1 nM; MABEL of 0.1 mg/kg was derived. With a safety "
        "factor of 10, the FIH dose of 0.05 mg/kg is proposed.",

        # Conservatism violation: NOAEL-derived MRSD lower than MABEL FIH
        "MABEL via PK-PD modeling = 1 mg/kg. With safety factor 10, FIH dose = "
        "0.1 mg/kg. The NOAEL-derived MRSD was 0.02 mg/kg.",

        # Not grounded (no MABEL claim)
        "The compound showed good tolerability in cynomolgus monkeys.",
    ]
    for ex in examples:
        f = verify_mabel(ex)
        print(f"passed={f.passed} grounded={f.grounded} method={f.method} "
              f"issues={f.issues}")
