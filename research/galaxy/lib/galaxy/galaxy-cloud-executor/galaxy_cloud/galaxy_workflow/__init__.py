"""
Galaxy Workflow Cloud Execution Module

This module provides Galaxy-specific components for executing workflows on cloud platforms.
It bridges Galaxy's workflow model with the cloud executor framework.
"""

from .converter import GalaxyWorkflowConverter
from .tool_registry import GalaxyToolRegistry
from .dag_executor import WorkflowDAGExecutor
from .data_manager import GalaxyDataManager
from .integration import GalaxyCloudIntegration
from .job_config_parser import GalaxyJobConfigParser

# GalaxyCloudJobRunner requires Galaxy core modules - only import if available
try:
    from .galaxy_job_runner import GalaxyCloudJobRunner
    _GALAXY_JOB_RUNNER_AVAILABLE = True
except ImportError:
    _GALAXY_JOB_RUNNER_AVAILABLE = False
    GalaxyCloudJobRunner = None

__all__ = [
    "GalaxyWorkflowConverter",
    "GalaxyToolRegistry",
    "WorkflowDAGExecutor",
    "GalaxyDataManager",
    "GalaxyCloudIntegration",
    "GalaxyJobConfigParser",
]

if _GALAXY_JOB_RUNNER_AVAILABLE:
    __all__.append("GalaxyCloudJobRunner")

__version__ = "0.1.0"