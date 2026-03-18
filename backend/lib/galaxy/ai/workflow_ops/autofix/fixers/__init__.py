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
]
