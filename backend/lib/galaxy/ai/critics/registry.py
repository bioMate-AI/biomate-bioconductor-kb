"""
Critic registry — domain → applicable critics.

Mirrors the pattern of ``pilot_analysis/registry.py`` (a wired, pluggable registry),
but for POST-run judgment instead of PRE-run parameter inference. A critic registers
itself against its ``domain``; the hook asks the registry for the critics applicable
to a given :class:`RunContext`.

The default process-wide registry (:data:`default_registry`) is populated lazily by
:func:`register_builtin_critics`, so importing this module stays cheap and import of
concrete critics (which may pull in heavier deps) is deferred until first use.
"""
from __future__ import annotations

import logging
from typing import Dict, List, Type

from .base import Critic
from .run_context import RunContext

log = logging.getLogger(__name__)


class CriticRegistry:
    """Holds Critic instances keyed by domain, with lookup by RunContext."""

    def __init__(self) -> None:
        self._by_domain: Dict[str, List[Critic]] = {}
        self._by_id: Dict[str, Critic] = {}

    def register(self, critic: Critic) -> Critic:
        """Register a critic instance. Idempotent on critic_id."""
        if not critic.critic_id:
            raise ValueError(f"Critic {critic!r} has no critic_id")
        if critic.critic_id in self._by_id:
            log.debug("[critics] critic %s already registered — replacing", critic.critic_id)
        self._by_id[critic.critic_id] = critic
        self._by_domain.setdefault(critic.domain or "*", []).append(critic)
        return critic

    def register_class(self, cls: Type[Critic]) -> Type[Critic]:
        """Decorator form: register a default-constructed instance of ``cls``."""
        self.register(cls())
        return cls

    def all(self) -> List[Critic]:
        return list(self._by_id.values())

    def for_domain(self, domain: str) -> List[Critic]:
        """Critics registered for ``domain`` plus domain-agnostic ('*') critics."""
        return list(self._by_domain.get(domain, [])) + list(self._by_domain.get("*", []))

    def for_context(self, ctx: RunContext) -> List[Critic]:
        """All critics whose ``applies_to(ctx)`` is True.

        We consult the run's declared domain first (cheap), but also give every
        domain-agnostic critic and — as a fallback for runs that did not stamp a
        domain — every registered critic a chance to self-select via applies_to.
        """
        candidates: List[Critic] = []
        seen = set()
        pool = self.for_domain(ctx.workflow_domain) if ctx.workflow_domain else self.all()
        # Always include the universal bucket so a mis-/un-stamped domain still matches.
        for c in pool + self._by_domain.get("*", []):
            if c.critic_id in seen:
                continue
            seen.add(c.critic_id)
            try:
                if c.applies_to(ctx):
                    candidates.append(c)
            except Exception as exc:  # a broken applies_to must not break dispatch
                log.warning("[critics] applies_to failed for %s: %s", c.critic_id, exc)
        return candidates


# ── process-wide default registry ────────────────────────────────────────────

default_registry = CriticRegistry()
_builtins_loaded = False


def register_builtin_critics(registry: CriticRegistry = default_registry) -> CriticRegistry:
    """Populate ``registry`` with the shipped critics. Safe to call repeatedly."""
    global _builtins_loaded
    if _builtins_loaded and registry is default_registry:
        return registry
    # Deferred imports: concrete critics only load when the framework is first used.
    from .critics.survival import SurvivalConfoundingCritic, SurvivalPHCritic
    from .critics.power import PowerEPVCritic
    from .critics.output_presence import OutputPresenceCritic

    for cls in (
        SurvivalConfoundingCritic, SurvivalPHCritic,
        PowerEPVCritic, OutputPresenceCritic,
    ):
        registry.register(cls())
    if registry is default_registry:
        _builtins_loaded = True
    log.info("[critics] registered %d built-in critic(s)", len(registry.all()))
    return registry


def get_registry() -> CriticRegistry:
    """Return the default registry, populated with built-ins on first call."""
    register_builtin_critics(default_registry)
    return default_registry
