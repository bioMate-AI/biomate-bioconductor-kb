"""Shared dataclasses for the chain composer.

Lives in its own module so composer + verifier can both import without
creating a cycle.
"""

from __future__ import annotations

from dataclasses import asdict, dataclass, field
from typing import Any, Dict, List, Literal


SurfacingMode = Literal["upfront", "stepwise", "reactive"]


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
    source: str = "stub"  # "stub" | "llm" | "curated_passthrough" | "llm_revised"
    entities: Dict[str, Any] = field(default_factory=dict)
    verifier_report: Dict[str, Any] = field(default_factory=dict)

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
            "entities": self.entities,
            "verifier_report": self.verifier_report,
        }
