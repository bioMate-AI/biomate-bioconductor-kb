"""
Helper functions for detailed analysis

辅助函数，用于支持工业级详细分析
"""

import uuid
import re
from typing import Dict, Any, Optional, List
from datetime import datetime

# Import models if available
try:
    from galaxy.ai.workflow_ops.models import (
        Recommendation,
        Action,
        ConfigChange,
        EstimatedImpact,
        HealthStatus,
        Severity,
        RootCause
    )
    MODELS_AVAILABLE = True
except ImportError:
    MODELS_AVAILABLE = False


def detect_error_type(error_message: str, exit_code: str) -> str:
    """
    根据错误信息和退出码检测错误类型

    Args:
        error_message: 错误消息
        exit_code: 退出码

    Returns:
        错误类型字符串
    """
    error_msg_lower = error_message.lower()

    # OOM 检测
    if exit_code == '137' or 'out of memory' in error_msg_lower or 'oom' in error_msg_lower:
        return 'out_of_memory'

    # 权限错误
    if 'permission' in error_msg_lower or 'access denied' in error_msg_lower or 'forbidden' in error_msg_lower:
        return 'permission_error'

    # 网络错误
    if 'connection' in error_msg_lower or 'network' in error_msg_lower or 'timeout' in error_msg_lower:
        return 'network_error'

    # 文件不存在
    if 'no such file' in error_msg_lower or 'file not found' in error_msg_lower:
        return 'file_not_found'

    # S3 错误
    if 's3' in error_msg_lower and ('403' in error_message or '404' in error_message):
        return 's3_access_error'

    # 配置错误
    if 'configuration' in error_msg_lower or 'invalid param' in error_msg_lower:
        return 'configuration_error'

    # 默认
    if exit_code != 'unknown' and exit_code != '0':
        return f'execution_error_code_{exit_code}'

    return 'unknown_error'


def create_recommendation_from_fix(fix: Dict[str, Any], root_cause: 'RootCause') -> Optional['Recommendation']:
    """
    从 Agent 返回的修复建议创建 Recommendation 对象

    Args:
        fix: Agent 返回的修复字典
        root_cause: 对应的根本原因

    Returns:
        Recommendation 对象或 None
    """
    if not MODELS_AVAILABLE:
        return None

    try:
        # 提取修复信息
        fix_type = fix.get('type', 'manual')
        description = fix.get('description', '')

        # 创建 Action
        action = Action(
            type=fix_type,
            file=fix.get('file'),
            changes=[],
            command=fix.get('command')
        )

        # 如果有配置更改
        if 'config_changes' in fix:
            for change in fix['config_changes']:
                action.changes.append(
                    ConfigChange(
                        line=change.get('line'),
                        old=change.get('old'),
                        new=change.get('new'),
                        description=change.get('description', '')
                    )
                )

        # 创建推荐
        recommendation = Recommendation(
            id=f"rec_{uuid.uuid4().hex[:8]}",
            priority=_severity_to_priority(root_cause.severity),
            title=fix.get('title', f"Fix for {root_cause.type}"),
            description=description,
            action=action,
            estimated_impact=EstimatedImpact(
                success_rate_increase=fix.get('success_rate_increase', 0.1),
                cost_increase_usd=fix.get('cost_increase_usd', 0.0),
                time_impact_sec=fix.get('time_impact_sec', 0.0)
            ),
            auto_applicable=fix.get('auto_applicable', False),
            applied=False
        )

        return recommendation

    except Exception as e:
        print(f"Error creating recommendation: {e}")
        return None


def generate_recommendation_for_root_cause(root_cause: 'RootCause') -> Optional['Recommendation']:
    """
    为根本原因生成推荐（基于规则）

    Args:
        root_cause: 根本原因对象

    Returns:
        Recommendation 对象或 None
    """
    if not MODELS_AVAILABLE:
        return None

    try:
        # 根据错误类型生成推荐
        if root_cause.type == 'out_of_memory':
            return Recommendation(
                id=f"rec_{uuid.uuid4().hex[:8]}",
                priority="high",
                title="Increase memory allocation",
                description=f"Process '{root_cause.component}' requires more memory. Consider doubling the memory limit.",
                action=Action(
                    type="config_change",
                    file="nextflow.config",
                    changes=[
                        ConfigChange(
                            line=None,
                            old="memory = '8.GB'",
                            new="memory = '16.GB'",
                            description="Double memory allocation"
                        )
                    ]
                ),
                estimated_impact=EstimatedImpact(
                    success_rate_increase=0.15,
                    cost_increase_usd=0.34,
                    time_impact_sec=0.0
                ),
                auto_applicable=False,  # 需要用户确认
                applied=False
            )

        elif root_cause.type == 's3_access_error' or root_cause.type == 'permission_error':
            return Recommendation(
                id=f"rec_{uuid.uuid4().hex[:8]}",
                priority="critical",
                title="Fix S3 access permissions",
                description="Add required S3 permissions to AWS Batch role or update bucket policy.",
                action=Action(
                    type="manual",
                    file=None,
                    command="aws s3api put-bucket-policy --bucket YOUR_BUCKET --policy file://policy.json"
                ),
                estimated_impact=EstimatedImpact(
                    success_rate_increase=1.0,
                    cost_increase_usd=0.0,
                    time_impact_sec=0.0
                ),
                auto_applicable=False,
                applied=False
            )

        elif root_cause.type == 'network_error':
            return Recommendation(
                id=f"rec_{uuid.uuid4().hex[:8]}",
                priority="high",
                title="Configure retry policy",
                description="Add retry configuration for network-related failures.",
                action=Action(
                    type="config_change",
                    file="nextflow.config",
                    changes=[
                        ConfigChange(
                            line=None,
                            old="",
                            new="process.errorStrategy = 'retry'\nprocess.maxRetries = 3",
                            description="Add retry strategy"
                        )
                    ]
                ),
                estimated_impact=EstimatedImpact(
                    success_rate_increase=0.3,
                    cost_increase_usd=0.1,
                    time_impact_sec=300.0
                ),
                auto_applicable=True,
                applied=False
            )

        # 默认建议
        return Recommendation(
            id=f"rec_{uuid.uuid4().hex[:8]}",
            priority=_severity_to_priority(root_cause.severity),
            title=f"Review and fix {root_cause.type}",
            description=f"Manual investigation required for {root_cause.component}. Review logs and error evidence.",
            action=Action(
                type="manual",
                file=None,
                command=None
            ),
            estimated_impact=EstimatedImpact(
                success_rate_increase=0.0,
                cost_increase_usd=0.0,
                time_impact_sec=0.0
            ),
            auto_applicable=False,
            applied=False
        )

    except Exception as e:
        print(f"Error generating recommendation: {e}")
        return None


def calculate_health_status(analysis_result) -> 'HealthStatus':
    """
    根据分析结果计算整体健康状态

    Args:
        analysis_result: DetailedAnalysisResult 对象

    Returns:
        HealthStatus 枚举值
    """
    if not MODELS_AVAILABLE:
        return 'healthy'

    # 统计严重程度
    critical_count = sum(1 for rc in analysis_result.root_causes if rc.severity == Severity.CRITICAL)
    high_count = sum(1 for rc in analysis_result.root_causes if rc.severity == Severity.HIGH)

    # 判断健康状态
    if critical_count > 0:
        return HealthStatus.CRITICAL
    elif high_count > 2:
        return HealthStatus.UNHEALTHY
    elif high_count > 0 or len(analysis_result.root_causes) > 3:
        return HealthStatus.DEGRADED
    else:
        return HealthStatus.HEALTHY


def _severity_to_priority(severity: 'Severity') -> str:
    """将严重程度转换为优先级"""
    mapping = {
        Severity.CRITICAL: "critical",
        Severity.HIGH: "high",
        Severity.MEDIUM: "medium",
        Severity.LOW: "low",
        Severity.INFO: "low"
    }
    return mapping.get(severity, "medium")
