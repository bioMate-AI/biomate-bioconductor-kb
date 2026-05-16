"""
Regulatory-science overrides loader (item 4 from handoff).

Provides a single YAML file (`data/regulatory_training/regulatory_science_overrides.yaml`)
where the regulatory science team can encode rule refinements derived from
customer dismissals — without code edits.

Each checker module reads its own section at import time and adjusts its rule
set accordingly. The first concrete use is phase_gating: dismissals showing
that "hERG required" doesn't apply to topical/ophthalmic products → encoded
as an exempt-when clause in the YAML.

Schema:
  phase_gating:
    - rule_id: hERG_required
      exempt_when:
        route: [topical, ophthalmic]
        indication_class: [topical_dermatology]
      added_by: reg-science-2026-Q3
      source_dismissals: 12   # how many customer dismissals motivated this
"""
from __future__ import annotations

import logging
from functools import lru_cache
from pathlib import Path
from typing import Any

log = logging.getLogger(__name__)

_OVERRIDES_PATH = (
    Path(__file__).resolve().parents[5]
    / "data" / "regulatory_training" / "regulatory_science_overrides.yaml"
)


@lru_cache(maxsize=1)
def load_overrides() -> dict[str, list[dict[str, Any]]]:
    """
    Load the overrides YAML. Returns a dict keyed by checker module name.
    Each value is a list of override entries.

    Returns empty dict (no overrides) when:
      - File doesn't exist (default case before any rules are added)
      - PyYAML not installed (fail soft — don't block checker imports)
      - File is malformed (logs warning, returns empty)
    """
    if not _OVERRIDES_PATH.exists():
        return {}
    try:
        import yaml  # type: ignore
    except ImportError:
        log.warning("[overrides] PyYAML not available — overrides disabled")
        return {}
    try:
        with _OVERRIDES_PATH.open() as f:
            data = yaml.safe_load(f) or {}
        if not isinstance(data, dict):
            log.warning("[overrides] root is not a mapping; ignoring")
            return {}
        return data
    except Exception as e:
        log.warning("[overrides] failed to load %s: %s", _OVERRIDES_PATH, e)
        return {}


def overrides_for(checker_name: str) -> list[dict[str, Any]]:
    """Return the override entries for one checker module."""
    return load_overrides().get(checker_name, [])


def is_exempt(
    checker_name: str,
    rule_id: str,
    context: dict[str, Any],
) -> bool:
    """
    Return True iff the rule is exempted by the overrides given the current
    context. Context fields commonly used:
      route                 — e.g. "topical", "oral", "intravenous"
      indication_class      — e.g. "oncology", "topical_dermatology"
      population            — e.g. "wocbp", "healthy_adult"
      trial_duration_days   — int
    """
    for entry in overrides_for(checker_name):
        if entry.get("rule_id") != rule_id:
            continue
        exempt_when = entry.get("exempt_when") or {}
        if _matches(exempt_when, context):
            return True
    return False


def _matches(exempt_when: dict[str, Any], context: dict[str, Any]) -> bool:
    """All fields in exempt_when must match the context (list = any-of)."""
    for field, expected in exempt_when.items():
        actual = context.get(field)
        if actual is None:
            return False
        if isinstance(expected, list):
            if actual not in expected:
                return False
        else:
            if actual != expected:
                return False
    return True


if __name__ == "__main__":
    # Smoke test — show current overrides + an exemption check
    print(f"overrides file: {_OVERRIDES_PATH}")
    print(f"exists: {_OVERRIDES_PATH.exists()}")
    print(f"loaded: {load_overrides()}")
    print(f"phase_gating hERG exempt for topical? "
          f"{is_exempt('phase_gating', 'hERG_required', {'route': 'topical'})}")
