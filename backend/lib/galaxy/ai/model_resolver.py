"""
Central LLM model resolver — the single source of truth for which model each *role* uses.

Replaces the ~scattered hardcoded model literals documented in
docs/20260824_LLM_CONFIG_FRAGMENTATION_AUDIT.md. Every module that needs a model
should call ``resolve_model(role, config=..., user_overrides=...)`` instead of
hardcoding a model string, so the choice is centrally auditable, upgradable in one
place, and overridable per user (the prerequisite for BYOK and the BioMate×LLM matrix).

Precedence (highest first):
  1. user_overrides[role]  — a per-role BYOK override
  2. user_overrides['model'] — a single BYOK model applied to *every* role
  3. env  BIOMATE_MODEL_<ROLE>  — per-role env override
  4. env  BIOMATE_MODEL         — global env override for every role
  5. config['model_roles'][role] — per-role config map
  6. ROLE_DEFAULTS[role]        — sensible current default for the role
  7. config.llm_model / config['llm_model'] / GLOBAL_DEFAULT — global fallback
"""
import os
from typing import Any, Dict, Optional

# Sensible, CURRENT defaults per role. This is the one place to bump models.
# (Supersedes the stale literals: claude-3-5-sonnet-20241022, claude-3-haiku-20240307,
#  gemini-2.0-flash-exp, claude-sonnet-4-20250514.)
ROLE_DEFAULTS: Dict[str, str] = {
    "intent":    "gemini-3.8-flash",   # cheap/fast intent classification
    "tool_rank": "claude-haiku-4-5",   # tool re-ranking
    "response":  "claude-sonnet-4-5",  # main chat response
    "convert":   "claude-sonnet-4-5",  # process/workflow conversion (quality)
    "autofix":   "claude-sonnet-4-5",  # workflow auto-fix / remediation
    "audit":     "claude-haiku-4-5",   # cheap semantic audit / log analysis / judging
    "rag":       "gemini-3.8-flash",   # fast RAG / lightweight utility calls
    "judge":     "claude-haiku-4-5",   # benchmark hallucination judge
    "param":     "claude-sonnet-4-5",  # parameter extraction
}
GLOBAL_DEFAULT: str = "claude-sonnet-4-5"


def _config_dict(config: Any) -> Dict[str, Any]:
    """Coerce an AIConfig / dict / None into a plain config dict."""
    if config is None:
        return {}
    inner = getattr(config, "config", None)
    if isinstance(inner, dict):
        return inner
    if isinstance(config, dict):
        return config
    return {}


def resolve_model(
    role: str,
    config: Any = None,
    user_overrides: Optional[Dict[str, str]] = None,
) -> str:
    """Return the model id for ``role`` under the documented precedence.

    ``config`` may be an AIConfig instance, a plain dict, or None.
    ``user_overrides`` is a per-user map (e.g. {'model': 'anthropic/claude-opus-4.1'}
    for BYOK, or {'response': '...'} for a per-role override).
    """
    # 1 + 2. per-user BYOK overrides (role-specific, then a single model for all roles)
    if user_overrides:
        m = user_overrides.get(role) or user_overrides.get("model")
        if m:
            return m
    # 3 + 4. env overrides
    env = os.getenv("BIOMATE_MODEL_" + role.upper()) or os.getenv("BIOMATE_MODEL")
    if env:
        return env
    # 5. per-role config map
    cfg = _config_dict(config)
    roles = cfg.get("model_roles") or {}
    if isinstance(roles, dict) and roles.get(role):
        return roles[role]
    # 6. sensible per-role default
    if role in ROLE_DEFAULTS:
        return ROLE_DEFAULTS[role]
    # 7. global fallback
    return cfg.get("llm_model") or getattr(config, "llm_model", None) or GLOBAL_DEFAULT
