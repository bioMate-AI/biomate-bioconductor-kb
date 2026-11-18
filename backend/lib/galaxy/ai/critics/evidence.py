"""
Design-rule evidence lookup — the grounding substrate (and closed citation vocab)
for critics.

The existing ``config/qc_evidence.yaml`` grounds *threshold* gates (hERG IC50 < X, …)
with DOI-graded (GOLD/SILVER/BRONZE) citations. Critics need a parallel class of
evidence — *design rules* ("adjust for known prognostic covariates", "test the PH
assumption"). Those now live in a dedicated ``design_rules:`` section of
``config/qc_evidence.yaml`` so grounding stays in ONE provenance-graded source.

This module loads that section (cached) and exposes it keyed by a stable design-rule
key. A critic cites by KEY — ``design_rule("survival.adjust_confounders")`` — and the
returned :class:`Evidence` carries ``kb_key`` set, so the hook can validate grounding
against the KB and read the authoritative DOI/provenance FROM the KB entry rather than
trusting an author- (or LLM-) supplied string. This closed-vocabulary discipline is
the structural fix for G1: an Evidence whose ``kb_key`` is absent/unknown is *not*
grounded and is never published, regardless of what DOI or grade it stamped on itself.

The hand-written seed table below is the FALLBACK used only when the YAML cannot be
read (so the framework still imports and the deterministic critics still ground in a
minimal environment). The YAML is the source of truth when present.
"""
from __future__ import annotations

import logging
import os
from pathlib import Path
from typing import Dict, List, Optional

from .base import Evidence, Provenance

log = logging.getLogger(__name__)


# ── Seed design-rule evidence (FALLBACK only — YAML `design_rules:` is canonical) ──
# KEY -> Evidence. GOLD = peer-reviewed/guideline w/ DOI. Mirrors the YAML section.
_SEED_DESIGN_RULES: Dict[str, Evidence] = {
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


def _qc_evidence_path() -> Optional[Path]:
    """Resolve the qc_evidence.yaml path (env override → repo-relative), or None."""
    env = os.environ.get("BIOMATE_QC_EVIDENCE_PATH")
    if env:
        p = Path(env)
        return p if p.is_file() else None
    # evidence.py = backend/lib/galaxy/ai/critics/evidence.py → parents[4] = backend
    try:
        candidate = Path(__file__).resolve().parents[4] / "config" / "qc_evidence.yaml"
        return candidate if candidate.is_file() else None
    except Exception:
        return None


def _provenance_from(value: object) -> Provenance:
    try:
        return Provenance(str(value).strip().upper())
    except Exception:
        return Provenance.NONE


def _load_design_rules_from_yaml() -> Optional[Dict[str, Evidence]]:
    """Parse the ``design_rules:`` section of qc_evidence.yaml into Evidence objects.

    Returns None (so the caller falls back to the seed) when yaml/the file/the
    section is unavailable. Each entry sets ``kb_key`` to its own key.
    """
    path = _qc_evidence_path()
    if path is None:
        return None
    try:
        import yaml  # lazy: keep module import cheap on the hot completion path
    except Exception:
        return None
    try:
        with path.open("r", encoding="utf-8") as fh:
            doc = yaml.safe_load(fh) or {}
    except Exception as exc:
        log.warning("[critics] could not read design_rules from %s: %s", path, exc)
        return None
    section = doc.get("design_rules")
    if not isinstance(section, dict):
        return None
    rules: Dict[str, Evidence] = {}
    for key, body in section.items():
        if not isinstance(body, dict):
            continue
        rules[str(key)] = Evidence(
            claim=str(body.get("claim") or body.get("rule_text") or "").strip(),
            source=str(body.get("source") or body.get("paper_ref") or "").strip(),
            doi=(str(body.get("doi") or body.get("paper_doi")).strip()
                 if (body.get("doi") or body.get("paper_doi")) else None),
            provenance=_provenance_from(body.get("provenance")),
            kb_key=str(key),
        )
    return rules or None


_CACHE: Optional[Dict[str, Evidence]] = None


def _rules() -> Dict[str, Evidence]:
    """Cached design-rule KB: YAML ``design_rules:`` if present, else the seed.

    The seed is always merged UNDER the YAML so a key the YAML forgets still grounds.
    Every returned Evidence has ``kb_key`` set (the seed objects are copied + stamped).
    """
    global _CACHE
    if _CACHE is not None:
        return _CACHE
    merged: Dict[str, Evidence] = {}
    for k, ev in _SEED_DESIGN_RULES.items():
        # copy + stamp kb_key so even the fallback grounds against its own key
        merged[k] = Evidence(claim=ev.claim, source=ev.source, doi=ev.doi,
                             provenance=ev.provenance, kb_key=k)
    from_yaml = _load_design_rules_from_yaml()
    if from_yaml:
        merged.update(from_yaml)
        log.info("[critics] loaded %d design-rule(s) from qc_evidence.yaml", len(from_yaml))
    else:
        log.info("[critics] design_rules YAML unavailable; using %d seed rule(s)", len(merged))
    _CACHE = merged
    return _CACHE


def reload_design_rules() -> Dict[str, Evidence]:
    """Drop the cache and reload (tests / after editing the YAML)."""
    global _CACHE
    _CACHE = None
    return _rules()


def design_rule(key: str) -> Optional[Evidence]:
    """Return the (KB-grounded, ``kb_key``-stamped) Evidence for a key, or None."""
    return _rules().get(key)


def require_design_rule(key: str) -> Evidence:
    """Like :func:`design_rule` but raises if the key is unknown (use in critics that
    must cite). This makes an un-grounded critic fail loudly at author time rather
    than silently emitting an uncited (and therefore suppressed) issue."""
    ev = _rules().get(key)
    if ev is None:
        raise KeyError(f"no design-rule evidence registered for {key!r}")
    return ev


def all_design_rule_keys() -> List[str]:
    """Every valid design-rule KB key — the closed citation vocabulary the hook
    (and a future LLM critic's retriever) validates against."""
    return list(_rules().keys())
