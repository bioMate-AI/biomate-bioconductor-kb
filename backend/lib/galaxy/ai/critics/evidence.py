"""
Design-rule evidence lookup — the grounding substrate for critics.

The existing ``config/qc_evidence.yaml`` grounds *threshold* gates (hERG IC50 < X, …)
with DOI-graded (GOLD/SILVER/BRONZE) citations, read via
``lib/galaxy/ai/retrievers/qc_evidence.py``. Critics need a parallel class of
evidence — *design rules* ("adjust for known prognostic covariates", "test the PH
assumption") — which is NOT yet in that YAML.

This module provides a thin, cached lookup keyed by a stable design-rule key, so a
critic cites by key (``design_rule("survival.adjust_confounders")``) rather than
hardcoding a DOI string. The shipped table below is the SEED set; the intended
migration (per the feasibility audit) is to move these into a ``design_rules:``
section of ``qc_evidence.yaml`` and have :func:`design_rule` read them through the
same retriever, so grounding stays in one provenance-graded source.
"""
from __future__ import annotations

from typing import Dict, Optional

from .base import Evidence, Provenance


# Seed design-rule evidence. KEY -> Evidence. GOLD = peer-reviewed/guideline w/ DOI.
# TODO(critic-layer): migrate into config/qc_evidence.yaml `design_rules:` and read
# via retrievers/qc_evidence.py so there is ONE provenance-graded evidence source.
_DESIGN_RULES: Dict[str, Evidence] = {
    "survival.adjust_confounders": Evidence(
        claim=(
            "A Cox model must adjust for known prognostic covariates; an omitted "
            "covariate associated with both exposure and outcome confounds the "
            "primary hazard ratio."
        ),
        source="STROBE statement, item 16a (confounder-adjusted estimates); "
               "Therneau & Grambsch, Modeling Survival Data (2000), ch. 3",
        doi="10.1016/j.jclinepi.2007.11.008",
        provenance=Provenance.GOLD,
    ),
    "survival.ph_assumption": Evidence(
        claim=(
            "The proportional-hazards assumption must be tested (scaled Schoenfeld "
            "residuals); a global or per-covariate p < 0.05 indicates a time-varying "
            "effect that biases a single hazard ratio."
        ),
        source="Grambsch & Therneau, 'Proportional hazards tests and diagnostics "
               "based on weighted residuals', Biometrika 81(3):515-526 (1994)",
        doi="10.1093/biomet/81.3.515",
        provenance=Provenance.GOLD,
    ),
    "survival.ph_time_transform": Evidence(
        claim=(
            "A PH violation is remediated by stratifying on the offending covariate "
            "or modelling it as a time-varying effect (e.g. a tt() time transform), "
            "not by reporting the unadjusted single HR."
        ),
        source="Therneau, Crowson & Atkinson, 'Using Time Dependent Covariates ... "
               "in the survival Package' (2023 vignette)",
        doi="10.1093/biomet/81.3.515",
        provenance=Provenance.SILVER,
    ),
}


def design_rule(key: str) -> Optional[Evidence]:
    """Return the Evidence for a design-rule key, or None if unknown."""
    return _DESIGN_RULES.get(key)


def require_design_rule(key: str) -> Evidence:
    """Like :func:`design_rule` but raises if the key is unknown (use in critics that
    must cite). This makes an un-grounded critic fail loudly at author time rather
    than silently emitting an uncited (and therefore suppressed) issue."""
    ev = _DESIGN_RULES.get(key)
    if ev is None:
        raise KeyError(f"no design-rule evidence registered for {key!r}")
    return ev
