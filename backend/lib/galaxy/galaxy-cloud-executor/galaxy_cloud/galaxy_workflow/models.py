"""
Galaxy Workflow Models

Data models for representing Galaxy workflows in the cloud execution context.
"""

from dataclasses import dataclass, field
from typing import Dict, List, Optional, Any
from enum import Enum

from galaxy_cloud.core.job import JobSpec


class StepType(str, Enum):
    """Workflow step types"""
    INPUT = "input"
    COLLECTION_INPUT = "collection_input"
    TOOL = "tool"
    SUBWORKFLOW = "subworkflow"
    PAUSE = "pause"
    UNKNOWN = "unknown"


class StepStatus(str, Enum):
    """Workflow step execution status"""
    PENDING = "pending"
    QUEUED = "queued"
    RUNNING = "running"
    COMPLETED = "completed"
    FAILED = "failed"
    CANCELLED = "cancelled"
    SKIPPED = "skipped"


@dataclass
class StepDependency:
    """Represents a dependency between workflow steps"""
    from_step: str
    to_step: str
    from_output: str
    to_input: str


@dataclass
class WorkflowStep:
    """Represents a single step in a Galaxy workflow"""
    step_id: str
    name: str
    step_type: StepType
    tool_id: Optional[str] = None
    job_spec: Optional[JobSpec] = None
    inputs: Dict[str, Dict] = field(default_factory=dict)
    outputs: Dict[str, Dict] = field(default_factory=dict)
    annotation: str = ""
    status: StepStatus = StepStatus.PENDING
    subworkflow_id: Optional[str] = None
    when_expression: Optional[str] = None


@dataclass
class WorkflowDAG:
    """Represents a Galaxy workflow as a Directed Acyclic Graph"""
    workflow_id: str
    name: str
    steps: Dict[str, WorkflowStep]
    dependencies: List[StepDependency]
    inputs: Dict[str, Dict] = field(default_factory=dict)
    outputs: Dict[str, Dict] = field(default_factory=dict)
    annotation: str = ""


@dataclass
class DatasetInfo:
    """Information about a Galaxy dataset"""
    dataset_id: str
    history_id: str
    name: str
    file_ext: str
    file_size: Optional[int] = None
    file_path: Optional[str] = None
    metadata: Dict[str, Any] = field(default_factory=dict)


@dataclass
class CollectionInfo:
    """Information about a Galaxy dataset collection"""
    collection_id: str
    history_id: str
    name: str
    collection_type: str
    elements: List[DatasetInfo] = field(default_factory=list)


@dataclass
class WorkflowInput:
    """Workflow input specification"""
    input_id: str
    label: str
    type: str  # 'dataset', 'collection', 'parameter'
    value: Optional[Any] = None
    dataset_info: Optional[DatasetInfo] = None
    collection_info: Optional[CollectionInfo] = None


@dataclass
class WorkflowOutput:
    """Workflow output specification"""
    output_id: str
    step_id: str
    output_name: str
    label: str
    dataset_info: Optional[DatasetInfo] = None
    collection_info: Optional[CollectionInfo] = None


@dataclass
class WorkflowExecution:
    """Represents a workflow execution instance"""
    execution_id: str
    workflow_dag: WorkflowDAG
    inputs: List[WorkflowInput]
    outputs: List[WorkflowOutput] = field(default_factory=list)
    step_executions: Dict[str, "StepExecution"] = field(default_factory=dict)
    status: StepStatus = StepStatus.PENDING
    start_time: Optional[str] = None
    end_time: Optional[str] = None
    error_message: Optional[str] = None


@dataclass
class StepExecution:
    """Represents the execution of a single workflow step"""
    step_id: str
    job_id: Optional[str] = None
    cloud_job_id: Optional[str] = None
    status: StepStatus = StepStatus.PENDING
    start_time: Optional[str] = None
    end_time: Optional[str] = None
    error_message: Optional[str] = None
    stdout: Optional[str] = None
    stderr: Optional[str] = None
    exit_code: Optional[int] = None
    resource_usage: Dict[str, Any] = field(default_factory=dict)


@dataclass
class CloudDatasetMapping:
    """Mapping between Galaxy datasets and cloud storage locations"""
    dataset_id: str
    galaxy_path: str
    cloud_uri: str
    cloud_provider: str
    staged: bool = False
    retrieved: bool = False
    checksum: Optional[str] = None


@dataclass
class ToolContainerInfo:
    """Information about a tool's container"""
    tool_id: str
    image: str
    tag: str = "latest"
    registry: str = "quay.io/biocontainers"
    command: Optional[List[str]] = None
    env: Dict[str, str] = field(default_factory=dict)
    working_dir: str = "/galaxy-central"
    resources: Dict[str, Any] = field(default_factory=dict)


@dataclass
class WorkflowRunConfig:
    """Configuration for a workflow run"""
    cloud_provider: str
    namespace: Optional[str] = None
    storage_bucket: str = ""
    staging_area: str = ""
    output_area: str = ""
    retain_intermediate: bool = False
    max_parallel_jobs: int = 10
    job_timeout: int = 3600
    retry_attempts: int = 2
    priority_class: Optional[str] = None
    node_selector: Dict[str, str] = field(default_factory=dict)
    tolerations: List[Dict] = field(default_factory=list)
    annotations: Dict[str, str] = field(default_factory=dict)
    labels: Dict[str, str] = field(default_factory=dict)