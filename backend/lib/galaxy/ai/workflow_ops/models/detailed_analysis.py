"""
详细分析结果模型

工业级 AI 运维分析结果数据结构
"""

from dataclasses import dataclass, field, asdict
from typing import List, Dict, Optional, Any
from datetime import datetime
from enum import Enum


class Severity(str, Enum):
    """严重程度"""
    CRITICAL = "critical"
    HIGH = "high"
    MEDIUM = "medium"
    LOW = "low"
    INFO = "info"


class StepStatus(str, Enum):
    """步骤状态"""
    PENDING = "pending"
    RUNNING = "running"
    COMPLETED = "completed"
    FAILED = "failed"
    SKIPPED = "skipped"


class HealthStatus(str, Enum):
    """整体健康状态"""
    HEALTHY = "healthy"
    DEGRADED = "degraded"
    UNHEALTHY = "unhealthy"
    CRITICAL = "critical"


@dataclass
class Finding:
    """单个发现项"""
    type: str
    severity: Severity
    location: str
    evidence: str
    confidence: float = 0.0

    def to_dict(self) -> Dict:
        return {
            'type': self.type,
            'severity': self.severity.value,
            'location': self.location,
            'evidence': self.evidence,
            'confidence': self.confidence
        }


@dataclass
class AnalysisStep:
    """分析步骤"""
    step: int
    name: str
    status: StepStatus
    duration_ms: int = 0
    details: str = ""
    findings: List[Finding] = field(default_factory=list)
    llm_calls: int = 0
    tokens_used: int = 0
    error: Optional[str] = None

    def to_dict(self) -> Dict:
        return {
            'step': self.step,
            'name': self.name,
            'status': self.status.value,
            'duration_ms': self.duration_ms,
            'details': self.details,
            'findings': [f.to_dict() for f in self.findings],
            'llm_calls': self.llm_calls,
            'tokens_used': self.tokens_used,
            'error': self.error
        }


@dataclass
class RootCause:
    """根本原因"""
    id: str
    type: str
    severity: Severity
    component: str
    description: str
    confidence: float
    evidence: List[str]
    affected_tasks: List[str] = field(default_factory=list)
    first_occurrence: Optional[str] = None
    occurrence_count: int = 1

    def to_dict(self) -> Dict:
        return {
            'id': self.id,
            'type': self.type,
            'severity': self.severity.value,
            'component': self.component,
            'description': self.description,
            'confidence': self.confidence,
            'evidence': self.evidence,
            'affected_tasks': self.affected_tasks,
            'first_occurrence': self.first_occurrence,
            'occurrence_count': self.occurrence_count
        }


@dataclass
class Metrics:
    """性能指标"""
    total_tasks: int = 0
    failed_tasks: int = 0
    success_rate: float = 0.0
    avg_task_duration_sec: float = 0.0
    total_cost_usd: float = 0.0
    llm_calls: int = 0
    llm_cost_usd: float = 0.0
    analysis_duration_sec: float = 0.0

    def to_dict(self) -> Dict:
        return asdict(self)


@dataclass
class ResourceUsage:
    """资源使用情况"""
    peak_memory_gb: float = 0.0
    avg_cpu_percent: float = 0.0
    disk_usage_gb: float = 0.0
    network_io_gb: float = 0.0
    aws_batch_hours: float = 0.0

    def to_dict(self) -> Dict:
        return asdict(self)


@dataclass
class TimelineEvent:
    """时间线事件"""
    timestamp: str
    event: str
    status: str  # "info", "warning", "error", "success"
    details: Optional[Dict[str, Any]] = None

    def to_dict(self) -> Dict:
        return asdict(self)


@dataclass
class ConfigChange:
    """配置更改"""
    line: Optional[int] = None
    old: Optional[str] = None
    new: str = ""
    description: str = ""

    def to_dict(self) -> Dict:
        return asdict(self)


@dataclass
class Action:
    """推荐操作"""
    type: str  # "config_change", "retry", "scale", "manual"
    file: Optional[str] = None
    changes: List[ConfigChange] = field(default_factory=list)
    command: Optional[str] = None

    def to_dict(self) -> Dict:
        return {
            'type': self.type,
            'file': self.file,
            'changes': [c.to_dict() for c in self.changes],
            'command': self.command
        }


@dataclass
class EstimatedImpact:
    """预估影响"""
    success_rate_increase: float = 0.0
    cost_increase_usd: float = 0.0
    time_impact_sec: float = 0.0

    def to_dict(self) -> Dict:
        return asdict(self)


@dataclass
class Recommendation:
    """推荐操作"""
    id: str
    priority: str  # "critical", "high", "medium", "low"
    title: str
    description: str
    action: Action
    estimated_impact: EstimatedImpact
    auto_applicable: bool = False
    applied: bool = False

    def to_dict(self) -> Dict:
        return {
            'id': self.id,
            'priority': self.priority,
            'title': self.title,
            'description': self.description,
            'action': self.action.to_dict(),
            'estimated_impact': self.estimated_impact.to_dict(),
            'auto_applicable': self.auto_applicable,
            'applied': self.applied
        }


@dataclass
class KnowledgeBaseMatch:
    """知识库匹配"""
    issue_id: str
    title: str
    similarity: float
    url: str
    solution_applied: int = 0
    success_rate: float = 0.0

    def to_dict(self) -> Dict:
        return asdict(self)


@dataclass
class KnowledgeBase:
    """知识库信息"""
    similar_issues: int = 0
    matches: List[KnowledgeBaseMatch] = field(default_factory=list)

    def to_dict(self) -> Dict:
        return {
            'similar_issues': self.similar_issues,
            'matches': [m.to_dict() for m in self.matches]
        }


@dataclass
class Summary:
    """分析摘要"""
    status: str  # "completed", "partial", "failed"
    total_issues: int = 0
    critical: int = 0
    warnings: int = 0
    overall_health: HealthStatus = HealthStatus.HEALTHY

    def to_dict(self) -> Dict:
        return {
            'status': self.status,
            'total_issues': self.total_issues,
            'critical': self.critical,
            'warnings': self.warnings,
            'overall_health': self.overall_health.value
        }


@dataclass
class DetailedAnalysisResult:
    """
    详细分析结果

    工业级 AI 运维分析的完整数据结构
    """
    analysis_id: str
    workflow_invocation_id: str
    timestamp: str
    duration_ms: int

    summary: Summary
    analysis_steps: List[AnalysisStep] = field(default_factory=list)
    root_causes: List[RootCause] = field(default_factory=list)
    metrics: Metrics = field(default_factory=Metrics)
    resource_usage: ResourceUsage = field(default_factory=ResourceUsage)
    timeline: List[TimelineEvent] = field(default_factory=list)
    recommendations: List[Recommendation] = field(default_factory=list)
    knowledge_base: KnowledgeBase = field(default_factory=KnowledgeBase)

    raw_logs: List[str] = field(default_factory=list)
    agent_reports: Dict[str, Any] = field(default_factory=dict)
    comprehensive_logs: Optional[Dict[str, Any]] = None  # 三源日志综合分析结果

    def to_dict(self) -> Dict:
        """转换为字典（用于 JSON 序列化）"""
        return {
            'analysis_id': self.analysis_id,
            'workflow_invocation_id': self.workflow_invocation_id,
            'timestamp': self.timestamp,
            'duration_ms': self.duration_ms,
            'summary': self.summary.to_dict(),
            'analysis_steps': [step.to_dict() for step in self.analysis_steps],
            'root_causes': [rc.to_dict() for rc in self.root_causes],
            'metrics': self.metrics.to_dict(),
            'resource_usage': self.resource_usage.to_dict(),
            'timeline': [event.to_dict() for event in self.timeline],
            'recommendations': [rec.to_dict() for rec in self.recommendations],
            'knowledge_base': self.knowledge_base.to_dict(),
            'raw_logs': self.raw_logs[:100],  # 限制日志数量
            'agent_reports': self.agent_reports,
            'comprehensive_logs': self.comprehensive_logs  # 三源日志分析结果
        }

    @staticmethod
    def create_empty(workflow_invocation_id: str) -> 'DetailedAnalysisResult':
        """创建空的分析结果"""
        import uuid
        return DetailedAnalysisResult(
            analysis_id=f"ana_{uuid.uuid4().hex[:12]}",
            workflow_invocation_id=workflow_invocation_id,
            timestamp=datetime.utcnow().isoformat() + 'Z',
            duration_ms=0,
            summary=Summary(
                status="pending",
                overall_health=HealthStatus.HEALTHY
            )
        )
