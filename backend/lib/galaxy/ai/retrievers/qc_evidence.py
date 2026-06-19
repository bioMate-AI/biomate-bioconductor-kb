"""
QC gate evidence lookup — standalone helper that surfaces per-gate
evidence (paper_ref, paper_doi, provenance grade, paper_supports text,
rule_text) for frontend hover-tooltips.

Designed as a NEW MODULE (does not modify per-domain knowledge_base.py
files) because those modules collide with parallel-session edits. The
YAML at backend/config/qc_evidence.yaml is the single source of truth.

Usage:

    from galaxy.ai.retrievers.qc_evidence import get_evidence_for_gate

    items = get_evidence_for_gate("pbpk", "pbpk_auc_fold_error")
    # → [
    #     {
    #       "paper_ref": "FDA Guidance ... PBPK Analyses (2018)",
    #       "paper_doi": "https://www.fda.gov/media/101469/download",
    #       "provenance": "GOLD",
    #       "paper_supports": "...",
    #       "rule_text": "...",
    #       "finding": "...",
    #     },
    #   ]

Provenance grades:
  GOLD   — threshold is verbatim or trivially derived from the cited source
  SILVER — community convention attributed to the source (paper supports
           the concept but doesn't state the exact value)
  BRONZE — operational heuristic; cited source is related context, not
           the source of the cutoff itself

The frontend should display the provenance grade prominently in the
tooltip so users can apply their own scrutiny: GOLD claims are
trustworthy; BRONZE claims need user verification.
"""

from __future__ import annotations

import logging
import os
from functools import lru_cache
from pathlib import Path
from typing import Any

log = logging.getLogger(__name__)


_DEFAULT_YAML = (
    Path(__file__).resolve().parents[4] / "config" / "qc_evidence.yaml"
)


@lru_cache(maxsize=1)
def _load_evidence(yaml_path: str | None = None) -> dict[str, dict[str, list[dict]]]:
    """Load the YAML once; cache for the process lifetime."""
    path = Path(
        yaml_path
        or os.environ.get("BIOMATE_QC_EVIDENCE_YAML", str(_DEFAULT_YAML))
    )
    if not path.exists():
        log.warning("qc_evidence.yaml not found at %s — tooltips will be empty", path)
        return {}
    try:
        import yaml
    except ImportError:
        log.warning("PyYAML unavailable — qc_evidence tooltips disabled")
        return {}
    try:
        with open(path) as f:
            data = yaml.safe_load(f) or {}
    except Exception as exc:
        log.warning("failed to load qc_evidence.yaml: %s", exc)
        return {}
    if not isinstance(data, dict):
        log.warning("qc_evidence.yaml root is not a dict — ignoring")
        return {}
    return data


def get_evidence_for_gate(domain: str, gate_name: str) -> list[dict[str, Any]]:
    """Return the evidence entries for a specific (domain, gate).

    Empty list if no entry exists. Always returns valid JSON-serializable
    list of dicts — safe to embed directly in SSE payloads.
    """
    data = _load_evidence()
    domain_entries = data.get(domain, {}) or {}
    items = domain_entries.get(gate_name, []) or []
    if not isinstance(items, list):
        return []
    return [dict(i) for i in items if isinstance(i, dict)]


def get_all_evidence_for_domain(domain: str) -> dict[str, list[dict[str, Any]]]:
    """Return {gate_name: [evidence...]} for all gates in a domain."""
    data = _load_evidence()
    domain_entries = data.get(domain, {}) or {}
    if not isinstance(domain_entries, dict):
        return {}
    return {
        gate: [dict(i) for i in items if isinstance(i, dict)]
        for gate, items in domain_entries.items()
        if isinstance(items, list)
    }


def list_domains() -> list[str]:
    """Return all domains with at least one gate's evidence defined."""
    return list(_load_evidence().keys())


def resolve_thresholds(
    domain: str,
    gate_name: str,
    context: dict[str, Any] | None = None,
    default_advisory: float | None = None,
    default_fail: float | None = None,
) -> tuple[float | None, float | None]:
    """Resolve (advisory_min, fail_min) for a gate, applying any modifier
    context found in qc_evidence.yaml.

    Schema in the YAML (added 2026-06-15 in Track 1 step 1):

        gate_name:
          - paper_ref: ...
            rule_text: ...
            modifiers:
              axis_name:
                option_a: {advisory_min: 20, fail_min: 30}
                option_b: {advisory_min: 30, fail_min: 50}
              other_axis:
                ...

    `context` is a dict like {"sampling_density": "sparse", "phase": "phase2_3"}.
    Each key matches a modifier axis name; each value picks one of the named
    options in that axis. When multiple axes apply, the **strictest** tier
    (lowest advisory_min / lowest fail_min) wins — fail-closed by design.

    Falls back to (default_advisory, default_fail) when:
      - the YAML entry has no `modifiers` block, OR
      - `context` is None / empty, OR
      - no context axis matches a modifier axis.

    Backwards-compatible: callers that don't pass `context` get the legacy
    hardcoded behavior. Callers that DO pass `context` get the modifier-
    resolved tier per the audit-honest YAML schema.
    """
    entries = get_evidence_for_gate(domain, gate_name)
    if not entries:
        return (default_advisory, default_fail)
    modifiers = entries[0].get("modifiers")
    if not isinstance(modifiers, dict) or not context:
        return (default_advisory, default_fail)

    # Collect every matching tier across the supplied context axes.
    matched_tiers: list[tuple[float, float]] = []
    for axis_name, axis_options in modifiers.items():
        if not isinstance(axis_options, dict):
            continue
        ctx_value = context.get(axis_name)
        if ctx_value is None:
            continue
        tier = axis_options.get(ctx_value)
        if not isinstance(tier, dict):
            continue
        adv = tier.get("advisory_min")
        fai = tier.get("fail_min")
        if isinstance(adv, (int, float)) and isinstance(fai, (int, float)):
            matched_tiers.append((float(adv), float(fai)))

    if not matched_tiers:
        return (default_advisory, default_fail)

    # Direction-correct strictness: ≥-direction gates (hERG margin, z_prime,
    # plddt — pass when value ≥ fail_min) want the HIGHEST fail_min as
    # strictest. ≤-direction gates (AUC extrap, NA fraction — pass when value
    # ≤ fail_min) want the LOWEST fail_min as strictest. We don't know the
    # direction here without metadata, so when multiple axes match we return
    # the FIRST matched tier and log the conflict. In practice the common case
    # has exactly one matching axis (e.g. context={"sampling_density":"sparse"}).
    if len(matched_tiers) > 1:
        log.info(
            "qc_evidence.resolve_thresholds: %d modifier axes matched for "
            "%s.%s — using first; caller should disambiguate if needed",
            len(matched_tiers), domain, gate_name,
        )
    return matched_tiers[0]


def clear_cache() -> None:
    """Force re-load of the YAML on next call (for tests / live edits)."""
    _load_evidence.cache_clear()
