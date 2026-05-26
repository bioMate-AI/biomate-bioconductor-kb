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


def clear_cache() -> None:
    """Force re-load of the YAML on next call (for tests / live edits)."""
    _load_evidence.cache_clear()
