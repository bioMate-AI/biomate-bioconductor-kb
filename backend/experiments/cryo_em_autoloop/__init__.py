"""
CryoEM Auto-Loop: autonomous parameter tuning for CryoSPARC SPA workflows.

Inspired by: The AI Scientist (Nature 2026, Sakana AI)
  https://doi.org/10.1038/s41586-026-10265-5
  https://github.com/SakanaAI/AI-Scientist

Architecture: per-phase feedback loop
  run phase → evaluate QC gates → if HALT, tune params → retry (up to N times)
"""

from .orchestrator import CryoEMAutoLoop, LoopResult, MockPhaseRunner
from .params import CryoEMParams, PHASE_PARAM_OWNERS
from .qc_evaluator import CryoEMQCEvaluator, PhaseQCResult, QCAction
from .param_tuner import ParamTuner, Remediation
from .audit_logger import AuditLogger
from .metrics_extractor import MetricsExtractor

__all__ = [
    "CryoEMAutoLoop",
    "LoopResult",
    "MockPhaseRunner",
    "CryoEMParams",
    "PHASE_PARAM_OWNERS",
    "CryoEMQCEvaluator",
    "PhaseQCResult",
    "QCAction",
    "ParamTuner",
    "Remediation",
    "AuditLogger",
    "MetricsExtractor",
]
