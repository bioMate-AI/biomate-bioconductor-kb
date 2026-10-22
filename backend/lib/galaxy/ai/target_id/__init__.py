"""Target identification — multi-agent, multi-channel, tabular-arbitered target nomination.

A first-class BioMate capability: a ranked, confidence-tiered, PROVENANCE-backed target list from
multiple evidence channels (genetics, PPI, pathway/TF, literature, VC/FM-as-channel).

HONEST DEFAULT (benchmark_multidisease.py, 17 diseases): the multi-channel FUSION does NOT beat the
single strongest channel (OpenTargets) — expansion dilutes, corroboration ties. So the default arbiter
ranks BY OpenTargets and uses the other channels as CORROBORATION / conflict flags / provenance, never a
silent fusion that ranks worse than OT. The value this module adds is surfacing OpenTargets well + showing
cross-source agreement + wiring the result into BioMate's workflow execution — NOT a claim to out-rank OT.
Every non-primary channel must still EARN a ranking role (none has on the benchmark). The learned TABULAR
arbiter (GBDT/TabPFN) remains available for when a channel set demonstrably earns lift. See
docs/20261021_TARGETID_FUSION_VS_OPENTARGETS_BENCHMARK.md and docs/20261020_INNOVATION_DEMONSTRATION_PROTOCOL.md.

Design map (audited primitives reused): parallel fan-out via galaxy.ai.map_reduce (ThreadPool
fallback), LLM via galaxy.ai.llm_client.LLMClient, workflows via UnifiedWorkflowSearch.
"""
from .arbiter import Arbiter, EvidenceGateArbiter, HarmonicSumArbiter, TabularArbiter
from .channels import CallableChannel, Channel, LLMReasonedChannel, MockChannel
from .data_channels import OpenTargetsGeneticsChannel, TableChannel, default_channels, frozen_fm_channel
from .clinical_arm import cyt_score, run_clinical_demonstration
from .demonstration import run_clinical_arm, run_demonstration
from .network_channels import PathwayCoMembershipChannel, StringPpiChannel
from .orchestrator import TargetIDOrchestrator, create_target_id_orchestrator
from .validation import nominate_and_validate, validation_plan, VALIDATION_INTENTS
from .types import ChannelResult, OrchestratorResult, TargetEvidence, TargetScore

__all__ = [
    "Arbiter", "EvidenceGateArbiter", "HarmonicSumArbiter", "TabularArbiter",
    "Channel", "MockChannel", "LLMReasonedChannel", "CallableChannel",
    "OpenTargetsGeneticsChannel", "TableChannel", "default_channels", "frozen_fm_channel",
    "StringPpiChannel", "PathwayCoMembershipChannel",
    "run_demonstration", "run_clinical_arm", "run_clinical_demonstration", "cyt_score",
    "TargetIDOrchestrator", "create_target_id_orchestrator",
    "nominate_and_validate", "validation_plan", "VALIDATION_INTENTS",
    "ChannelResult", "OrchestratorResult", "TargetEvidence", "TargetScore",
]
