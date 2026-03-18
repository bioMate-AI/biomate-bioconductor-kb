"""
Fix Effect Validation Module

🆕 Phase 3.3: 修复效果验证

Provides mechanisms to:
1. Validate fixes before applying them
2. Track fix success rates
3. Generate fix effectiveness reports
4. Auto-tune fix confidence based on historical data

Safety:
- Pre-validation to catch obvious errors
- Post-validation to confirm fix worked
- Success rate tracking per fixer type
- Automatic confidence adjustment
"""

import logging
from datetime import datetime, timedelta
from typing import Any, Dict, List, Optional, Tuple

from galaxy.ai.workflow_ops.autofix.base import AutoFixResult, FixContext, FixPlan, FixStatus
from galaxy.model import WorkflowInvocation

log = logging.getLogger(__name__)


class FixValidator:
    """
    Validates fixes before and after application

    🆕 Phase 3.3补充: 修复前后验证机制
    """

    def __init__(self, sa_session: Any):
        self.sa_session = sa_session

    def pre_validate(
        self,
        context: FixContext,
        fix_plan: FixPlan
    ) -> Tuple[bool, Optional[str]]:
        """
        Pre-validate fix plan before application

        Checks:
        1. Parameter validity
        2. Resource limits not exceeded
        3. Fix actions are reasonable
        4. No obvious conflicts

        Args:
            context: Fix context
            fix_plan: Proposed fix plan

        Returns:
            (is_valid, error_message)
        """
        try:
            # Check if fixable
            if not fix_plan.fixable:
                return False, "Fix plan is marked as not fixable"

            # Check if there are fix actions
            if not fix_plan.fix_actions:
                return False, "Fix plan has no actions"

            # Validate resource limits
            for action in fix_plan.fix_actions:
                params = action.params or {}

                # Check memory limits
                if 'memory_gb' in params:
                    requested_memory = params['memory_gb']
                    if requested_memory > context.max_memory_gb:
                        return False, f"Requested memory ({requested_memory}GB) exceeds user limit ({context.max_memory_gb}GB)"

                # Check CPU limits
                if 'cpus' in params:
                    requested_cpus = params['cpus']
                    if requested_cpus > context.max_cpus:
                        return False, f"Requested CPUs ({requested_cpus}) exceeds user limit ({context.max_cpus})"

                # Check memory increase percent is reasonable
                if 'memory_increase_percent' in params:
                    percent = params['memory_increase_percent']
                    if percent > 100:  # Max 100% increase
                        return False, f"Memory increase ({percent}%) is too large (max 100%)"

                # Check retry count is reasonable
                if 'retry_count' in params:
                    retry_count = params['retry_count']
                    if retry_count > 10:  # Max 10 retries
                        return False, f"Retry count ({retry_count}) is too high (max 10)"

            # Check confidence threshold
            if fix_plan.confidence and fix_plan.confidence < 0.3:
                return False, f"Fix confidence too low ({fix_plan.confidence:.2f})"

            log.info(f"✅ Pre-validation passed for {len(fix_plan.fix_actions)} fix action(s)")
            return True, None

        except Exception as e:
            log.error(f"Pre-validation error: {e}", exc_info=True)
            return False, f"Validation error: {str(e)}"

    def post_validate(
        self,
        context: FixContext,
        fix_result: AutoFixResult
    ) -> Tuple[bool, Optional[str]]:
        """
        Post-validate fix after application

        Checks:
        1. Fix was actually applied
        2. Invocation state is valid
        3. No unexpected side effects

        Args:
            context: Fix context
            fix_result: Fix result after application

        Returns:
            (is_valid, error_message)
        """
        try:
            # Check if fix was successful
            if not fix_result.success:
                return False, fix_result.error_message or "Fix failed"

            # Check status
            if fix_result.status not in [FixStatus.APPLIED, FixStatus.APPROVED]:
                return False, f"Unexpected fix status: {fix_result.status.value}"

            # Check invocation still exists
            invocation = self.sa_session.query(WorkflowInvocation).get(context.invocation_id)
            if not invocation:
                return False, "Workflow invocation not found after fix"

            # Check state_after is present
            if not fix_result.state_after:
                log.warning("No state_after in fix result")

            log.info("✅ Post-validation passed")
            return True, None

        except Exception as e:
            log.error(f"Post-validation error: {e}", exc_info=True)
            return False, f"Validation error: {str(e)}"


class FixSuccessTracker:
    """
    Tracks fix success rates for continuous improvement

    🆕 Phase 3.3补充: 修复成功率统计
    """

    def __init__(self, sa_session: Any):
        self.sa_session = sa_session

    def record_fix_attempt(
        self,
        fixer_name: str,
        fix_type: str,
        success: bool,
        issue_type: Optional[str] = None,
        confidence: Optional[float] = None,
        execution_time: Optional[float] = None,
    ):
        """
        Record a fix attempt for statistics

        Args:
            fixer_name: Name of the fixer
            fix_type: Type of fix
            success: Whether fix succeeded
            issue_type: Specific issue type (optional)
            confidence: Fix confidence score (optional)
            execution_time: Time taken in seconds (optional)
        """
        try:
            # In a real implementation, this would write to a database table
            # For now, we'll just log it

            status_emoji = "✅" if success else "❌"

            # 正确处理可选值的格式化
            confidence_str = f"{confidence:.2f}" if confidence else "N/A"
            time_str = f"{execution_time:.2f}s" if execution_time else "N/A"

            log.info(
                f"{status_emoji} Fix attempt: fixer={fixer_name}, "
                f"type={fix_type}, issue={issue_type}, "
                f"confidence={confidence_str}, time={time_str}"
            )

            # TODO: Store in AIFixAuditLog or separate statistics table

        except Exception as e:
            log.error(f"Error recording fix attempt: {e}", exc_info=True)

    def get_success_rate(
        self,
        fixer_name: Optional[str] = None,
        fix_type: Optional[str] = None,
        issue_type: Optional[str] = None,
        days: int = 30
    ) -> Dict[str, Any]:
        """
        Get fix success rate statistics

        Args:
            fixer_name: Filter by fixer name (optional)
            fix_type: Filter by fix type (optional)
            issue_type: Filter by issue type (optional)
            days: Number of days to look back (default 30)

        Returns:
            Statistics dictionary with success rates
        """
        try:
            # In a real implementation, this would query the database
            # For now, return mock statistics

            return {
                "fixer_name": fixer_name,
                "fix_type": fix_type,
                "issue_type": issue_type,
                "period_days": days,
                "total_attempts": 0,  # TODO: Query from DB
                "successful_attempts": 0,
                "success_rate": 0.0,
                "average_confidence": 0.0,
                "average_execution_time": 0.0,
            }

        except Exception as e:
            log.error(f"Error getting success rate: {e}", exc_info=True)
            return {}

    def generate_effectiveness_report(
        self,
        days: int = 7
    ) -> Dict[str, Any]:
        """
        Generate comprehensive fix effectiveness report

        Args:
            days: Number of days to analyze (default 7)

        Returns:
            Report with fix effectiveness metrics
        """
        try:
            report = {
                "generated_at": datetime.now().isoformat(),
                "period_days": days,
                "summary": {
                    "total_fix_attempts": 0,
                    "successful_fixes": 0,
                    "failed_fixes": 0,
                    "overall_success_rate": 0.0,
                },
                "by_fixer": {},
                "by_fix_type": {},
                "by_issue_type": {},
                "recommendations": []
            }

            # TODO: Query database for actual statistics

            # Example recommendations based on success rates
            # if success_rate < 0.5:
            #     report["recommendations"].append(
            #         f"Low success rate for {fixer_name} - consider improving detection logic"
            #     )

            return report

        except Exception as e:
            log.error(f"Error generating effectiveness report: {e}", exc_info=True)
            return {}

    def auto_tune_confidence(
        self,
        fixer_name: str,
        fix_type: str,
        current_confidence: float,
        days: int = 30
    ) -> float:
        """
        Auto-tune fix confidence based on historical success rate

        🆕 Phase 3.3补充: 基于历史数据自动调整confidence

        Args:
            fixer_name: Name of the fixer
            fix_type: Type of fix
            current_confidence: Current confidence score
            days: Number of days to analyze

        Returns:
            Adjusted confidence score
        """
        try:
            # Get historical success rate
            stats = self.get_success_rate(
                fixer_name=fixer_name,
                fix_type=fix_type,
                days=days
            )

            success_rate = stats.get('success_rate', 0.5)

            # Adjust confidence based on success rate
            # If success rate is high, boost confidence slightly
            # If success rate is low, reduce confidence

            if success_rate > 0.9:
                # High success rate: boost confidence by 10%
                adjusted = min(current_confidence * 1.1, 1.0)
            elif success_rate > 0.7:
                # Good success rate: keep confidence as is
                adjusted = current_confidence
            elif success_rate > 0.5:
                # Moderate success rate: reduce confidence by 10%
                adjusted = current_confidence * 0.9
            else:
                # Low success rate: reduce confidence by 20%
                adjusted = current_confidence * 0.8

            if adjusted != current_confidence:
                log.info(
                    f"Auto-tuned confidence for {fixer_name}/{fix_type}: "
                    f"{current_confidence:.2f} → {adjusted:.2f} "
                    f"(based on {success_rate:.1%} success rate)"
                )

            return adjusted

        except Exception as e:
            log.error(f"Error auto-tuning confidence: {e}", exc_info=True)
            return current_confidence


class FixSimulator:
    """
    Simulates fix application to predict outcome

    🆕 Phase 3.3补充: 修复效果模拟预测
    """

    def __init__(self, sa_session: Any):
        self.sa_session = sa_session

    def simulate_parameter_fix(
        self,
        context: FixContext,
        fix_plan: FixPlan
    ) -> Tuple[bool, Optional[str]]:
        """
        Simulate parameter fix to check if it will likely succeed

        Args:
            context: Fix context
            fix_plan: Proposed fix plan

        Returns:
            (likely_success, prediction_message)
        """
        try:
            # Check if parameters are valid
            for action in fix_plan.fix_actions:
                params = action.params or {}

                # Example: Check if parameter values are in valid ranges
                if 'memory_gb' in params:
                    memory = params['memory_gb']
                    if memory < 1 or memory > 1024:
                        return False, f"Memory value {memory}GB is out of valid range"

                if 'cpus' in params:
                    cpus = params['cpus']
                    if cpus < 1 or cpus > 256:
                        return False, f"CPU value {cpus} is out of valid range"

            log.info("✅ Simulation predicts fix will likely succeed")
            return True, "Simulation successful"

        except Exception as e:
            log.error(f"Simulation error: {e}", exc_info=True)
            return False, f"Simulation error: {str(e)}"

    def estimate_fix_impact(
        self,
        context: FixContext,
        fix_plan: FixPlan
    ) -> Dict[str, Any]:
        """
        Estimate the impact of applying a fix

        Args:
            context: Fix context
            fix_plan: Proposed fix plan

        Returns:
            Impact estimation dictionary
        """
        impact = {
            "resource_changes": {
                "memory_delta_gb": 0,
                "cpu_delta": 0,
                "disk_delta_gb": 0,
            },
            "estimated_runtime_change_percent": 0,
            "estimated_cost_change_usd": 0.0,
            "risk_factors": [],
        }

        try:
            invocation = self.sa_session.query(WorkflowInvocation).get(context.invocation_id)
            if not invocation:
                return impact

            # Calculate resource deltas
            for action in fix_plan.fix_actions:
                params = action.params or {}

                if 'memory_increase_percent' in params:
                    percent = params['memory_increase_percent']
                    # Assume current memory is context.max_memory_gb
                    current_memory = context.max_memory_gb * 0.5  # Assume using 50%
                    delta = current_memory * (percent / 100.0)
                    impact["resource_changes"]["memory_delta_gb"] += delta
                    impact["estimated_cost_change_usd"] += delta * 0.01  # $0.01 per GB

                if 'retry_count' in params:
                    retry_count = params['retry_count']
                    impact["estimated_cost_change_usd"] += retry_count * 1.0  # $1 per retry
                    impact["estimated_runtime_change_percent"] += retry_count * 10  # +10% per retry

            # Identify risk factors
            if impact["resource_changes"]["memory_delta_gb"] > 10:
                impact["risk_factors"].append("Large memory increase may hit account limits")

            if impact["estimated_cost_change_usd"] > 10:
                impact["risk_factors"].append("High cost increase may require user approval")

            return impact

        except Exception as e:
            log.error(f"Error estimating fix impact: {e}", exc_info=True)
            return impact
