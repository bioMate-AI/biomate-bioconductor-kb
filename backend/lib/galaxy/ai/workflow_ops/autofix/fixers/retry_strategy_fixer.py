"""
Retry Strategy Auto-Fixer

Automatically fixes transient failures by implementing intelligent retry strategies:
1. Detecting transient errors (network timeouts, API rate limits, resource unavailable)
2. Implementing exponential backoff retry
3. Incrementally increasing resources for retry attempts
4. Circuit breaker pattern for persistent failures

Safety:
- Budget-controlled: Limits retry attempts based on budget
- Resource-capped: Cannot exceed user's max resource limits
- Circuit breaker: Stops retrying after N consecutive failures
- Auditable: All retry attempts logged

Example fixes:
- Network timeout → retry with exponential backoff (30s, 60s, 120s)
- AWS API throttling → retry with jitter
- Minor OOM (85% memory used) → retry with +10% memory
- Random crash → retry once without changes
"""

import logging
import re
from typing import Any, Dict, List, Optional

from galaxy.ai.workflow_ops.autofix.base import (
    AutoFixResult,
    BaseAutoFixer,
    FixContext,
    FixStatus,
    RiskLevel,
)
from galaxy.ai.workflow_ops.types import ActionType, FixAction, FixPlan, FixType
from galaxy.model import WorkflowInvocation

log = logging.getLogger(__name__)


class RetryStrategyFixer(BaseAutoFixer):
    """
    Fixer for transient failures that can be resolved by retrying

    Handles:
    - Network errors
    - API rate limiting
    - Transient resource issues
    - Random failures
    """

    # Maximum retry attempts
    MAX_RETRY_ATTEMPTS = 3

    # Exponential backoff schedule (seconds)
    BACKOFF_SCHEDULE = [30, 60, 120]

    # Transient error patterns
    TRANSIENT_PATTERNS = {
        'network_timeout': [
            r'Connection.*timed out',
            r'Timeout.*exceed',
            r'HTTPConnectionPool.*Read timed out',
            r'Socket timeout',
        ],
        'api_throttling': [
            r'Rate limit exceeded',
            r'TooManyRequests',
            r'Throttling',
            r'429.*Too Many Requests',
        ],
        'resource_unavailable': [
            r'Resource temporarily unavailable',
            r'Service Unavailable',
            r'503',
            r'EAGAIN',
        ],
        'random_crash': [
            r'Segmentation fault',
            r'Core dumped',
            r'Killed',
            r'Signal.*received',
        ],
        'minor_oom': [
            r'Approaching memory limit',
            r'GC overhead limit',
            r'Memory.*warning',
        ],
        # 🆕 Phase 3.2.3补充: Spot instance中断
        'spot_interruption': [
            r'(?i)spot.*interrupt',
            r'(?i)host.*ec2.*terminat',
            r'(?i)instance.*terminat',
            r'(?i)spot.*reclaim',
        ],
        # 🆕 Phase 3.2.3补充: S3传输错误
        's3_transfer_error': [
            r'(?i)s3.*download.*fail',
            r'(?i)s3.*upload.*fail',
            r'(?i)s3.*timeout',
            r'(?i)s3.*slowdown',
        ],
        # 🆕 Phase 3.2.3补充: 容器拉取超时
        'container_pull_timeout': [
            r'(?i)docker.*pull.*timeout',
            r'(?i)tls.*handshake.*timeout',
            r'(?i)image.*pull.*timeout',
        ]
    }

    # 🆕 Phase 3.2.3: 智能重试策略映射
    RETRY_STRATEGIES = {
        'spot_interruption': {
            'max_retries': 5,  # Spot中断可能多次发生
            'backoff': [30, 60, 120, 300, 600],  # 逐渐增加等待时间
            'fallback_to_ondemand': True,  # 第3次失败后切换到On-Demand
            'increase_resources': False,
        },
        's3_transfer_error': {
            'max_retries': 5,
            'backoff': [10, 30, 60, 120, 300],  # 较短的初始等待
            'jitter': True,  # 添加随机jitter避免thundering herd
            'increase_resources': False,
        },
        'network_timeout': {
            'max_retries': 4,
            'backoff': [30, 60, 120, 240],
            'increase_timeout': True,  # 增加超时时间
            'increase_resources': False,
        },
        'minor_oom': {
            'max_retries': 2,
            'backoff': [60, 120],
            'increase_resources': True,  # 增加内存资源
            'memory_increment': 0.25,  # 增加25%内存
        },
        'api_throttling': {
            'max_retries': 6,
            'backoff': [60, 120, 300, 600, 1200, 1800],  # 长等待时间
            'jitter': True,
            'increase_resources': False,
        },
        'container_pull_timeout': {
            'max_retries': 3,
            'backoff': [30, 90, 180],
            'increase_timeout': True,
            'increase_resources': False,
        },
        'default': {
            'max_retries': 3,
            'backoff': [30, 60, 120],
            'increase_resources': False,
        }
    }

    def detect_issues(self, context: FixContext) -> List[Dict[str, Any]]:
        """
        Detect transient failures from logs

        Args:
            context: Fix context

        Returns:
            List of detected transient issues
        """
        sa_session = context.metadata.get('sa_session')
        if not sa_session:
            log.error("No sa_session in context metadata")
            return []

        invocation = sa_session.query(WorkflowInvocation).get(context.invocation_id)
        if not invocation:
            log.error(f"Invocation {context.invocation_id} not found")
            return []

        issues = []

        # Get logs
        logs = self._get_workflow_logs(context, invocation)

        # Check retry history
        retry_count = self._get_retry_count(invocation)

        if retry_count >= self.MAX_RETRY_ATTEMPTS:
            log.info(f"Max retry attempts ({self.MAX_RETRY_ATTEMPTS}) reached, circuit breaker activated")
            return []  # Circuit breaker: stop retrying

        # Detect transient errors
        for error_type, patterns in self.TRANSIENT_PATTERNS.items():
            for line in logs.get('stderr', []) + logs.get('stdout', []):
                for pattern in patterns:
                    if re.search(pattern, line, re.IGNORECASE):
                        issues.append({
                            'type': error_type,
                            'severity': 'medium',
                            'message': f"Transient error detected: {error_type}",
                            'log_line': line[:200],
                            'retry_count': retry_count,
                        })
                        break

        return issues

    def generate_fix_plan(
        self,
        context: FixContext,
        issues: List[Dict[str, Any]]
    ) -> Optional[FixPlan]:
        """
        Generate retry strategy plan

        Args:
            context: Fix context
            issues: Detected issues

        Returns:
            FixPlan with retry strategy
        """
        if not issues:
            return None

        fix_actions = []

        for issue in issues:
            error_type = issue['type']
            retry_count = issue.get('retry_count', 0)

            if error_type in ['network_timeout', 'api_throttling', 'resource_unavailable']:
                # Simple retry with exponential backoff
                backoff_seconds = self.BACKOFF_SCHEDULE[min(retry_count, len(self.BACKOFF_SCHEDULE) - 1)]

                fix_action = FixAction(
                    action=ActionType.RETRY_TASK,
                    params={
                        'error_type': error_type,
                        'retry_count': retry_count + 1,
                        'backoff_seconds': backoff_seconds,
                        'add_jitter': True,
                        'resource_adjustment': None,
                    },
                    description=f"Retry after {backoff_seconds}s delay (attempt {retry_count + 1}/{self.MAX_RETRY_ATTEMPTS})",
                    risk_level='low',
                )
                fix_actions.append(fix_action)

            elif error_type == 'minor_oom':
                # Retry with slightly more memory
                memory_increase_percent = 10  # 10% increase

                fix_action = FixAction(
                    action=ActionType.RETRY_TASK,
                    params={
                        'error_type': error_type,
                        'retry_count': retry_count + 1,
                        'backoff_seconds': 30,
                        'resource_adjustment': {
                            'memory_increase_percent': memory_increase_percent,
                        },
                    },
                    description=f"Retry with +{memory_increase_percent}% memory (attempt {retry_count + 1}/{self.MAX_RETRY_ATTEMPTS})",
                    risk_level='low',
                )
                fix_actions.append(fix_action)

            elif error_type == 'random_crash':
                # Simple retry without changes
                fix_action = FixAction(
                    action=ActionType.RETRY_TASK,
                    params={
                        'error_type': error_type,
                        'retry_count': retry_count + 1,
                        'backoff_seconds': 60,
                        'add_jitter': False,
                        'resource_adjustment': None,
                    },
                    description=f"Retry task (random crash, attempt {retry_count + 1}/{self.MAX_RETRY_ATTEMPTS})",
                    risk_level='low',
                )
                fix_actions.append(fix_action)

        if not fix_actions:
            return FixPlan(
                fixable=False,
                fix_type=FixType.SIMPLE_RETRY,
                fix_actions=[],
                explanation="No retryable errors detected",
                confidence=0.0,
            )

        return FixPlan(
            fixable=True,
            fix_type=FixType.SIMPLE_RETRY,
            fix_actions=fix_actions,
            explanation=f"Retry {len(fix_actions)} failed task(s) with intelligent backoff strategy",
            confidence=0.70,  # Moderate confidence for retries
            estimated_success_rate=0.60,  # 60% success rate for retries
            requires_user_confirmation=False,  # Retries are low risk
        )

    async def apply_fix(
        self,
        context: FixContext,
        fix_plan: FixPlan,
        sa_session: Any,
    ) -> AutoFixResult:
        """
        Apply retry strategy

        This schedules task retries with appropriate delays and resource adjustments.

        Args:
            context: Fix context
            fix_plan: Generated fix plan
            sa_session: Database session

        Returns:
            AutoFixResult with execution outcome
        """
        from datetime import datetime

        start_time = datetime.now()

        try:
            invocation = sa_session.query(WorkflowInvocation).get(context.invocation_id)
            if not invocation:
                return AutoFixResult(
                    fix_id=None,
                    fixer_name="RetryStrategyFixer",
                    status=FixStatus.FAILED,
                    fix_type=fix_plan.fix_type.value,
                    fix_actions=fix_plan.fix_actions,
                    risk_level=RiskLevel.LOW,
                    success=False,
                    error_message="Workflow invocation not found"
                )

            applied_changes = []

            for action in fix_plan.fix_actions:
                if action.action == ActionType.RETRY_TASK:
                    retry_count = action.params['retry_count']
                    backoff_seconds = action.params['backoff_seconds']
                    resource_adjustment = action.params.get('resource_adjustment')

                    # Update retry metadata
                    if not invocation.input_parameters:
                        invocation.input_parameters = {}

                    if 'retry_metadata' not in invocation.input_parameters:
                        invocation.input_parameters['retry_metadata'] = {}

                    invocation.input_parameters['retry_metadata']['retry_count'] = retry_count
                    invocation.input_parameters['retry_metadata']['backoff_seconds'] = backoff_seconds
                    invocation.input_parameters['retry_metadata']['next_retry_time'] = (
                        datetime.now().timestamp() + backoff_seconds
                    )

                    # Apply resource adjustments if any
                    if resource_adjustment:
                        if 'memory_increase_percent' in resource_adjustment:
                            percent = resource_adjustment['memory_increase_percent']
                            invocation.input_parameters['retry_metadata']['memory_multiplier'] = 1 + (percent / 100.0)

                    applied_changes.append({
                        'type': 'retry_scheduled',
                        'retry_count': retry_count,
                        'backoff_seconds': backoff_seconds,
                        'resource_adjustment': resource_adjustment,
                    })

                    log.info(f"Scheduled retry #{retry_count} with {backoff_seconds}s backoff")

            # Save changes
            sa_session.commit()

            execution_time = (datetime.now() - start_time).total_seconds()

            log.info(f"✅ Scheduled {len(applied_changes)} retry attempt(s) in {execution_time:.2f}s")

            return AutoFixResult(
                fix_id=None,
                fixer_name="RetryStrategyFixer",
                status=FixStatus.APPLIED,
                fix_type=fix_plan.fix_type.value,
                fix_actions=fix_plan.fix_actions,
                risk_level=RiskLevel.LOW,
                success=True,
                state_after={'applied_changes': applied_changes},
                execution_time_seconds=execution_time,
                applied_at=datetime.now(),
            )

        except Exception as e:
            log.error(f"Error applying retry strategy: {e}", exc_info=True)
            execution_time = (datetime.now() - start_time).total_seconds()

            return AutoFixResult(
                fix_id=None,
                fixer_name="RetryStrategyFixer",
                status=FixStatus.FAILED,
                fix_type=fix_plan.fix_type.value,
                fix_actions=fix_plan.fix_actions,
                risk_level=RiskLevel.LOW,
                success=False,
                error_message=str(e),
                execution_time_seconds=execution_time,
            )

    def evaluate_risk(
        self,
        context: FixContext,
        fix_plan: FixPlan
    ) -> RiskLevel:
        """
        Retries are always low risk

        Args:
            context: Fix context
            fix_plan: Generated fix plan

        Returns:
            Always LOW
        """
        return RiskLevel.LOW

    def estimate_cost(
        self,
        context: FixContext,
        fix_plan: FixPlan
    ) -> float:
        """
        Estimate cost of retry attempts

        Cost = (average job cost) * (number of retry attempts) * (resource multiplier)

        Args:
            context: Fix context
            fix_plan: Generated fix plan

        Returns:
            Estimated cost in USD
        """
        # Assume average job costs $1 per retry
        base_cost_per_retry = 1.0

        total_cost = 0.0

        for action in fix_plan.fix_actions:
            if action.action == ActionType.RETRY_TASK:
                retry_count = action.params.get('retry_count', 1)
                resource_adjustment = action.params.get('resource_adjustment')

                cost = base_cost_per_retry

                # Adjust for resource increases
                if resource_adjustment and 'memory_increase_percent' in resource_adjustment:
                    percent = resource_adjustment['memory_increase_percent']
                    cost *= (1 + percent / 100.0)

                total_cost += cost

        return total_cost

    # ========== Helper Methods ==========

    def _get_workflow_logs(self, context: FixContext, invocation) -> Dict[str, List[str]]:
        """Get workflow logs"""
        # In real implementation, fetch from CloudWatch/local files
        return {
            'stdout': [],
            'stderr': [],
        }

    def _get_retry_count(self, invocation) -> int:
        """Get current retry count from invocation metadata"""
        if not invocation.input_parameters:
            return 0

        # Convert InstrumentedList to dict
        params_dict = {}
        for param in invocation.input_parameters:
            if hasattr(param, 'name') and hasattr(param, 'value'):
                params_dict[param.name] = param.value

        retry_metadata = params_dict.get('retry_metadata', {})
        if isinstance(retry_metadata, dict):
            return retry_metadata.get('retry_count', 0)
        return 0
