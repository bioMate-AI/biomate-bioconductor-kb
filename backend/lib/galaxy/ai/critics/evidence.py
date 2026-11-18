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
    # ── Power / events-per-variable / sample-size (archetype D, domain `*`) ────
    "power.epv_floor": Evidence(
        claim=(
            "A risk model (Cox proportional-hazards or logistic regression) needs at "
            "least ~10 events per estimated coefficient (EPV >= 10). Below this floor "
            "the coefficient estimates, standard errors and significance tests are "
            "unstable, biased and over-fit."
        ),
        source=(
            "Peduzzi et al., 'A simulation study of the number of events per variable "
            "in logistic regression analysis', J Clin Epidemiol 49(12):1373-1379 (1996); "
            "Peduzzi et al., 'Importance of events per independent variable in "
            "proportional hazards regression analysis', J Clin Epidemiol 48(12):1503-1510 (1995)"
        ),
        doi="10.1016/S0895-4356(96)00236-3",
        provenance=Provenance.GOLD,
    ),
    "power.min_replicates": Evidence(
        claim=(
            "Differential-expression testing requires replication: at least 3 "
            "biological replicates per group are the practical minimum to estimate "
            "within-group variance (dispersion), and >=6 are recommended to recover "
            "most true changes; with fewer than 2 the dispersion is not estimable at all."
        ),
        source=(
            "Schurch et al., 'How many biological replicates are needed in an RNA-seq "
            "experiment and which differential expression tool should you use?', "
            "RNA 22(6):839-851 (2016)"
        ),
        doi="10.1261/rna.053959.115",
        provenance=Provenance.GOLD,
    ),
    "power.overparameterized": Evidence(
        claim=(
            "A model that estimates as many (or more) parameters than it has independent "
            "observations is over-fit or non-identifiable; a minimum of ~5-10 "
            "observations per estimated parameter is required for stable estimation."
        ),
        source=(
            "Harrell, Regression Modeling Strategies, 2nd ed. (2015), ch. 4 "
            "(overfitting; the 10-20 observations/events-per-predictor rule); "
            "Peduzzi et al. 1995/1996"
        ),
        doi="10.1007/978-3-319-19425-7",
        provenance=Provenance.SILVER,
    ),
    # ── Output presence / null-result floor (domain `*`) ──────────────────────
    "output.expected_outputs_present": Evidence(
        claim=(
            "A completed analysis must emit its declared primary output artifacts "
            "(result table / model / figure); a run that produces no such artifact has "
            "not produced usable, reusable science and must not be presented as a "
            "successful finding."
        ),
        source=(
            "Wilkinson et al., 'The FAIR Guiding Principles for scientific data "
            "management and stewardship', Sci Data 3:160018 (2016)"
        ),
        doi="10.1038/sdata.2016.18",
        provenance=Provenance.SILVER,
    ),
    "output.null_result_reporting": Evidence(
        claim=(
            "An empty result table or zero significant features is a legitimate NULL "
            "result, not a pipeline success; it must be reported honestly as 'no "
            "significant findings' and distinguished from a run that silently failed "
            "to produce output."
        ),
        source=(
            "Wasserstein & Lazar, 'The ASA Statement on p-Values: Context, Process, "
            "and Purpose', Am Stat 70(2):129-133 (2016)"
        ),
        doi="10.1080/00031305.2016.1154108",
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
