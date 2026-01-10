"""
Core module containing base classes and interfaces for the Galaxy Cloud Executor.
"""

from .executor import CloudExecutor
from .storage import CloudStorage, CloudPath
from .auth import CloudAuth
from .job import JobSpec, JobStatus, JobResult

__all__ = [
    "CloudExecutor",
    "CloudStorage", 
    "CloudPath",
    "CloudAuth",
    "JobSpec",
    "JobStatus", 
    "JobResult",
]