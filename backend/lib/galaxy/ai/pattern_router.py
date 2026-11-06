"""
Pattern Router — capability-gated single-vs-multi agent pattern selection.

STATUS: standalone, INERT, disabled-by-default. This module ships the *decision
logic* plus a *flagged dispatch helper* only. It does NOT modify the live chat
path (`ai_assistant.py` / `generate_workflow_unified`); wiring is a later slice.
It performs NO network / LLM calls on its own and never imports the orchestrator
unless (a) the feature flag is ON and (b) the chosen pattern is MULTI_SPECIALIST.

Why this exists (design: docs/20261008_AGENT_PATTERNS_RESEARCH_AND_BIOMATE_INTEGRATION.md):
  - BioMate already OWNS a dormant multi-agent orchestrator
    (`agents.agent_orchestrator.AgentOrchestrator`, reachable via
    `generate_workflow_multi_agent`, zero live callers). The live path is
    hardwired to the single-pass `generate_workflow_unified`.
  - The Nature Machine Intelligence result (§2) says single-agent *baseline*
    performance per domain is the predictor: ABOVE a per-domain
    capability-saturation threshold, collaboration is noise / amplifies error ->
    use a SINGLE model; BELOW it, multi-agent adds complementary info.
  - The Claude Code pattern inventory (§3) adds task-shape rules: independent
    items -> parallel fan-out; dependent stages -> pipeline.

This router codifies that decision. It is Python 3.9-safe
(`from __future__ import annotations`, typing.Optional/List/Dict, no PEP 604 unions).
"""

from __future__ import annotations

import logging
import os
from typing import Any, Callable, Dict, List, Optional

log = logging.getLogger(__name__)

# Feature flag env var. Default FALSE — this slice is inert.
ENV_FLAG = "BIOMATE_PATTERN_ROUTER_ENABLED"

# Global default saturation threshold (NMI capability-saturation gate).
DEFAULT_THRESHOLD = 0.75


class Pattern:
    """
    Orchestration patterns the router can choose. String-valued for JSON/audit
    friendliness (used as plain strings throughout; no Enum coercion needed).
    """

    SINGLE = "SINGLE"
    MULTI_SPECIALIST = "MULTI_SPECIALIST"
    PIPELINE = "PIPELINE"
    PARALLEL_FANOUT = "PARALLEL_FANOUT"

    ALL = (SINGLE, MULTI_SPECIALIST, PIPELINE, PARALLEL_FANOUT)


# Task shapes understood by decide().
SHAPE_SINGLE = "single"
SHAPE_INDEPENDENT_ITEMS = "independent_items"
SHAPE_DEPENDENT_STAGES = "dependent_stages"
SHAPE_OPEN_ENDED = "open_ended"

VALID_SHAPES = (
    SHAPE_SINGLE,
    SHAPE_INDEPENDENT_ITEMS,
    SHAPE_DEPENDENT_STAGES,
    SHAPE_OPEN_ENDED,
)


# ---------------------------------------------------------------------------
# Conservative static baseline table (single-agent baseline pass-rate, 0..1).
#
# Injectable: pass baseline_fn=... to override (tests + production can wire this
# to real benchmark history — param_prefill / routing / admet / pbpk / boin /
# per-domain workflow pass-rates — later). These static values are deliberately
# conservative placeholders, NOT measured ground truth.
#
#   - Saturated / well-covered structured tasks (>= DEFAULT_THRESHOLD) -> SINGLE.
#   - Open-ended / novel / low-coverage domains (< threshold) -> MULTI_SPECIALIST.
#   - Unknown domains default LOW (treated as novel/ambiguous -> multi helps),
#     matching the research: novel intent is a low-baseline regime.
# ---------------------------------------------------------------------------
_STATIC_BASELINES: Dict[str, float] = {
    # --- saturated: structured, near-deterministic subtasks ---
    "routing": 0.85,
    "param_prefill": 0.80,
    "param_extraction": 0.80,
    "qc": 0.90,
    "qc_threshold": 0.90,
    # --- well-covered workflow domains (single pass already works) ---
    "transcriptomics": 0.80,
    "genomics": 0.78,
    "variant_calling": 0.78,
    "epigenomics": 0.76,
    "single_cell": 0.72,
    # --- below threshold: multi-agent adds complementary info ---
    "proteomics": 0.62,
    "metabolomics": 0.58,
    "metagenomics": 0.60,
    "cryo_em": 0.55,
    "drug_discovery": 0.60,
    "admet": 0.65,
    "pbpk": 0.55,
    "boin": 0.62,
    "systems_biology": 0.55,
    "immunology": 0.55,
    "structural_biology": 0.58,
    # --- explicitly open-ended / low-baseline (multi-agent wins) ---
    "hypothesis_generation": 0.35,
    "target_triage": 0.40,
    "cross_domain": 0.45,
    "novel_synthesis": 0.45,
}

# Default baseline for an unknown domain: below threshold -> treated as novel.
_UNKNOWN_DOMAIN_BASELINE = 0.50


def default_baseline_fn(domain: Optional[str]) -> float:
    """Conservative static single-agent baseline for a domain (0..1)."""
    if not domain:
        return _UNKNOWN_DOMAIN_BASELINE
    return _STATIC_BASELINES.get(str(domain).strip().lower(), _UNKNOWN_DOMAIN_BASELINE)


# ---------------------------------------------------------------------------
# Real-signal baseline: read BioMate benchmark pass-rates off disk when present,
# else fall back to the conservative static table above. Robust by design: any
# missing dir / parse error / unexpected shape degrades silently to static.
#
# Benchmark summaries are heterogeneous (verified against the real repo tree:
# `evaluation/results/<name>/summary.json` holds, variously, `pass_rate` as a
# 0..100 percentage, `mean_score` 0..1, or `consistency_rate` 0..1, keyed either
# by a top-level benchmark/subtask name or as a list of per-model records). The
# loader tolerates all of those and maps known benchmark names onto the router's
# domain keys; unknown shapes simply contribute nothing.
# ---------------------------------------------------------------------------

# Maps a benchmark / summary key -> the router domain key it informs. Only the
# benchmarks that correspond to a saturation-gated domain are folded in; the rest
# are ignored (they do not describe a single-vs-multi domain baseline).
_BENCHMARK_DOMAIN_ALIASES: Dict[str, str] = {
    "param_prefill": "param_prefill",
    "param_extraction": "param_extraction",
    "routing": "routing",
    "cross_domain_routing": "routing",
    "cross_domain_routing_bare": "routing",
    "admet": "admet",
    "admet_benchmark": "admet",
    "pbpk": "pbpk",
    "pbpk_benchmark": "pbpk",
    "boin": "boin",
    "boin_benchmark": "boin",
}

# Env override for the evaluation results directory (checked first).
ENV_EVAL_RESULTS_DIR = "BIOMATE_EVAL_RESULTS_DIR"

_RATE_KEYS = ("pass_rate", "mean_score", "accuracy", "consistency_rate", "score")

# Lazy cache so importing this module stays inert (no disk scan at import time).
_BENCH_FN_CACHE: Dict[str, Callable[[Optional[str]], float]] = {}


def _normalize_rate(value: Any) -> Optional[float]:
    """Coerce a reported metric to a 0..1 rate, or None if unusable."""
    try:
        v = float(value)
    except (TypeError, ValueError):
        return None
    if v != v:  # NaN
        return None
    if v > 1.0:  # a 0..100 percentage
        v = v / 100.0
    if v < 0.0:
        return None
    return 0.0 if v < 0.0 else (1.0 if v > 1.0 else v)


def _pick_rate(record: Dict[str, Any]) -> Optional[float]:
    for key in _RATE_KEYS:
        if key in record:
            rate = _normalize_rate(record.get(key))
            if rate is not None:
                return rate
    return None


def _extract_rates(obj: Any) -> Dict[str, float]:
    """Pull {name_lower: rate} out of one parsed summary document, tolerantly."""
    rates: Dict[str, float] = {}
    if isinstance(obj, dict):
        for key, val in obj.items():
            if isinstance(val, dict):
                rate = _pick_rate(val)
                if rate is not None:
                    rates[str(key).strip().lower()] = rate
    elif isinstance(obj, list):
        for item in obj:
            if not isinstance(item, dict):
                continue
            name = item.get("benchmark") or item.get("name") or item.get("model")
            rate = _pick_rate(item)
            if name and rate is not None:
                rates[str(name).strip().lower()] = rate
    return rates


def _candidate_results_dirs(results_dir):  # type: ignore[no-untyped-def]
    import os as _os
    from pathlib import Path as _Path

    cands = []
    if results_dir:
        cands.append(_Path(results_dir))
    env_dir = _os.environ.get(ENV_EVAL_RESULTS_DIR)
    if env_dir:
        cands.append(_Path(env_dir))
    try:
        repo_root = _Path(__file__).resolve().parents[4]
        cands.append(repo_root / "evaluation" / "results")
    except Exception:
        pass
    cands.append(_Path.cwd() / "evaluation" / "results")
    return cands


def _load_benchmark_baselines(results_dir=None) -> Dict[str, float]:  # type: ignore[no-untyped-def]
    """Scan evaluation summaries and return a {domain_key: rate} table.

    Returns an empty dict on any failure or if no summaries are found -- the
    caller then falls back to the static table per-domain.
    """
    import json as _json

    table: Dict[str, float] = {}
    for base in _candidate_results_dirs(results_dir):
        try:
            if not base or not base.exists() or not base.is_dir():
                continue
            # Bounded walk for summary.json / summary_*.json files.
            for path in sorted(base.rglob("summary*.json")):
                try:
                    with path.open("r", encoding="utf-8") as fh:
                        parsed = _json.load(fh)
                except Exception:
                    continue
                for raw_name, rate in _extract_rates(parsed).items():
                    domain = _BENCHMARK_DOMAIN_ALIASES.get(raw_name)
                    if domain is None and raw_name in _STATIC_BASELINES:
                        domain = raw_name  # a summary keyed directly by a domain
                    if domain is not None:
                        # Keep the first seen value (sorted order = deterministic).
                        table.setdefault(domain, rate)
        except Exception:
            # Any unexpected error on a candidate -> skip it, keep going.
            continue
    return table


def make_benchmark_baseline_fn(
    results_dir=None,
    static_fn: Optional[Callable[[Optional[str]], float]] = None,
) -> Callable[[Optional[str]], float]:
    """Build a baseline_fn backed by real benchmark pass-rates where available.

    Loads the on-disk table ONCE (any failure -> empty table), then returns a
    closure: a domain present in the real table yields its measured rate, every
    other domain falls through to ``static_fn`` (the conservative static table by
    default). Drop-in for ``PatternRouter(baseline_fn=...)``.
    """
    static = static_fn if static_fn is not None else default_baseline_fn
    try:
        real = _load_benchmark_baselines(results_dir)
    except Exception as exc:  # pragma: no cover - defensive; loader is already guarded
        log.warning("benchmark baseline load failed (%s); using static table", exc)
        real = {}

    def _fn(domain: Optional[str]) -> float:
        if domain:
            key = str(domain).strip().lower()
            if key in real:
                return real[key]
        return static(domain)

    return _fn


def benchmark_baseline_fn(domain: Optional[str]) -> float:
    """Convenience real-signal baseline_fn (lazily built + cached, default dirs).

    Equivalent to ``make_benchmark_baseline_fn()`` but memoized so repeated use
    never re-scans disk, and so importing this module performs no I/O.
    """
    fn = _BENCH_FN_CACHE.get("default")
    if fn is None:
        fn = make_benchmark_baseline_fn()
        _BENCH_FN_CACHE["default"] = fn
    return fn(domain)


def _task_from_context(
    query: str,
    context: Optional[Dict[str, Any]] = None,
) -> Dict[str, Any]:
    """Derive a minimal router task descriptor from the live request.

    Conservative: workflow generation defaults to the single-vs-multi capability
    gate (shape ``single``). A ``domain`` / ``shape`` carried on ``context`` is
    honored when present; otherwise an unknown domain gates low -> the router may
    choose MULTI_SPECIALIST (only acted on when the feature flag is ON).
    """
    ctx = context or {}
    domain = ctx.get("domain") or ctx.get("workflow_domain")
    shape = ctx.get("shape") or SHAPE_SINGLE
    return {"domain": domain, "shape": shape}


def maybe_route_workflow_generation(
    query: str,
    context: Optional[Dict[str, Any]] = None,
    task: Optional[Dict[str, Any]] = None,
    enabled: Optional[bool] = None,
    router: Optional["PatternRouter"] = None,
    **kw: Any,
) -> Dict[str, Any]:
    """Flag-gated entry the live workflow-generation path delegates to.

    This is the single, independently-tested seam between ``ai_assistant`` and the
    orchestration decision. It guarantees the default (flag OFF) is a pure no-op:

      - ``enabled`` is False (default, from env ``BIOMATE_PATTERN_ROUTER_ENABLED``)
        -> returns ``{"proceed": True, "dispatched": False, "enabled": False}``
        WITHOUT constructing or invoking any PatternRouter / orchestrator. The
        caller then proceeds exactly as it does today.
      - ``enabled`` is True -> consults ``PatternRouter.route_and_maybe_dispatch``
        (which itself only reaches the dormant multi-agent orchestrator for a
        MULTI_SPECIALIST decision). ``proceed`` is True unless a dispatch produced
        a result the caller should use instead of the default single pass.
    """
    if enabled is None:
        enabled = _env_enabled()

    if not enabled:
        return {
            "proceed": True,
            "dispatched": False,
            "enabled": False,
            "reason": "pattern router disabled (default) -- proceed as normal",
        }

    task = task if task is not None else _task_from_context(query, context)
    active_router = router if router is not None else PatternRouter(enabled=True)
    out = active_router.route_and_maybe_dispatch(task, query, **kw)
    out["enabled"] = True
    # Use a dispatched result if one came back; otherwise fall through to the
    # default single-pass generation.
    out["proceed"] = not bool(out.get("dispatched"))
    return out


def _env_enabled() -> bool:
    """Read the feature flag from the environment (default FALSE)."""
    raw = os.environ.get(ENV_FLAG, "")
    return str(raw).strip().lower() in ("1", "true", "yes", "on")


class PatternRouter:
    """
    Decides single-vs-multi agent orchestration pattern per task, and can
    (only when explicitly enabled) dispatch low-baseline intents to BioMate's
    already-built-but-dormant multi-agent orchestrator.
    """

    def __init__(
        self,
        baseline_fn: Optional[Callable[[Optional[str]], float]] = None,
        thresholds: Optional[Dict[str, float]] = None,
        enabled: Optional[bool] = None,
        orchestrator_factory: Optional[Callable[..., Any]] = None,
    ) -> None:
        """
        Args:
            baseline_fn: domain -> single-agent baseline (0..1). Injectable for
                tests / real benchmark wiring. Defaults to the conservative
                static table (`default_baseline_fn`).
            thresholds: per-domain saturation thresholds; missing domains fall
                back to the global default (`DEFAULT_THRESHOLD`, 0.75).
            enabled: explicit flag override. When None, read from env
                `BIOMATE_PATTERN_ROUTER_ENABLED` (default FALSE).
            orchestrator_factory: injectable factory used ONLY on an enabled
                MULTI_SPECIALIST dispatch. When None, the real
                `agents.agent_orchestrator.create_agent_orchestrator` is
                imported lazily at dispatch time (never at import time).
        """
        self.baseline_fn = baseline_fn if baseline_fn is not None else default_baseline_fn
        self.thresholds: Dict[str, float] = dict(thresholds) if thresholds else {}
        self.enabled = _env_enabled() if enabled is None else bool(enabled)
        self._orchestrator_factory = orchestrator_factory

    # ------------------------------------------------------------------ #
    # Threshold lookup
    # ------------------------------------------------------------------ #
    def threshold_for(self, domain: Optional[str]) -> float:
        """Per-domain saturation threshold, falling back to the global default."""
        if domain:
            key = str(domain).strip().lower()
            if key in self.thresholds:
                return self.thresholds[key]
        return self.thresholds.get("default", DEFAULT_THRESHOLD)

    def baseline_for(self, domain: Optional[str]) -> float:
        """Single-agent baseline for a domain (0..1), clamped defensively."""
        try:
            val = float(self.baseline_fn(domain))
        except Exception as exc:  # defensive: a bad injected fn must not crash routing
            log.warning("baseline_fn raised for domain=%r (%s); using conservative default", domain, exc)
            val = _UNKNOWN_DOMAIN_BASELINE
        if val < 0.0:
            return 0.0
        if val > 1.0:
            return 1.0
        return val

    # ------------------------------------------------------------------ #
    # Decision
    # ------------------------------------------------------------------ #
    def decide(self, task: Dict[str, Any]) -> Dict[str, Any]:
        """
        Choose an orchestration pattern for `task`.

        `task` carries at least {"domain": str, "shape": str} where shape is one
        of {"single", "independent_items", "dependent_stages", "open_ended"}.

        Rules:
          - shape == independent_items  -> PARALLEL_FANOUT
          - shape == dependent_stages   -> PIPELINE
          - otherwise (single/open_ended) -> capability gate:
                baseline(domain) >= threshold(domain)  -> SINGLE
                else                                    -> MULTI_SPECIALIST

        Always returns {pattern, reason, baseline, threshold, domain, shape}
        with the numbers filled in for auditability, regardless of pattern.
        """
        task = task or {}
        domain = task.get("domain")
        shape = task.get("shape", SHAPE_SINGLE) or SHAPE_SINGLE

        baseline = self.baseline_for(domain)
        threshold = self.threshold_for(domain)

        if shape == SHAPE_INDEPENDENT_ITEMS:
            pattern = Pattern.PARALLEL_FANOUT
            reason = (
                "task shape 'independent_items' -> PARALLEL_FANOUT: independent "
                "per-item work parallelizes (Claude Code fan-out)"
            )
        elif shape == SHAPE_DEPENDENT_STAGES:
            pattern = Pattern.PIPELINE
            reason = (
                "task shape 'dependent_stages' -> PIPELINE: ordered dependency "
                "chain runs as a pipeline"
            )
        else:
            # Capability-saturation gate (NMI rule).
            if baseline >= threshold:
                pattern = Pattern.SINGLE
                reason = (
                    "baseline %.3f >= threshold %.3f (domain=%r saturated) -> "
                    "SINGLE: collaboration would add noise above the saturation "
                    "threshold" % (baseline, threshold, domain)
                )
            else:
                pattern = Pattern.MULTI_SPECIALIST
                reason = (
                    "baseline %.3f < threshold %.3f (domain=%r below saturation) "
                    "-> MULTI_SPECIALIST: multi-agent collaboration adds "
                    "complementary info at low baseline" % (baseline, threshold, domain)
                )

        return {
            "pattern": pattern,
            "reason": reason,
            "baseline": baseline,
            "threshold": threshold,
            "domain": domain,
            "shape": shape,
        }

    # ------------------------------------------------------------------ #
    # PARALLEL_FANOUT execution via the shared map-reduce layer
    # ------------------------------------------------------------------ #
    def fanout(
        self,
        units: List[Any],
        worker_fn: Callable[[Any], Any],
        reduce_fn: Optional[Callable[[List[Any]], Any]] = None,
        max_concurrent: int = 8,
    ) -> Dict[str, Any]:
        """Execute the PARALLEL_FANOUT pattern over independent ``units``.

        Thin, decision-free delegate to the shared ``map_reduce`` fan-out layer
        (worker injected -> hermetically testable; bounded concurrency; per-unit
        errors isolated; input-order results). This is the execution primitive
        the router's PARALLEL_FANOUT decision points to for independent-item work
        (per-sample / per-candidate / portfolio).

        Imported lazily so module import stays inert and works both as the
        installed ``galaxy.ai`` package and as a loose script on sys.path.
        """
        try:
            from .map_reduce import map_reduce
        except (ImportError, ValueError):  # pragma: no cover - loose/script path
            from map_reduce import map_reduce  # type: ignore
        return map_reduce(
            list(units or []),
            worker_fn,
            reduce_fn=reduce_fn,
            max_concurrent=max_concurrent,
        )

    # ------------------------------------------------------------------ #
    # Flagged dispatch helper (INERT unless enabled)
    # ------------------------------------------------------------------ #
    def route_and_maybe_dispatch(
        self,
        task: Dict[str, Any],
        query: str,
        **kw: Any,
    ) -> Dict[str, Any]:
        """
        Compute the decision and, ONLY when enabled AND pattern == MULTI_SPECIALIST,
        dispatch to the dormant multi-agent orchestrator.

        Behavior:
          - Not enabled              -> {"dispatched": False, "decision": ...}
                                        (pure decision, NO behavior change).
          - Enabled, non-multi       -> {"dispatched": False, "decision": ...}
                                        (orchestrator is NOT called).
          - Enabled, MULTI_SPECIALIST -> lazily create the orchestrator and call
                                        generate_workflow(query, parallel=True, **kw);
                                        returns {"dispatched": True, "decision": ...,
                                        "result": <OrchestrationResult>}.
          - Any dispatch failure      -> degrades to decision-only:
                                        {"dispatched": False, "decision": ...,
                                         "degraded": True, "error": "<msg>"}.
        """
        decision = self.decide(task)

        if not self.enabled:
            return {"dispatched": False, "decision": decision}

        if decision["pattern"] != Pattern.MULTI_SPECIALIST:
            return {"dispatched": False, "decision": decision}

        try:
            factory = self._orchestrator_factory
            if factory is None:
                # LAZY import — never at module import time, only on an enabled
                # multi-specialist dispatch.
                from .agents.agent_orchestrator import create_agent_orchestrator as factory  # type: ignore

            orchestrator = factory()
            result = orchestrator.generate_workflow(query, parallel=True, **kw)
            return {"dispatched": True, "decision": decision, "result": result}
        except Exception as exc:  # degrade to decision-only; never break the caller
            log.warning("Multi-specialist dispatch failed; degrading to decision-only: %s", exc)
            return {
                "dispatched": False,
                "decision": decision,
                "degraded": True,
                "error": str(exc),
            }


__all__ = [
    "Pattern",
    "PatternRouter",
    "default_baseline_fn",
    "benchmark_baseline_fn",
    "make_benchmark_baseline_fn",
    "maybe_route_workflow_generation",
    "DEFAULT_THRESHOLD",
    "ENV_FLAG",
    "ENV_EVAL_RESULTS_DIR",
    "SHAPE_SINGLE",
    "SHAPE_INDEPENDENT_ITEMS",
    "SHAPE_DEPENDENT_STAGES",
    "SHAPE_OPEN_ENDED",
]
