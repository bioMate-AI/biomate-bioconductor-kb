"""
AWS provider implementation for Galaxy Cloud Executor.
Inspired by Nextflow's nf-amazon plugin.
"""

from .executor import AWSBatchExecutor
from .storage import S3Storage
from .auth import AWSAuth

__all__ = [
    "AWSBatchExecutor",
    "S3Storage", 
    "AWSAuth",
]