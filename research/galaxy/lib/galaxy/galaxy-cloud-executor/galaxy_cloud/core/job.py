"""
Job models and status definitions.
"""

from enum import Enum
from typing import Dict, Any, Optional, List
from pathlib import Path
from pydantic import BaseModel, Field, field_validator
from datetime import datetime


class JobStatus(str, Enum):
    """Job status enumeration."""
    PENDING = "pending"
    QUEUED = "queued"
    RUNNING = "running"
    COMPLETED = "completed"
    FAILED = "failed"
    CANCELLED = "cancelled"
    UNKNOWN = "unknown"


class ResourceSpec(BaseModel):
    """Resource specification for a job."""
    cpus: int = Field(default=1, ge=1, description="Number of CPU cores")
    memory_mb: int = Field(default=1024, ge=1, description="Memory in MB")
    disk_gb: Optional[int] = Field(default=None, ge=1, description="Disk space in GB")
    gpu: Optional[int] = Field(default=None, ge=0, description="Number of GPUs")
    gpu_type: Optional[str] = Field(default=None, description="GPU type (e.g., nvidia.com/gpu)")
    
    class Config:
        extra = "forbid"


class ContainerSpec(BaseModel):
    """Container specification for a job."""
    image: str = Field(description="Container image URI")
    command: Optional[List[str]] = Field(default=None, description="Container command")
    args: Optional[List[str]] = Field(default=None, description="Container arguments")
    env: Dict[str, str] = Field(default_factory=dict, description="Environment variables")
    working_dir: Optional[str] = Field(default=None, description="Working directory")
    privileged: bool = Field(default=False, description="Run container in privileged mode")
    
    class Config:
        extra = "forbid"


class JobSpec(BaseModel):
    """Complete job specification."""
    job_id: str = Field(description="Unique job identifier")
    name: str = Field(description="Human-readable job name")
    
    # Container and resources
    container: ContainerSpec = Field(description="Container specification")
    resources: ResourceSpec = Field(default_factory=ResourceSpec, description="Resource requirements")
    
    # File mappings
    input_files: Dict[str, str] = Field(default_factory=dict, description="Input file mappings (local -> remote)")
    output_files: Dict[str, str] = Field(default_factory=dict, description="Output file mappings (remote -> local)")
    
    # Execution parameters
    timeout_seconds: Optional[int] = Field(default=None, description="Job timeout in seconds (must be >= 1 if provided)")
    retry_attempts: int = Field(default=0, ge=0, description="Number of retry attempts")
    priority: int = Field(default=0, description="Job priority (higher = more priority)")
    
    # Cloud-specific options
    cloud_options: Dict[str, Any] = Field(default_factory=dict, description="Cloud provider specific options")
    
    # Metadata
    labels: Dict[str, str] = Field(default_factory=dict, description="Job labels/tags")
    annotations: Dict[str, str] = Field(default_factory=dict, description="Job annotations")

    @field_validator('timeout_seconds')
    @classmethod
    def validate_timeout(cls, v):
        """Validate timeout_seconds is >= 1 if provided"""
        if v is not None and v < 1:
            raise ValueError('timeout_seconds must be >= 1')
        return v

    class Config:
        extra = "forbid"


class JobResult(BaseModel):
    """Job execution result."""
    job_id: str = Field(description="Job identifier")
    cloud_job_id: Optional[str] = Field(default=None, description="Cloud provider job ID")
    status: JobStatus = Field(description="Final job status")
    
    # Timing information
    submitted_at: Optional[datetime] = Field(default=None, description="Job submission time")
    started_at: Optional[datetime] = Field(default=None, description="Job start time")
    finished_at: Optional[datetime] = Field(default=None, description="Job completion time")
    
    # Execution details
    exit_code: Optional[int] = Field(default=None, description="Process exit code")
    stdout: Optional[str] = Field(default=None, description="Standard output")
    stderr: Optional[str] = Field(default=None, description="Standard error")
    
    # Resource usage
    cpu_usage: Optional[float] = Field(default=None, description="CPU usage (core-hours)")
    memory_usage_mb: Optional[float] = Field(default=None, description="Peak memory usage in MB")
    
    # Error information
    error_message: Optional[str] = Field(default=None, description="Error message if failed")
    error_details: Dict[str, Any] = Field(default_factory=dict, description="Detailed error information")
    
    # Cloud-specific data
    cloud_metadata: Dict[str, Any] = Field(default_factory=dict, description="Cloud provider metadata")
    
    class Config:
        extra = "forbid"


class JobEvent(BaseModel):
    """Job event for monitoring and logging."""
    job_id: str = Field(description="Job identifier")
    timestamp: datetime = Field(default_factory=datetime.utcnow, description="Event timestamp")
    event_type: str = Field(description="Event type (e.g., 'status_change', 'log', 'error')")
    message: str = Field(description="Event message")
    details: Dict[str, Any] = Field(default_factory=dict, description="Additional event details")
    
    class Config:
        extra = "forbid"