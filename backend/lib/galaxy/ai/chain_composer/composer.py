"""Compose a candidate chain for a user query.

Orchestrates: pattern retrieval → curated-chain exemplars → LLM compose
(or deterministic stub if no LLM available) → confidence score → surfacing mode.

LLM is optional in the prototype — when a key isn't configured we fall back to
a stub that returns the top curated chain (or a single-step plan keyed off the
top pattern's first instantiation). This lets the prototype run end-to-end
in CI / dev without external dependencies. Real LLM integration plugs in via
`compose_chain(llm=callable)`.
"""

from __future__ import annotations

import json
import re
from dataclasses import asdict, dataclass, field
from typing import Any, Callable, Dict, List, Optional, Set

from .confidence import (
    ConfidenceResult,
    ConfidenceSignals,
    SurfacingMode,
    score_confidence,
)
from .llm_adapter import default_llm, default_ner_llm
from .ner import QueryEntities, extract_entities, extract_entities_offline
from .pattern_loader import Pattern, load_patterns
from .retrieval import (
    ScoredChain,
    ScoredPattern,
    ScoredWorkflow,
    retrieve_curated_chains,
    retrieve_patterns,
    retrieve_workflows,
)
from .types import ChainEdge, ChainStep, ComposedChain, SurfacingMode
from . import verifier as _verifier
import logging
import os

log = logging.getLogger(__name__)


def _debug_enabled() -> bool:
    return bool(os.environ.get("BIOMATE_COMPOSER_DEBUG"))


def _debug(msg: str, *args: Any) -> None:
    """Emit to stderr when BIOMATE_COMPOSER_DEBUG is set. Avoids logging config."""
    if _debug_enabled():
        import sys
        sys.stderr.write("[composer] " + (msg % args if args else msg) + "\n")


# (ChainStep, ChainEdge, ComposedChain now live in .types — both composer
# and verifier import from there to avoid a circular dependency.)


# Legacy hard-coded vocabulary kept only for the deprecated stub path.
# Production specificity now comes from ner.QueryEntities.specificity_score().
_LEGACY_SPECIFICITY_TERMS = {
    "human", "mouse", "rat", "rna-seq", "atac-seq", "scrna", "wgs", "wes",
    "deseq2", "seurat", "admet", "smiles", "docking", "tcga", "ukbiobank",
}


def _legacy_query_specificity(query: str) -> float:
    """Fallback when NER produces zero entities (very vague query)."""
    q = query.lower()
    hits = sum(1 for t in _LEGACY_SPECIFICITY_TERMS if t in q)
    return min(1.0, hits / 4.0)


# Bound the curated_chain_score normalization to a reasonable range. The
# retrieval scores are unbounded jaccard-ish values (typically 0.5–3.0 for
# good hits); we map ≥1.5 to ~1.0.
def _normalize_chain_score(raw: float) -> float:
    return min(1.0, raw / 1.5)


def _normalize_pattern_score(raw: float) -> float:
    return min(1.0, raw / 2.0)


# Pattern → set of typical domains. Derived once at module load by scanning
# each pattern's `Instantiations` text for backtick-quoted workflow names
# that appear in the catalog. Conservative: a pattern with no recognizable
# workflow names gets an empty set and is treated as universally-applicable.
_PATTERN_DOMAINS_CACHE: Dict[str, set] = {}


def _pattern_typical_domains(pattern: Pattern, workflow_domains: Dict[str, str]) -> set:
    """Return the set of catalog domains the pattern's instantiations point at."""
    cached = _PATTERN_DOMAINS_CACHE.get(pattern.name)
    if cached is not None:
        return cached
    import re as _re
    domains: set = set()
    text = " ".join(pattern.instantiations) if pattern.instantiations else ""
    # Pull names from backticks (`nf-core/rnaseq`) and also bare nf-core/* tokens.
    for m in _re.findall(r"`([^`]+)`", text):
        d = workflow_domains.get(m.strip())
        if d:
            domains.add(d)
    for m in _re.findall(r"\b(nf-core/[a-z0-9_]+)\b", text):
        d = workflow_domains.get(m)
        if d:
            domains.add(d)
    _PATTERN_DOMAINS_CACHE[pattern.name] = domains
    return domains


def _load_workflow_domains(db_path) -> Dict[str, str]:
    """Map workflow name → domain. Cached at module level via the retrieval
    module's index (which we don't want to import directly here to avoid
    circularity). Fresh small query: ~30ms uncached, negligible cached."""
    import sqlite3 as _sqlite3
    try:
        conn = _sqlite3.connect(str(db_path))
        rows = conn.execute(
            "SELECT name, COALESCE(domain,'') FROM workflows WHERE executable=1"
        ).fetchall()
        conn.close()
    except Exception:
        return {}
    return {n: d for n, d in rows if n}


def _pattern_chain_agreement(
    top_patterns: List[ScoredPattern],
    top_chains: List[ScoredChain],
    workflow_domains: Dict[str, str],
) -> float:
    """1.0 = neutral (no top chain, or no signal). Lower means disagreement.

    Algorithm: if the top pattern's typical domains intersect the top chain's
    domain → 1.0. If both are known and disjoint → 0.3 (significant
    disagreement). If pattern has no known domain → 1.0 (can't disagree).
    """
    if not top_chains or not top_patterns:
        return 1.0
    pat_domains = _pattern_typical_domains(top_patterns[0].pattern, workflow_domains)
    if not pat_domains:
        return 1.0
    chain_domain = (top_chains[0].domain or "").strip().lower()
    if not chain_domain:
        return 1.0
    if any(chain_domain == d.lower() for d in pat_domains):
        return 1.0
    # Soft partial credit when domains are in the same broad family
    # (transcriptomics ↔ genomics ↔ epigenomics often co-occur in
    # multi-omics chains).
    OMICS_FAMILY = {"transcriptomics", "genomics", "epigenomics", "proteomics"}
    pat_lower = {d.lower() for d in pat_domains}
    if chain_domain in OMICS_FAMILY and pat_lower & OMICS_FAMILY:
        return 0.7
    return 0.3


def _downstream_determinism(top_patterns: List[ScoredPattern]) -> float:
    """How uniquely does one pattern dominate?
    Score gap between top-1 and top-2 → high determinism.
    """
    if not top_patterns:
        return 0.3
    if len(top_patterns) == 1:
        return 0.9
    gap = top_patterns[0].score - top_patterns[1].score
    # Normalize: gap ≥ 1.0 → very deterministic; 0 → ambiguous.
    return _clip01(0.3 + gap)


_SPLITSTEP_SIGNALS = (
    "step by step", "step-by-step", "let's start", "start with",
    "first step", "one step at a time", "first", "begin",
)
_UPFRONT_SIGNALS = (
    "do the whole", "full analysis", "end to end", "end-to-end",
    "all the way", "complete pipeline",
)


def _user_signal(query: str) -> float:
    q = query.lower()
    if any(s in q for s in _UPFRONT_SIGNALS):
        return 0.3
    if any(s in q for s in _SPLITSTEP_SIGNALS):
        return -0.3
    return 0.0


def _clip01(x: float) -> float:
    return max(0.0, min(1.0, x))


_SENTINEL_AUTO = object()


def compose_chain(
    query: str,
    *,
    user_profile_bias: float = 0.0,
    llm: Any = _SENTINEL_AUTO,
    patterns: Optional[List[Pattern]] = None,
    top_k_patterns: int = 3,
    top_k_chains: int = 3,
    top_k_workflows: int = 10,
    entities: Optional[QueryEntities] = None,
    enable_llm_ner: bool = True,
) -> ComposedChain:
    """Compose a candidate chain for a user query.

    Args:
        query: free-text user query.
        user_profile_bias: -0.2..+0.2 hint from memory (beginner → negative,
            PI/experienced → positive). Default 0.
        llm: callable that takes a prompt and returns a string. If omitted,
            `default_llm()` is invoked — returns None when no API key is set,
            falling back to the deterministic stub. Pass `llm=None` explicitly
            to force the stub path (useful for offline tests).
        patterns: override the loaded pattern library (for tests).
        top_k_patterns: how many patterns to retrieve.
        top_k_chains: how many curated chains to retrieve as exemplars.
        entities: pre-extracted query entities (for tests / when caller has
            already done NER). If None, extracted via `ner.extract_entities`.
        enable_llm_ner: when True and an LLM is available, NER uses the LLM
            (richer extraction). Otherwise falls back to dictionary NER.
    """
    patterns = patterns if patterns is not None else load_patterns()

    # Auto-resolve LLM only on the sentinel value, so callers can pass
    # llm=None explicitly to force the stub path.
    if llm is _SENTINEL_AUTO:
        llm = default_llm()

    # NER first — entities feed both retrieval and confidence scoring. Use the
    # cheaper NER-tier model when possible (default Haiku); fall back to the
    # compose-tier LLM if no NER-tier resolves (same API key needed either way).
    if entities is None:
        if enable_llm_ner:
            ner_llm = default_ner_llm() if callable(llm) else None
            if ner_llm is None and callable(llm):
                ner_llm = llm  # share the compose model when NER tier unavailable
        else:
            ner_llm = None
        _debug("NER LLM: %s", "configured" if ner_llm else "offline-only")
        entities = extract_entities(query, llm=ner_llm)
    _debug("entities: %d terms (%s)", len(entities.all_terms()),
           ",".join(entities.all_terms()[:6]))
    entity_terms = entities.all_terms()

    top_patterns = retrieve_patterns(
        query, patterns=patterns, top_k=top_k_patterns, entity_terms=entity_terms,
    )
    top_chains = retrieve_curated_chains(
        query, top_k=top_k_chains, entity_terms=entity_terms,
    )
    top_workflows = retrieve_workflows(
        query, top_k=top_k_workflows, entity_terms=entity_terms,
    )

    # Specificity: prefer entity-count; fall back to legacy keyword scan if NER
    # returned nothing (very vague query, or LLM failed silently).
    spec = entities.specificity_score()
    if spec == 0.0:
        spec = _legacy_query_specificity(query)

    chain_score = _normalize_chain_score(top_chains[0].score) if top_chains else 0.0
    pattern_score = _normalize_pattern_score(top_patterns[0].score) if top_patterns else 0.0

    # Vague-query reactive floor: surface reactively when the query has NO
    # recognizable entities AND retrieval is weak (raw BM25 < 5.0 — vague
    # short queries score 1-3, real specific queries score 8-20). Patterns
    # ARE a specificity signal — strong pattern retrieval means the user
    # has shape in mind even when their vocabulary isn't in our NER dict.
    # Raw BM25 is the right discriminator here, not normalized, because
    # normalization saturates at ~2.0 and discards the long-tail signal.
    _weak_pattern_score = (
        not top_patterns or top_patterns[0].score < 5.0
    )
    _force_reactive = (
        len(entity_terms) == 0
        and _weak_pattern_score
        and _user_signal(query) <= 0
    )
    if _force_reactive:
        _debug("vague-query reactive floor engaged (no entities, weak pattern)")
    # Pattern-chain agreement uses the catalog's domain map. Loaded lazily;
    # ~30ms uncached, ~1ms on the second call within a process.
    from .retrieval import _DEFAULT_DB as _DEF_DB
    workflow_domains = _load_workflow_domains(_DEF_DB)
    agreement = _pattern_chain_agreement(top_patterns, top_chains, workflow_domains)
    _debug("pattern-chain agreement: %.2f (top_pattern=%s top_chain=%s [%s])",
           agreement,
           top_patterns[0].pattern.name if top_patterns else "—",
           top_chains[0].name if top_chains else "—",
           top_chains[0].domain if top_chains else "—")
    signals = ConfidenceSignals(
        curated_chain_score=chain_score,
        pattern_match_score=pattern_score,
        query_specificity=spec,
        downstream_determinism=_downstream_determinism(top_patterns),
        user_signal=_user_signal(query),
        user_profile_bias=user_profile_bias,
        pattern_chain_agreement=agreement,
    )
    conf = score_confidence(signals)
    if _force_reactive:
        # Override surfacing mode regardless of computed confidence.
        conf.mode = "reactive"

    # LLM short-circuit: when the top curated chain is a near-perfect match
    # AND the pattern-chain agreement is full, the LLM cannot improve the
    # outcome — only cost time and tokens. Pass the curated chain through
    # deterministically. Tunable via env.
    try:
        shortcircuit_min = float(os.environ.get("BIOMATE_LLM_SHORTCIRCUIT_MIN", "0.95"))
    except (TypeError, ValueError):
        shortcircuit_min = 0.95
    _shortcircuit = (
        top_chains
        and _normalize_chain_score(top_chains[0].score) >= shortcircuit_min
        and agreement >= 0.999
        and not _force_reactive
    )
    if _shortcircuit:
        _debug("LLM short-circuit: top chain %s at normalized %.2f >= %.2f, agreement %.2f — skipping LLM",
               top_chains[0].name, _normalize_chain_score(top_chains[0].score),
               shortcircuit_min, agreement)

    # Branch: short-circuit → curated passthrough; LLM-driven compose; or stub.
    if _shortcircuit:
        composed = _curated_passthrough(top_chains[0])
    else:
        composed = (
            _compose_llm(query, top_patterns, top_chains, top_workflows, entities, llm)
            if (llm and not _force_reactive)
            else None
        )
    if composed is None:
        composed = _compose_stub(top_patterns, top_chains)

    # Verify structure. For LLM output that fails, try one revision pass
    # with the verifier feedback injected into the prompt. Stub output is
    # not revised — it's already deterministic.
    report = _verifier.verify_chain(composed)
    if not report.ok and llm and composed.source == "llm":
        revised = _compose_llm(
            query, top_patterns, top_chains, top_workflows, entities, llm,
            verifier_feedback=report.to_llm_feedback(),
        )
        if revised is not None:
            re_report = _verifier.verify_chain(revised)
            # Accept the revision only if it improved on the prior error count.
            if len(re_report.errors) < len(report.errors):
                composed = revised
                composed.source = "llm_revised"
                report = re_report
    composed.verifier_report = report.to_dict()

    composed.confidence = conf.confidence
    composed.surfacing_mode = conf.mode
    composed.signals = {
        **{k: round(v, 3) for k, v in conf.contributions.items()},
        "normalized_chain_score": round(chain_score, 3),
        "normalized_pattern_score": round(pattern_score, 3),
        "query_specificity": round(signals.query_specificity, 3),
        "downstream_determinism": round(signals.downstream_determinism, 3),
        "pattern_chain_agreement": round(agreement, 3),
    }
    composed.patterns_used = [sp.pattern.name for sp in top_patterns]
    composed.exemplars_used = [sc.name for sc in top_chains]
    composed.entities = entities.to_dict()
    return composed


# Minimum normalized score for a curated chain to be confidently passed
# through by the stub. Below this the stub returns empty steps rather than
# pretending the top retrieval hit is right. Tunable via env.
def _curated_passthrough_threshold() -> float:
    try:
        return float(os.environ.get("BIOMATE_CURATED_PASSTHROUGH_MIN", "0.7"))
    except (TypeError, ValueError):
        return 0.7


def _curated_passthrough(chain: ScoredChain) -> ComposedChain:
    """Build a ComposedChain by pasting a curated chain through unchanged.

    Used by both the short-circuit path (high-confidence retrieval, no LLM
    needed) and the stub's dual-score branch.
    """
    steps: List[ChainStep] = []
    edges: List[ChainEdge] = []
    for i, step in enumerate(chain.steps):
        steps.append(
            ChainStep(
                order=step.get("order", i + 1),
                workflow_name=step.get("workflow_name", "?"),
                role=step.get("role", ""),
                rationale=f"from curated chain `{chain.name}`",
            )
        )
        if i > 0:
            edges.append(ChainEdge(from_step=i, to_step=i + 1))
    return ComposedChain(
        steps=steps,
        edges=edges,
        rationale=f"Curated chain `{chain.name}` matched the query "
                  f"(score {_normalize_chain_score(chain.score):.2f}).",
        source="curated_passthrough",
    )


def _compose_stub(
    top_patterns: List[ScoredPattern],
    top_chains: List[ScoredChain],
) -> ComposedChain:
    """Deterministic placeholder. Only passes through a curated chain when
    its normalized score is comfortably high (default ≥0.7). Otherwise emits
    an honest "no plan emitted" — better than fabricating relevance.
    """
    threshold = _curated_passthrough_threshold()
    if top_chains:
        normalized = _normalize_chain_score(top_chains[0].score)
        if normalized >= threshold and (
            not top_patterns or top_chains[0].score >= top_patterns[0].score
        ):
            return _curated_passthrough(top_chains[0])

    # No high-confidence curated match — be honest about it rather than guess.
    if top_chains and top_patterns:
        note = (
            f"Best curated match `{top_chains[0].name}` scored {_normalize_chain_score(top_chains[0].score):.2f} "
            f"(threshold {threshold:.2f}). Top pattern `{top_patterns[0].pattern.name}` "
            f"suggests the shape. LLM composition required to synthesize a specific chain."
        )
    elif top_patterns:
        note = (
            f"Top pattern: `{top_patterns[0].pattern.name}` (score {top_patterns[0].score:.2f}). "
            "No curated chain matched; LLM composition required."
        )
    else:
        note = "No relevant pattern or curated chain found for this query."
    return ComposedChain(
        steps=[],
        edges=[],
        rationale=note,
        source="stub",
    )


def _compose_llm(
    query: str,
    top_patterns: List[ScoredPattern],
    top_chains: List[ScoredChain],
    top_workflows: List[ScoredWorkflow],
    entities: QueryEntities,
    llm: Callable[[str], str],
    verifier_feedback: str = "",
) -> Optional[ComposedChain]:
    """Ask the LLM to emit a chain in the free-form schema."""
    prompt = _build_prompt(
        query, top_patterns, top_chains, top_workflows, entities, verifier_feedback,
    )
    _debug("LLM prompt: %d chars, %d patterns, %d chains, %d workflows%s",
           len(prompt), len(top_patterns), len(top_chains), len(top_workflows),
           " (revision)" if verifier_feedback else "")
    try:
        raw = llm(prompt)
    except Exception as exc:
        _debug("LLM call RAISED: %s: %s", type(exc).__name__, str(exc)[:200])
        return None
    _debug("LLM response: %d chars, starts: %r", len(raw or ""), (raw or "")[:80])
    parsed = _parse_llm_chain(raw)
    if parsed is None:
        _debug("LLM response did not parse to a valid chain — falling back. "
               "Raw response (first 400 chars): %r", (raw or "")[:400])
    elif not parsed.steps:
        _debug("LLM returned a chain with 0 steps — treating as no-op. "
               "Raw response (first 200): %r", (raw or "")[:200])
        # Empty step list is not useful — let the stub take over.
        return None
    return parsed


def _build_prompt(
    query: str,
    top_patterns: List[ScoredPattern],
    top_chains: List[ScoredChain],
    top_workflows: List[ScoredWorkflow],
    entities: QueryEntities,
    verifier_feedback: str = "",
) -> str:
    parts = [
        "You are composing a multi-step bioinformatics analysis chain for a user.",
        "",
        f"USER QUERY:\n{query}",
        "",
        "EXTRACTED ENTITIES (use these as canonical names where possible):",
        json.dumps(entities.to_dict(), indent=2),
        "",
        "RELEVANT PATTERNS (scaffolding — use the SHAPE if it fits, ignore if not):",
    ]
    for sp in top_patterns:
        p = sp.pattern
        parts.append(f"\n- {p.name} (score {sp.score:.2f})")
        parts.append(f"  When: {p.when}")
        parts.append(f"  Shape:\n{p.shape}")
        if p.instantiations:
            parts.append(f"  Real instantiations: {'; '.join(p.instantiations[:2])}")
        if p.pitfall:
            parts.append(f"  Pitfall to avoid: {p.pitfall}")

    parts.append("\nCURATED CHAIN EXEMPLARS (similar prior chains — use as style reference):")
    for sc in top_chains:
        parts.append(f"\n- {sc.name} [{sc.domain}] (score {sc.score:.2f})")
        parts.append(f"  Description: {sc.description}")
        step_names = [s.get("workflow_name", "?") for s in sc.steps]
        parts.append(f"  Steps: {' → '.join(step_names)}")

    # Collect every workflow name the LLM is allowed to reference. This is the
    # closed set: top-K BM25-retrieved candidates PLUS every step name from
    # the retrieved curated chains (those names are valid even when they
    # don't appear in the `workflows` table — the verifier treats them as
    # known).
    chain_step_names: Set[str] = set()
    for sc in top_chains:
        for s in sc.steps:
            wn = s.get("workflow_name") if isinstance(s, dict) else None
            if wn:
                chain_step_names.add(wn)

    parts.append("\nCANDIDATE WORKFLOWS (these are REAL workflow names from the catalog — use ONLY these or curated-chain step names above):")
    for w in top_workflows:
        desc = (w.description or "").replace("\n", " ")[:140]
        parts.append(f"- `{w.name}` [{w.domain}] — {desc}")
    if chain_step_names:
        extras = sorted(n for n in chain_step_names if not any(w.name == n for w in top_workflows))
        if extras:
            parts.append("  Curated-chain step names also valid: " + ", ".join(f"`{n}`" for n in extras))

    if verifier_feedback:
        parts.append("\nPRIOR ATTEMPT FAILED VERIFICATION — fix these issues:")
        parts.append(verifier_feedback)

    parts.append("""
TASK: Output a chain as JSON with this exact schema:
{
  "steps": [
    {"order": 1, "workflow_name": "<existing-workflow-name>", "role": "<short>", "rationale": "<one sentence>"},
    ...
  ],
  "edges": [
    {"from_step": 1, "to_step": 2, "via": "<what passes between, e.g. counts_matrix>"}
  ],
  "rationale": "<2-3 sentences justifying the overall plan, naming pattern(s) used>"
}

Constraints:
- workflow_name MUST be from the CANDIDATE WORKFLOWS list or the curated-chain step names above. Do NOT invent names — if no listed workflow fits a step, OMIT that step.
- Keep chains short (2-5 steps).
- Name pattern(s) you drew from in the rationale field.
- Output JSON ONLY — no surrounding prose.
""")
    return "\n".join(parts)


def _parse_llm_chain(raw: str) -> Optional[ComposedChain]:
    """Best-effort JSON extraction from LLM output."""
    raw = raw.strip()
    # If wrapped in code fences, peel them off.
    fence = re.match(r"^```(?:json)?\s*(.*?)\s*```$", raw, re.DOTALL)
    if fence:
        raw = fence.group(1)
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        return None
    if not isinstance(data, dict):
        return None
    steps = [
        ChainStep(
            order=int(s.get("order", i + 1)),
            workflow_name=str(s.get("workflow_name", "?")),
            role=str(s.get("role", "")),
            rationale=str(s.get("rationale", "")),
        )
        for i, s in enumerate(data.get("steps", []))
        if isinstance(s, dict)
    ]
    edges = [
        ChainEdge(
            from_step=int(e.get("from_step", 0)),
            to_step=int(e.get("to_step", 0)),
            via=str(e.get("via", "")),
        )
        for e in data.get("edges", [])
        if isinstance(e, dict)
    ]
    return ComposedChain(
        steps=steps,
        edges=edges,
        rationale=str(data.get("rationale", "")),
        source="llm",
    )
