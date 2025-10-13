"""
Type definitions for the Galaxy AI Assistant module.
"""

from typing import Dict, List, Any, Optional, Union, NamedTuple
from enum import Enum
from dataclasses import dataclass
from datetime import datetime


class TaskType(Enum):
    """Types of research tasks that can be automated."""
    SEQUENCE_ANALYSIS = "sequence_analysis"
    GENOMICS = "genomics"
    PROTEOMICS = "proteomics"
    TRANSCRIPTOMICS = "transcriptomics"
    QUALITY_CONTROL = "quality_control"
    ASSEMBLY = "assembly"
    ANNOTATION = "annotation"
    COMPARATIVE_ANALYSIS = "comparative_analysis"
    VISUALIZATION = "visualization"
    STATISTICS = "statistics"
    DATA_PROCESSING = "data_processing"
    UNKNOWN = "unknown"


class IntentType(Enum):
    """Types of user intents."""
    ANALYZE = "analyze"
    COMPARE = "compare"
    VISUALIZE = "visualize"
    PROCESS = "process"
    CONVERT = "convert"
    FILTER = "filter"
    ANNOTATE = "annotate"
    ASSEMBLE = "assemble"
    ALIGN = "align"
    UNKNOWN = "unknown"


@dataclass
class DataType:
    """Represents a data type in Galaxy."""
    name: str
    extension: str
    description: Optional[str] = None
    compatible_tools: List[str] = None
    
    def __post_init__(self):
        if self.compatible_tools is None:
            self.compatible_tools = []


@dataclass
class Tool:
    """Represents a Galaxy tool."""
    id: str
    name: str
    version: str
    description: str
    inputs: List[Dict[str, Any]]
    outputs: List[Dict[str, Any]]
    requirements: List[str]
    edam_operations: List[str] = None
    edam_topics: List[str] = None
    citations: List[str] = None
    tool_type: Optional[str] = None  # "data_source", "data_source_async", "default", etc.

    def __post_init__(self):
        if self.edam_operations is None:
            self.edam_operations = []
        if self.edam_topics is None:
            self.edam_topics = []
        if self.citations is None:
            self.citations = []
        # Auto-detect tool type if not specified
        if self.tool_type is None:
            self.tool_type = self._detect_tool_type()

    def _detect_tool_type(self) -> str:
        """Auto-detect tool type based on tool_id."""
        if self.id.startswith('biomate_dm_'):
            return 'data_source'
        elif self.id.startswith('query_'):
            return 'data_source'
        elif self.id in ['ebi_sra_main', 'ucsc_table_direct', 'flymine', 'wormbase', 'biomart']:
            return 'data_source'
        else:
            return 'default'

    def requires_containerization(self) -> bool:
        """Check if this tool requires container installation."""
        return self.tool_type not in ['data_source', 'data_source_async', 'manage_data']


@dataclass
class Task:
    """Represents a decomposed research task."""
    id: str
    name: str
    description: str
    task_type: TaskType
    intent_type: IntentType
    input_data_types: List[DataType]
    output_data_types: List[DataType]
    estimated_duration: Optional[int] = None  # in minutes
    confidence: float = 0.0
    dependencies: List[str] = None
    
    def __post_init__(self):
        if self.dependencies is None:
            self.dependencies = []


@dataclass
class ToolRecommendation:
    """Represents a tool recommendation for a task."""
    tool: Tool
    confidence: float
    reasoning: str
    estimated_runtime: Optional[int] = None  # in minutes
    resource_requirements: Optional[Dict[str, Any]] = None


@dataclass
class WorkflowStep:
    """Represents a step in a Galaxy workflow."""
    step_id: int
    tool_id: str
    tool_version: str
    input_connections: Dict[str, Any]
    parameters: Dict[str, Any]
    annotation: Optional[str] = None
    position: Optional[Dict[str, int]] = None
    tool_type: Optional[str] = None  # Track tool type for execution optimization
    requires_container: bool = True  # Flag for container installation requirement


@dataclass
class WorkflowTemplate:
    """Represents a generated workflow template."""
    name: str
    description: str
    steps: List[WorkflowStep]
    inputs: List[Dict[str, Any]]
    outputs: List[Dict[str, Any]]
    tags: List[str] = None
    created_at: datetime = None
    
    def __post_init__(self):
        if self.tags is None:
            self.tags = []
        if self.created_at is None:
            self.created_at = datetime.now()


@dataclass
class UserRequest:
    """Represents a user's research request."""
    user_id: str
    request_text: str
    context: Optional[Dict[str, Any]] = None
    available_datasets: Optional[List[Dict[str, Any]]] = None
    preferred_tools: Optional[List[str]] = None
    constraints: Optional[Dict[str, Any]] = None
    timestamp: datetime = None
    
    def __post_init__(self):
        if self.timestamp is None:
            self.timestamp = datetime.now()


@dataclass
class AIResponse:
    """Represents the AI assistant's response to a user request."""
    request_id: str
    parsed_intent: IntentType
    decomposed_tasks: List[Task]
    tool_recommendations: List[ToolRecommendation]
    workflow_template: Optional[WorkflowTemplate]
    confidence: float
    execution_plan: Optional[str] = None
    warnings: List[str] = None
    
    def __post_init__(self):
        if self.warnings is None:
            self.warnings = []


class ToolMatch(NamedTuple):
    """Represents a tool match result."""
    tool: Tool
    score: float
    matching_criteria: List[str]


class TaskGraph:
    """Represents a dependency graph of tasks."""
    
    def __init__(self):
        self.nodes: Dict[str, Task] = {}
        self.edges: Dict[str, List[str]] = {}
    
    def add_task(self, task: Task):
        """Add a task to the graph."""
        self.nodes[task.id] = task
        if task.id not in self.edges:
            self.edges[task.id] = []
    
    def add_dependency(self, from_task_id: str, to_task_id: str):
        """Add a dependency between tasks."""
        if from_task_id not in self.edges:
            self.edges[from_task_id] = []
        self.edges[from_task_id].append(to_task_id)
    
    def get_execution_order(self) -> List[str]:
        """Get the topological order for task execution."""
        visited = set()
        temp_visited = set()
        result = []
        
        def dfs(node_id: str):
            if node_id in temp_visited:
                raise ValueError(f"Circular dependency detected involving task: {node_id}")
            if node_id in visited:
                return
            
            temp_visited.add(node_id)
            for neighbor in self.edges.get(node_id, []):
                dfs(neighbor)
            temp_visited.remove(node_id)
            visited.add(node_id)
            result.append(node_id)
        
        for node_id in self.nodes:
            if node_id not in visited:
                dfs(node_id)
        
        return list(reversed(result))