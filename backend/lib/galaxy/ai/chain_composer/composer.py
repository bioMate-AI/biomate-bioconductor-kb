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
from typing import Any, Callable, Dict, List, Optional

from .confidence import (
    ConfidenceResult,
    ConfidenceSignals,
    SurfacingMode,
    score_confidence,
)
from .pattern_loader import Pattern, load_patterns
from .retrieval import (
    ScoredChain,
    ScoredPattern,
    retrieve_curated_chains,
    retrieve_patterns,
)


@dataclass
class ChainStep:
    order: int
    workflow_name: str
    role: str = ""
    rationale: str = ""


@dataclass
class ChainEdge:
    from_step: int
    to_step: int
    via: str = ""


@dataclass
class ComposedChain:
    steps: List[ChainStep] = field(default_factory=list)
    edges: List[ChainEdge] = field(default_factory=list)
    rationale: str = ""
    patterns_used: List[str] = field(default_factory=list)
    exemplars_used: List[str] = field(default_factory=list)
    confidence: float = 0.0
    surfacing_mode: SurfacingMode = "reactive"
    signals: Dict[str, float] = field(default_factory=dict)
    source: str = "stub"  # "stub" | "llm" | "curated_passthrough"

    def to_dict(self) -> Dict[str, Any]:
        return {
            "steps": [asdict(s) for s in self.steps],
            "edges": [asdict(e) for e in self.edges],
            "rationale": self.rationale,
            "patterns_used": self.patterns_used,
            "exemplars_used": self.exemplars_used,
            "confidence": self.confidence,
            "surfacing_mode": self.surfacing_mode,
            "signals": self.signals,
            "source": self.source,
        }


# Cheap query-specificity heuristic. Real systems would use NER + domain
# lexicons. For the prototype: count "specificity tokens" — organism names,
# modality names, contrast keywords, technology names, etc.
_SPECIFICITY_TERMS = {
    "human", "mouse", "rat", "yeast", "zebrafish", "drosophila", "fly",
    "hg38", "grch38", "grch37", "hg19", "mm10", "mm9",
    "rna-seq", "atac-seq", "scrna", "scrnaseq", "chip-seq", "wgs", "wes",
    "single-cell", "bulk", "spatial",
    "tumor", "normal", "control", "treatment", "ko", "wildtype", "knockout",
    "fastq", "bam", "vcf", "h5ad", "mtx",
    "deseq2", "edger", "limma", "seurat", "scanpy", "harmony", "mofa",
    # drug discovery / pharma
    "admet", "smiles", "pdb", "docking", "ic50", "ec50", "kd",
    "pbpk", "pharmacokinetics", "compound", "library",
    "gromacs", "mm-gbsa", "free-energy",
    # clinical / cohort
    "ukbiobank", "tcga", "gtex", "icgc", "finngen", "biobank",
    "case-control", "longitudinal",
}


def _query_specificity(query: str) -> float:
    q = query.lower()
    hits = sum(1 for t in _SPECIFICITY_TERMS if t in q)
    return min(1.0, hits / 4.0)  # 4+ specificity terms → maxed out


# Bound the curated_chain_score normalization to a reasonable range. The
# retrieval scores are unbounded jaccard-ish values (typically 0.5–3.0 for
# good hits); we map ≥1.5 to ~1.0.
def _normalize_chain_score(raw: float) -> float:
    return min(1.0, raw / 1.5)


def _normalize_pattern_score(raw: float) -> float:
    return min(1.0, raw / 2.0)


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


def compose_chain(
    query: str,
    *,
    user_profile_bias: float = 0.0,
    llm: Optional[Callable[[str], str]] = None,
    patterns: Optional[List[Pattern]] = None,
    top_k_patterns: int = 3,
    top_k_chains: int = 3,
) -> ComposedChain:
    """Compose a candidate chain for a user query.

    Args:
        query: free-text user query.
        user_profile_bias: -0.2..+0.2 hint from memory (beginner → negative,
            PI/experienced → positive). Default 0.
        llm: optional callable that takes a prompt and returns a JSON string
            with shape `{steps: [...], edges: [...], rationale: ""}`. If None,
            the composer uses the deterministic stub.
        patterns: override the loaded pattern library (for tests).
        top_k_patterns: how many patterns to retrieve.
        top_k_chains: how many curated chains to retrieve as exemplars.
    """
    patterns = patterns if patterns is not None else load_patterns()
    top_patterns = retrieve_patterns(query, patterns=patterns, top_k=top_k_patterns)
    top_chains = retrieve_curated_chains(query, top_k=top_k_chains)

    # Compute signals up-front so the stub and LLM paths share them.
    chain_score = _normalize_chain_score(top_chains[0].score) if top_chains else 0.0
    pattern_score = _normalize_pattern_score(top_patterns[0].score) if top_patterns else 0.0
    signals = ConfidenceSignals(
        curated_chain_score=chain_score,
        pattern_match_score=pattern_score,
        query_specificity=_query_specificity(query),
        downstream_determinism=_downstream_determinism(top_patterns),
        user_signal=_user_signal(query),
        user_profile_bias=user_profile_bias,
    )
    conf = score_confidence(signals)

    # Branch: LLM-driven compose vs deterministic stub.
    composed = _compose_llm(query, top_patterns, top_chains, llm) if llm else None
    if composed is None:
        composed = _compose_stub(top_patterns, top_chains)

    composed.confidence = conf.confidence
    composed.surfacing_mode = conf.mode
    composed.signals = {
        **{k: round(v, 3) for k, v in conf.contributions.items()},
        "normalized_chain_score": round(chain_score, 3),
        "normalized_pattern_score": round(pattern_score, 3),
        "query_specificity": round(signals.query_specificity, 3),
        "downstream_determinism": round(signals.downstream_determinism, 3),
    }
    composed.patterns_used = [sp.pattern.name for sp in top_patterns]
    composed.exemplars_used = [sc.name for sc in top_chains]
    return composed


def _compose_stub(
    top_patterns: List[ScoredPattern],
    top_chains: List[ScoredChain],
) -> ComposedChain:
    """Deterministic placeholder: when a curated chain is the clear winner,
    pass it through; otherwise emit a one-step "needs LLM" placeholder.
    """
    if top_chains and (not top_patterns or top_chains[0].score >= top_patterns[0].score):
        # Curated chain passthrough.
        chain = top_chains[0]
        steps = []
        edges = []
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
            rationale=f"Curated chain `{chain.name}` matched the query.",
            source="curated_passthrough",
        )

    # No clear curated match — emit a stub flagging that LLM composition is
    # required. The prototype intentionally stops here rather than hallucinate.
    pattern_note = (
        f"Top pattern: `{top_patterns[0].pattern.name}` "
        f"(score {top_patterns[0].score:.2f}). "
        "LLM not configured — composer cannot synthesize without it."
        if top_patterns
        else "No relevant pattern or curated chain found."
    )
    return ComposedChain(
        steps=[],
        edges=[],
        rationale=pattern_note,
        source="stub",
    )


def _compose_llm(
    query: str,
    top_patterns: List[ScoredPattern],
    top_chains: List[ScoredChain],
    llm: Callable[[str], str],
) -> Optional[ComposedChain]:
    """Ask the LLM to emit a chain in the free-form schema.

    The LLM is shown: query, top patterns (as scaffolding), top curated
    chains (as exemplars), and is asked to return JSON. We parse and
    fall back to None if parsing fails — caller treats as stub then.
    """
    prompt = _build_prompt(query, top_patterns, top_chains)
    try:
        raw = llm(prompt)
        return _parse_llm_chain(raw)
    except Exception:
        return None


def _build_prompt(
    query: str,
    top_patterns: List[ScoredPattern],
    top_chains: List[ScoredChain],
) -> str:
    parts = [
        "You are composing a multi-step bioinformatics analysis chain for a user.",
        "",
        f"USER QUERY:\n{query}",
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
- Use only workflow names that actually exist in the BioMate catalog.
- Keep chains short (2-5 steps). If you can't ground a step in a real workflow, omit it.
- Name patterns you drew from in the rationale.
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
