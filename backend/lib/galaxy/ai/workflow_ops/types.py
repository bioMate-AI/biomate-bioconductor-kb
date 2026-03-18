"""
Data types for Workflow AI Operations
"""

from typing import List, Dict, Optional, Any, Literal
from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum


class IssueSeverity(str, Enum):
    """问题严重级别"""
    INFO = "info"
    WARNING = "warning"
    ERROR = "error"
    CRITICAL = "critical"


class IssueType(str, Enum):
    """问题类型"""
    DATA_FORMAT = "data_format"
    MISSING_PARAM = "missing_param"
    INVALID_PARAM = "invalid_param"
    RESOURCE_LIMIT = "resource_limit"
    NETWORK_ERROR = "network_error"
    DEPENDENCY_MISSING = "dependency_missing"
    PERMISSION_ERROR = "permission_error"
    UNKNOWN = "unknown"


class WorkflowStatus(str, Enum):
    """Workflow状态"""
    RUNNING = "running"
    WARNING = "warning"
    ERROR = "error"
    COMPLETED = "completed"
    FAILED = "failed"


class FixType(str, Enum):
    """修复类型"""
    CONFIG_ADJUSTMENT = "config_adjustment"
    DATA_CONVERSION = "data_conversion"
    RESOURCE_SCALING = "resource_scaling"
    SIMPLE_RETRY = "simple_retry"
    MANUAL_INTERVENTION = "manual_intervention"


class ActionType(str, Enum):
    """修复动作类型"""
    UPDATE_PARAM = "update_param"
    CONVERT_DATA = "convert_data"
    INCREASE_MEMORY = "increase_memory"
    INCREASE_DISK = "increase_disk"
    RETRY_TASK = "retry_task"
    SKIP_STEP = "skip_step"
    DIAGNOSTIC = "diagnostic"  # For diagnostic/informational actions


@dataclass
class Issue:
    """检测到的问题"""
    severity: IssueSeverity
    type: IssueType
    message: str
    suggestion: str
    auto_fixable: bool
    step_id: Optional[int] = None
    task_name: Optional[str] = None
    confidence: float = 1.0
    detected_at: datetime = field(default_factory=datetime.now)
    raw_logs: List[str] = field(default_factory=list)

    def to_dict(self) -> Dict[str, Any]:
        return {
            'severity': self.severity.value,
            'type': self.type.value,
            'message': self.message,
            'suggestion': self.suggestion,
            'auto_fixable': self.auto_fixable,
            'step_id': self.step_id,
            'task_name': self.task_name,
            'confidence': self.confidence,
            'detected_at': self.detected_at.isoformat(),
        }


@dataclass
class ProgressInfo:
    """执行进度信息"""
    current: int
    total: int
    percentage: float
    completed_tasks: int = 0
    failed_tasks: int = 0
    running_tasks: int = 0
    cached_tasks: int = 0

    def to_dict(self) -> Dict[str, Any]:
        return {
            'current': self.current,
            'total': self.total,
            'percentage': self.percentage,
            'completed_tasks': self.completed_tasks,
            'failed_tasks': self.failed_tasks,
            'running_tasks': self.running_tasks,
            'cached_tasks': self.cached_tasks,
        }


@dataclass
class LogAnalysisResult:
    """日志分析结果"""
    status: WorkflowStatus
    progress: ProgressInfo
    issues: List[Issue]
    insights: str  # LLM对当前状态的自然语言理解
    timestamp: datetime = field(default_factory=datetime.now)
    analysis_duration: float = 0.0  # 分析耗时（秒）
    llm_cost: float = 0.0  # LLM调用成本（美元）

    def to_dict(self) -> Dict[str, Any]:
        return {
            'status': self.status.value,
            'progress': self.progress.to_dict(),
            'issues': [issue.to_dict() for issue in self.issues],
            'insights': self.insights,
            'timestamp': self.timestamp.isoformat(),
            'analysis_duration': self.analysis_duration,
            'llm_cost': self.llm_cost,
        }


@dataclass
class FixAction:
    """具体的修复动作"""
    action: ActionType
    params: Dict[str, Any]
    description: str
    risk_level: Literal['low', 'medium', 'high'] = 'low'

    def to_dict(self) -> Dict[str, Any]:
        return {
            'action': self.action.value,
            'params': self.params,
            'description': self.description,
            'risk_level': self.risk_level,
        }


@dataclass
class FixPlan:
    """修复方案"""
    fixable: bool
    fix_type: FixType
    fix_actions: List[FixAction]
    explanation: str
    confidence: float
    estimated_success_rate: float = 0.0
    risk_level: str = 'low'  # 'low', 'medium', 'high'
    requires_user_confirmation: bool = False
    estimated_cost: float = 0.0  # 修复的成本估算（美元）
    created_at: datetime = field(default_factory=datetime.now)

    def to_dict(self) -> Dict[str, Any]:
        return {
            'fixable': self.fixable,
            'fix_type': self.fix_type.value,
            'fix_actions': [action.to_dict() for action in self.fix_actions],
            'explanation': self.explanation,
            'confidence': self.confidence,
            'estimated_success_rate': self.estimated_success_rate,
            'requires_user_confirmation': self.requires_user_confirmation,
            'created_at': self.created_at.isoformat(),
        }


@dataclass
class QueryResponse:
    """查询响应"""
    answer: str
    sources: List[str]  # 引用的日志/配置片段
    confidence: float
    follow_up_questions: List[str] = field(default_factory=list)
    timestamp: datetime = field(default_factory=datetime.now)

    def to_dict(self) -> Dict[str, Any]:
        return {
            'answer': self.answer,
            'sources': self.sources,
            'confidence': self.confidence,
            'follow_up_questions': self.follow_up_questions,
            'timestamp': self.timestamp.isoformat(),
        }


@dataclass
class LLMUsageStats:
    """LLM使用统计"""
    model: str
    input_tokens: int
    output_tokens: int
    cost: float
    duration: float  # 秒
    timestamp: datetime = field(default_factory=datetime.now)

    def to_dict(self) -> Dict[str, Any]:
        return {
            'model': self.model,
            'input_tokens': self.input_tokens,
            'output_tokens': self.output_tokens,
            'cost': self.cost,
            'duration': self.duration,
            'timestamp': self.timestamp.isoformat(),
        }
