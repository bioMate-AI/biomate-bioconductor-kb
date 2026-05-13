"""
Built-in Auto-Fixers

Collection of production-ready fixers for common workflow issues.
"""

# Each fixer that depends on galaxy.model is guarded so the package loads
# outside the full Galaxy web process (standalone workers, tests, etc.).

from galaxy.ai.workflow_ops.autofix.fixers.container_error_fixer import ContainerErrorFixer

def _try_import(module_path, class_name):
    try:
        import importlib
        mod = importlib.import_module(module_path)
        return getattr(mod, class_name)
    except ImportError:
        return None

LLMFirstFixer = _try_import("galaxy.ai.workflow_ops.autofix.fixers.llm_first_fixer", "LLMFirstFixer")
NextflowParameterFixer = _try_import("galaxy.ai.workflow_ops.autofix.fixers.nextflow_parameter_fixer", "NextflowParameterFixer")
AWSResourceFixer = _try_import("galaxy.ai.workflow_ops.autofix.fixers.aws_resource_fixer", "AWSResourceFixer")
DataFileFixer = _try_import("galaxy.ai.workflow_ops.autofix.fixers.data_file_fixer", "DataFileFixer")
RetryStrategyFixer = _try_import("galaxy.ai.workflow_ops.autofix.fixers.retry_strategy_fixer", "RetryStrategyFixer")
ReferenceGenomeFixer = _try_import("galaxy.ai.workflow_ops.autofix.fixers.reference_genome_fixer", "ReferenceGenomeFixer")
FileFormatFixer = _try_import("galaxy.ai.workflow_ops.autofix.fixers.file_format_fixer", "FileFormatFixer")
SamplesheetFixer = _try_import("galaxy.ai.workflow_ops.autofix.fixers.samplesheet_fixer", "SamplesheetFixer")

# Tier 1 / Tier 2 fixers ported from galaxy/dev (Hybrid Strategy, 2026-05-09).
# Chain order: rule-based first, LLM-driven next, DeepAgentFixer last as the
# Tier 2 fallback when all rule fixers have missed.
CPUResourceFixer = _try_import("galaxy.ai.workflow_ops.autofix.fixers.cpu_resource_fixer", "CPUResourceFixer")
ParameterValidationFixer = _try_import("galaxy.ai.workflow_ops.autofix.fixers.parameter_validation_fixer", "ParameterValidationFixer")
DockerDaemonFixer = _try_import("galaxy.ai.workflow_ops.autofix.fixers.docker_daemon_fixer", "DockerDaemonFixer")
LLMUniversalFixer = _try_import("galaxy.ai.workflow_ops.autofix.fixers.llm_universal_fixer", "LLMUniversalFixer")
LLMLearningFixer = _try_import("galaxy.ai.workflow_ops.autofix.fixers.llm_learning_fixer", "LLMLearningFixer")
PureLLMAutoFixer = _try_import("galaxy.ai.workflow_ops.autofix.fixers.pure_llm_fixer", "PureLLMAutoFixer")
DeepAgentFixer = _try_import("galaxy.ai.workflow_ops.autofix.fixers.deep_agent_fixer", "DeepAgentFixer")

__all__ = [
    "LLMFirstFixer",
    "NextflowParameterFixer",
    "AWSResourceFixer",
    "DataFileFixer",
    "RetryStrategyFixer",
    "ContainerErrorFixer",
    "ReferenceGenomeFixer",
    "FileFormatFixer",
    "SamplesheetFixer",
    # Tier 1 / Tier 2 additions
    "CPUResourceFixer",
    "ParameterValidationFixer",
    "DockerDaemonFixer",
    "LLMUniversalFixer",
    "LLMLearningFixer",
    "PureLLMAutoFixer",
    "DeepAgentFixer",
]
