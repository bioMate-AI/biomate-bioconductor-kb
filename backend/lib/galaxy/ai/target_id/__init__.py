"""Target identification — multi-agent, multi-channel, tabular-arbitered target nomination.

A first-class BioMate capability that fuses evidence channels (genetics, PPI, pathway/TF,
literature, and VC/FM-as-channel incl. CAPTAIN/scGPT and — once it PROVES contribution — our
immune-FM) into a ranked, confidence-tiered, provenance-backed target list. The learned
arbiter is TABULAR (GBDT/TabPFN) by default, not a deep net; every channel must earn its
place via the evidence gate (linear-advantage). See docs/20261020_INNOVATION_DEMONSTRATION_PROTOCOL.md.

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
from .types import ChannelResult, OrchestratorResult, TargetEvidence, TargetScore

__all__ = [
    "Arbiter", "EvidenceGateArbiter", "HarmonicSumArbiter", "TabularArbiter",
    "Channel", "MockChannel", "LLMReasonedChannel", "CallableChannel",
    "OpenTargetsGeneticsChannel", "TableChannel", "default_channels", "frozen_fm_channel",
    "StringPpiChannel", "PathwayCoMembershipChannel",
    "run_demonstration", "run_clinical_arm", "run_clinical_demonstration", "cyt_score",
    "TargetIDOrchestrator", "create_target_id_orchestrator",
    "ChannelResult", "OrchestratorResult", "TargetEvidence", "TargetScore",
]
