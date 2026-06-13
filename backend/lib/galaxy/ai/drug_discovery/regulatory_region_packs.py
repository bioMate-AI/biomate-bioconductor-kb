"""
Lane B2 — region-specific narrative style rules.

Used by ind_assembly._build_rag_context to inject 1–3 short, deterministic
constraints when generating an IND §2.6.x paragraph for a non-FDA region.
Closes region_adaptation, the highest-variance task in the cross-judge n=70
(macro 0.388, CI [0.338, 0.446]).

Pure data — no LLM calls, no external dependencies. Easy to extend by
adding rows to REGION_RULES.
"""
from __future__ import annotations
from typing import Iterable


REGION_RULES: dict[str, dict[str, list[str]]] = {
    "FDA": {
        "*": [
            "Use FDA reviewer-style phrasing (active voice, past tense, no overclaims).",
            "Cite 21 CFR 312 where audit-trail requirements apply.",
        ],
    },
    "EMA": {
        "*": [
            "Use EMA scientific-advice style: precise, hedged where appropriate, units in SI.",
            "Prefer 'were observed' over 'were noted'; avoid US idioms.",
            "Cite ICH guidelines in the EMA-adopted form (e.g. 'ICH M3(R2) CHMP/ICH/286/95').",
        ],
        "pbpk": [
            "Reference the EMA PBPK qualification guideline 'EMA/CHMP/EWP/37498/2011'.",
            "Report within-2-fold acceptance criterion for both Cmax and AUC explicitly.",
        ],
        "tox_overview": [
            "Single-figure NOAEL/NOEL: state both NOAEL and NOEL where they diverge.",
        ],
    },
    "NMPA": {
        "*": [
            "Write in formal Chinese pharmaceutical-regulatory English (concise, paratactic).",
            "Declare the GLP facility origin (domestic GLP or foreign GLP recognized by NMPA).",
            "Cite NMPA Announcement No. 35 (2018) for GLP-equivalence framing.",
        ],
        "tox_overview": [
            "Add a Chinese ethnic safety bridging statement when the pivotal toxicology cohort "
            "is non-Asian.",
        ],
        "pbpk": [
            "Note that NMPA Center for Drug Evaluation (CDE) accepts EMA PBPK criteria as a "
            "scientific reference; cite EMA/CHMP/EWP/37498/2011 alongside any domestic guidance.",
        ],
    },
    "PMDA": {
        "*": [
            "Use PMDA review-style phrasing (formal, structured paragraphs, no rhetorical flourishes).",
            "Cite Japanese guidelines in MHLW format (e.g. 'MHLW Notification No. 0911-1').",
        ],
        "tox_overview": [
            "When relevant, reference 'Guideline for the Reporting of Adverse Reactions' "
            "(MHLW PSEHB/SD Notification No. 0928-1).",
        ],
    },
}


def region_style_rules(region: str, section_type: str) -> list[str]:
    """Return up to 4 region+section narrative-style rules.

    Combines section-specific rules with the region-wide '*' rules.
    Returns empty list when the region is unknown (FDA default behaviour).
    """
    region = (region or "FDA").upper()
    pack = REGION_RULES.get(region, {})
    out: list[str] = []
    out.extend(pack.get("*", []))
    out.extend(pack.get(section_type, []))
    return out[:4]


def known_regions() -> Iterable[str]:
    return REGION_RULES.keys()
