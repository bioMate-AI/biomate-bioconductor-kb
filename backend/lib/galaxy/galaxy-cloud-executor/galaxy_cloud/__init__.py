"""
Galaxy Cloud Executor

A multi-cloud executor module for Galaxy, inspired by Nextflow's cloud integration patterns.
Provides unified interfaces for executing computational tasks across AWS, Azure, Google Cloud, and Kubernetes.
"""

from .factory import CloudExecutorFactory
from .config import CloudConfig
from .core.job import JobSpec, JobStatus
from .registry import registry

# Import providers to trigger registration decorators
try:
    from .providers import aws
except ImportError:
    pass  # AWS provider not available

try:
    from .providers import azure
except ImportError:
    pass  # Azure provider not available

try:
    from .providers import gcp
except ImportError:
    pass  # GCP provider not available

try:
    from .providers import k8s
except ImportError:
    pass  # K8s provider not available

try:
    from ._version import version as __version__
except ImportError:
    __version__ = "unknown"

__all__ = [
    "__version__",
    "CloudExecutorFactory",
    "CloudConfig",
    "JobSpec",
    "JobStatus",
    "registry",
]