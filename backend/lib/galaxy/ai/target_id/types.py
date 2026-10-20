"""Typed results for the target-identification orchestrator.

3.9-safe (typing.Optional/Dict/List; no PEP-604 unions). Pure stdlib — no galaxy/numpy
imports at module load, so these types can be used anywhere cheaply.
"""
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional


@dataclass
class ChannelResult:
    """One evidence channel's raw output: target/gene -> raw evidence score (higher = more).

    A channel must NOT z-score or rank — the arbiter does that so every channel is
    calibrated against its own null in one place. Channels fail soft: on error they
    return an empty ``scores`` with ``error`` set (never raise into the fan-out).
    """
    channel: str
    scores: Dict[str, float] = field(default_factory=dict)
    provenance: Dict[str, Any] = field(default_factory=dict)
    error: Optional[str] = None

    @property
    def ok(self) -> bool:
        return self.error is None and bool(self.scores)


@dataclass
class TargetEvidence:
    """Per-target evidence breakdown after calibration — auditable, never an opaque score."""
    target: str
    per_channel_z: Dict[str, float] = field(default_factory=dict)
    fired_channels: List[str] = field(default_factory=list)
    n_fired: int = 0
    tier: str = "none"            # "corroborated" (AND, >=2) | "nominated" (OR, >=1) | "none"
    max_z: float = 0.0
    mean_fired_z: float = 0.0


@dataclass
class TargetScore:
    target: str
    score: float
    tier: str
    rank: int
    evidence: TargetEvidence


@dataclass
class OrchestratorResult:
    query: str
    targets: List[TargetScore] = field(default_factory=list)
    channels_run: List[str] = field(default_factory=list)
    channel_errors: Dict[str, str] = field(default_factory=dict)
    arbiter: str = "evidence_gate"
    plan: Optional[Dict[str, Any]] = None

    def top(self, k: int = 20) -> List[TargetScore]:
        return self.targets[:k]

    def to_dict(self) -> Dict[str, Any]:
        return {
            "query": self.query,
            "arbiter": self.arbiter,
            "channels_run": self.channels_run,
            "channel_errors": self.channel_errors,
            "plan": self.plan,
            "targets": [
                {
                    "rank": t.rank, "target": t.target, "score": round(t.score, 4), "tier": t.tier,
                    "n_fired": t.evidence.n_fired, "fired_channels": t.evidence.fired_channels,
                    "per_channel_z": {k: round(v, 3) for k, v in t.evidence.per_channel_z.items()},
                }
                for t in self.targets
            ],
        }
