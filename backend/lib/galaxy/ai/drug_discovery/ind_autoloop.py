"""
Lane B4 — checker → auto-loop regen wrapper.

Standalone module that wraps ind_assembly._llm_narrative with up to N
regeneration attempts. After each attempt, runs _quick_audit; if it returns
failures, the first failure ID is translated to a natural-language
constraint via _AUDIT_RULE_DESCRIPTIONS and passed back as
`audit_constraint` so the next attempt explicitly addresses it.

Zero new LLM dependencies — reuses the existing 9 deterministic checkers
already wired into _quick_audit. The audit_constraint plumbing was already
in place in ind_assembly; this just exercises it in a loop.
"""
from __future__ import annotations
import logging

log = logging.getLogger(__name__)

_AUDIT_RULE_DESCRIPTIONS = {
    "CITE_001:PBPK_missing_EMA_guideline":
        "include the EMA PBPK qualification guideline citation 'EMA/CHMP/EWP/37498/2011' "
        "and the within-2-fold acceptance criterion",
    "CITE_002:genotox_missing_S2R1":
        "cite ICH S2(R1) as the genotoxicity guideline",
    "CONTENT_002:genotox_missing_ames":
        "explicitly mention the Ames (bacterial reverse mutation) assay result",
    "CITE_003:cardiac_missing_S7B":
        "cite ICH S7B for cardiac/hERG safety pharmacology",
}


def llm_narrative_with_retry(
    section_type: str,
    data: dict,
    region: str = "FDA",
    user_prompt_override: str = "",
    max_attempts: int = 3,
    org_id: str | None = None,
) -> tuple[str, list[str]]:
    """Generate narrative; on _quick_audit failure inject the rule as a
    constraint and regenerate up to max_attempts.

    Returns (text, list_of_constraints_tried). Always returns the cleanest
    of the attempted outputs (zero audit failures preferred; if none clean,
    the attempt with fewest failures).

    `org_id` forwards to `_llm_narrative` so the autoloop retries get the
    same per-org rule pack + few-shot exemplars in their RAG context as
    the first-pass call (B3 plumbing). Without this forward the PBPK,
    genotox, and cardiac autoloop paths would silently fall back to
    region-only RAG on retry, undoing per-org adaptation for the most
    quality-critical sections.
    """
    from galaxy.ai.drug_discovery.ind_assembly import _llm_narrative, _quick_audit

    attempts: list[tuple[str, list[str]]] = []
    constraint = ""
    constraints_tried: list[str] = []

    for _ in range(max_attempts):
        narrative = _llm_narrative(
            section_type=section_type,
            data=data,
            region=region,
            audit_constraint=constraint,
            user_prompt_override=user_prompt_override,
            org_id=org_id,
        )
        findings = _quick_audit(narrative, section_type) if narrative else []
        attempts.append((narrative, findings))
        if not findings:
            return narrative, constraints_tried
        rule_id = findings[0]
        constraint = _AUDIT_RULE_DESCRIPTIONS.get(rule_id, rule_id)
        constraints_tried.append(rule_id)
        log.debug("[IND auto-loop] %s attempt %d: failures=%s constraint=%r",
                  section_type, len(attempts), findings, constraint)

    best = min(attempts, key=lambda x: len(x[1]))
    return best[0], constraints_tried
