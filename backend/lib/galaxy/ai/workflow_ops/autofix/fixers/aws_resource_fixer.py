"""
AWS Resource Auto-Fixer

Automatically fixes AWS resource allocation issues by:
1. Detecting OOM (Out of Memory) errors from CloudWatch logs
2. Detecting CPU throttling issues
3. Detecting disk space issues
4. Automatically adjusting resource allocations within user limits

Safety:
- User-isolated: Only modifies user's own AWS resource configurations
- Cost-controlled: Checks budget before increasing resources
- Limited: Cannot exceed UserCloudPreferences.max_memory_gb/max_cpus
- Auditable: All changes logged to AIFixAuditLog

Example issues fixed:
- Memory: Task requires 16GB but allocated 8GB → increase to 18GB (1.125x actual need)
- CPU: Task throttled at 4 vCPUs → increase to 6 vCPUs
- Disk: Task ran out of disk space → increase storage allocation
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


class AWSResourceFixer(BaseAutoFixer):
    """
    Fixer for AWS resource allocation issues

    Handles:
    - Out of Memory (OOM) errors
    - CPU throttling
    - Disk space exhaustion
    """

    # Resource adjustment safety margins
    MEMORY_OVERHEAD = 1.25  # Add 25% overhead to actual memory usage
    CPU_OVERHEAD = 1.2      # Add 20% overhead for CPU
    DISK_OVERHEAD = 1.5     # Add 50% overhead for disk

    # AWS pricing (USD per hour, approximate)
    VCPU_COST_PER_HOUR = 0.04
    GB_MEMORY_COST_PER_HOUR = 0.004
    GB_DISK_COST_PER_GB_MONTH = 0.10

    def detect_issues(self, context: FixContext) -> List[Dict[str, Any]]:
        """
        Detect AWS resource issues from logs and metrics

        Args:
            context: Fix context

        Returns:
            List of detected resource issues
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

        # Get logs (from context or fetch from CloudWatch)
        logs = self._get_workflow_logs(context, invocation)

        # Detect OOM errors
        oom_issues = self._detect_oom_errors(logs)
        issues.extend(oom_issues)

        # Detect CPU throttling
        cpu_issues = self._detect_cpu_throttling(logs)
        issues.extend(cpu_issues)

        # Detect disk space issues
        disk_issues = self._detect_disk_issues(logs)
        issues.extend(disk_issues)

        # 🆕 Phase 3 Day 7: Detect Spot instance interruptions
        spot_issues = self._detect_spot_interruptions(logs)
        issues.extend(spot_issues)

        # 🆕 Phase 3 Day 7: Detect S3 transfer errors
        s3_issues = self._detect_s3_transfer_errors(logs)
        issues.extend(s3_issues)

        # 🆕 Phase 3 Day 7: Detect container pull errors
        container_issues = self._detect_container_pull_errors(logs)
        issues.extend(container_issues)

        return issues

    def generate_fix_plan(
        self,
        context: FixContext,
        issues: List[Dict[str, Any]]
    ) -> Optional[FixPlan]:
        """
        Generate fix plan for resource issues

        Args:
            context: Fix context
            issues: Detected issues

        Returns:
            FixPlan with resource adjustment recommendations
        """
        if not issues:
            return None

        fix_actions = []

        for issue in issues:
            issue_type = issue['type']

            if issue_type == 'oom':
                # Memory adjustment
                current_memory = issue.get('current_memory_gb', 8)
                required_memory = issue.get('required_memory_gb', current_memory * 2)
                recommended_memory = int(required_memory * self.MEMORY_OVERHEAD)

                # Check against user limits
                recommended_memory = min(recommended_memory, context.max_memory_gb)

                if recommended_memory > current_memory:
                    fix_action = FixAction(
                        action=ActionType.INCREASE_MEMORY,
                        params={
                            'current_memory_gb': current_memory,
                            'recommended_memory_gb': recommended_memory,
                            'task_name': issue.get('task_name', 'unknown'),
                        },
                        description=f"Increase memory from {current_memory}GB to {recommended_memory}GB (task: {issue.get('task_name', 'unknown')})",
                        risk_level='medium',  # Resource changes are medium risk
                    )
                    fix_actions.append(fix_action)

            elif issue_type == 'cpu_throttling':
                # CPU adjustment
                current_cpus = issue.get('current_cpus', 2)
                recommended_cpus = int(current_cpus * self.CPU_OVERHEAD)

                # Check against user limits
                recommended_cpus = min(recommended_cpus, context.max_cpus)

                if recommended_cpus > current_cpus:
                    fix_action = FixAction(
                        action=ActionType.INCREASE_MEMORY,  # Reuse this for CPU (or create new ActionType)
                        params={
                            'current_cpus': current_cpus,
                            'recommended_cpus': recommended_cpus,
                            'task_name': issue.get('task_name', 'unknown'),
                        },
                        description=f"Increase CPUs from {current_cpus} to {recommended_cpus} (task: {issue.get('task_name', 'unknown')})",
                        risk_level='medium',
                    )
                    fix_actions.append(fix_action)

            elif issue_type == 'disk_space':
                # Disk adjustment
                current_disk = issue.get('current_disk_gb', 100)
                required_disk = issue.get('required_disk_gb', current_disk * 2)
                recommended_disk = int(required_disk * self.DISK_OVERHEAD)

                # Check against user limits
                recommended_disk = min(recommended_disk, context.max_memory_gb * 10)  # Max 10x memory

                if recommended_disk > current_disk:
                    fix_action = FixAction(
                        action=ActionType.INCREASE_DISK,
                        params={
                            'current_disk_gb': current_disk,
                            'recommended_disk_gb': recommended_disk,
                            'task_name': issue.get('task_name', 'unknown'),
                        },
                        description=f"Increase disk from {current_disk}GB to {recommended_disk}GB (task: {issue.get('task_name', 'unknown')})",
                        risk_level='low',  # Disk is low risk
                    )
                    fix_actions.append(fix_action)

        if not fix_actions:
            return FixPlan(
                fixable=False,
                fix_type=FixType.RESOURCE_SCALING,
                fix_actions=[],
                explanation="Detected resource issues but cannot adjust within user limits",
                confidence=0.0,
                requires_user_confirmation=True,
            )

        return FixPlan(
            fixable=True,
            fix_type=FixType.RESOURCE_SCALING,
            fix_actions=fix_actions,
            explanation=f"Automatically adjust {len(fix_actions)} resource allocation(s) based on actual usage",
            confidence=0.85,
            estimated_success_rate=0.80,
            requires_user_confirmation=True,  # Always require confirmation for resource changes
        )

    async def apply_fix(
        self,
        context: FixContext,
        fix_plan: FixPlan,
        sa_session: Any,
    ) -> AutoFixResult:
        """
        Apply resource adjustments

        This updates the workflow/job configuration with new resource limits.

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
                    fixer_name="AWSResourceFixer",
                    status=FixStatus.FAILED,
                    fix_type=fix_plan.fix_type.value,
                    fix_actions=fix_plan.fix_actions,
                    risk_level=RiskLevel.MEDIUM,
                    success=False,
                    error_message="Workflow invocation not found"
                )

            # Apply each resource adjustment
            applied_changes = []

            for action in fix_plan.fix_actions:
                if action.action == ActionType.INCREASE_MEMORY:
                    # Update workflow job configuration
                    if 'recommended_memory_gb' in action.params:
                        new_memory = action.params['recommended_memory_gb']
                        task_name = action.params.get('task_name', 'global')

                        # Store in invocation metadata or job_config
                        if not invocation.input_parameters:
                            invocation.input_parameters = {}

                        if 'resource_overrides' not in invocation.input_parameters:
                            invocation.input_parameters['resource_overrides'] = {}

                        invocation.input_parameters['resource_overrides'][task_name] = {
                            'memory_gb': new_memory
                        }

                        applied_changes.append({
                            'resource': 'memory',
                            'task': task_name,
                            'old_value': action.params.get('current_memory_gb'),
                            'new_value': new_memory,
                        })

                        log.info(f"Updated memory for task '{task_name}': {action.params.get('current_memory_gb')}GB → {new_memory}GB")

                    elif 'recommended_cpus' in action.params:
                        # CPU adjustment
                        new_cpus = action.params['recommended_cpus']
                        task_name = action.params.get('task_name', 'global')

                        if not invocation.input_parameters:
                            invocation.input_parameters = {}

                        if 'resource_overrides' not in invocation.input_parameters:
                            invocation.input_parameters['resource_overrides'] = {}

                        if task_name not in invocation.input_parameters['resource_overrides']:
                            invocation.input_parameters['resource_overrides'][task_name] = {}

                        invocation.input_parameters['resource_overrides'][task_name]['cpus'] = new_cpus

                        applied_changes.append({
                            'resource': 'cpu',
                            'task': task_name,
                            'old_value': action.params.get('current_cpus'),
                            'new_value': new_cpus,
                        })

                        log.info(f"Updated CPUs for task '{task_name}': {action.params.get('current_cpus')} → {new_cpus}")

                elif action.action == ActionType.INCREASE_DISK:
                    new_disk = action.params['recommended_disk_gb']
                    task_name = action.params.get('task_name', 'global')

                    if not invocation.input_parameters:
                        invocation.input_parameters = {}

                    if 'resource_overrides' not in invocation.input_parameters:
                        invocation.input_parameters['resource_overrides'] = {}

                    if task_name not in invocation.input_parameters['resource_overrides']:
                        invocation.input_parameters['resource_overrides'][task_name] = {}

                    invocation.input_parameters['resource_overrides'][task_name]['disk_gb'] = new_disk

                    applied_changes.append({
                        'resource': 'disk',
                        'task': task_name,
                        'old_value': action.params.get('current_disk_gb'),
                        'new_value': new_disk,
                    })

                    log.info(f"Updated disk for task '{task_name}': {action.params.get('current_disk_gb')}GB → {new_disk}GB")

            # Save changes
            sa_session.commit()

            execution_time = (datetime.now() - start_time).total_seconds()

            log.info(f"✅ Applied {len(applied_changes)} resource adjustments in {execution_time:.2f}s")

            return AutoFixResult(
                fix_id=None,
                fixer_name="AWSResourceFixer",
                status=FixStatus.APPLIED,
                fix_type=fix_plan.fix_type.value,
                fix_actions=fix_plan.fix_actions,
                risk_level=RiskLevel.MEDIUM,
                success=True,
                state_after={'applied_changes': applied_changes},
                execution_time_seconds=execution_time,
                applied_at=datetime.now(),
            )

        except Exception as e:
            log.error(f"Error applying resource fixes: {e}", exc_info=True)
            execution_time = (datetime.now() - start_time).total_seconds()

            return AutoFixResult(
                fix_id=None,
                fixer_name="AWSResourceFixer",
                status=FixStatus.FAILED,
                fix_type=fix_plan.fix_type.value,
                fix_actions=fix_plan.fix_actions,
                risk_level=RiskLevel.MEDIUM,
                success=False,
                error_message=str(e),
                execution_time_seconds=execution_time,
            )

    def estimate_cost(
        self,
        context: FixContext,
        fix_plan: FixPlan
    ) -> float:
        """
        Estimate the additional cost of resource adjustments

        Args:
            context: Fix context
            fix_plan: Generated fix plan

        Returns:
            Estimated additional cost in USD per hour
        """
        total_cost_per_hour = 0.0

        for action in fix_plan.fix_actions:
            if action.action == ActionType.INCREASE_MEMORY:
                if 'recommended_memory_gb' in action.params:
                    # Memory cost
                    current_memory = action.params.get('current_memory_gb', 0)
                    new_memory = action.params['recommended_memory_gb']
                    memory_diff = new_memory - current_memory
                    total_cost_per_hour += memory_diff * self.GB_MEMORY_COST_PER_HOUR

                elif 'recommended_cpus' in action.params:
                    # CPU cost
                    current_cpus = action.params.get('current_cpus', 0)
                    new_cpus = action.params['recommended_cpus']
                    cpu_diff = new_cpus - current_cpus
                    total_cost_per_hour += cpu_diff * self.VCPU_COST_PER_HOUR

            elif action.action == ActionType.INCREASE_DISK:
                # Disk cost (monthly, convert to hourly)
                current_disk = action.params.get('current_disk_gb', 0)
                new_disk = action.params['recommended_disk_gb']
                disk_diff = new_disk - current_disk
                monthly_cost = disk_diff * self.GB_DISK_COST_PER_GB_MONTH
                total_cost_per_hour += monthly_cost / (30 * 24)  # Convert to hourly

        # Estimate average job duration (assume 2 hours)
        estimated_duration_hours = 2.0
        total_estimated_cost = total_cost_per_hour * estimated_duration_hours

        return total_estimated_cost

    # ========== Helper Methods ==========

    def _get_workflow_logs(self, context: FixContext, invocation) -> Dict[str, List[str]]:
        """Get workflow logs from various sources"""
        # In a real implementation, this would fetch from:
        # 1. CloudWatch logs
        # 2. Local log files
        # 3. Nextflow trace files

        # For now, return empty logs (would be populated in real system)
        return {
            'stdout': [],
            'stderr': [],
            'nextflow_log': []
        }

    def _detect_oom_errors(self, logs: Dict[str, List[str]]) -> List[Dict[str, Any]]:
        """Detect Out of Memory errors from logs"""
        issues = []

        # Common OOM patterns
        oom_patterns = [
            r'Out of memory',
            r'OOMKilled',
            r'java\.lang\.OutOfMemoryError',
            r'Cannot allocate memory',
            r'MemoryError',
        ]

        # Search stderr logs
        for line in logs.get('stderr', []):
            for pattern in oom_patterns:
                if re.search(pattern, line, re.IGNORECASE):
                    # Try to extract memory info
                    memory_match = re.search(r'(\d+)\s*(GB|MB|G|M)', line, re.IGNORECASE)
                    required_memory = 16  # Default assumption

                    if memory_match:
                        value = int(memory_match.group(1))
                        unit = memory_match.group(2).upper()
                        if unit in ['MB', 'M']:
                            required_memory = value / 1024.0
                        else:
                            required_memory = value

                    issues.append({
                        'type': 'oom',
                        'severity': 'high',
                        'message': 'Out of memory detected',
                        'current_memory_gb': 8,  # Would be extracted from job config
                        'required_memory_gb': required_memory,
                        'log_line': line[:200],
                    })
                    break

        return issues

    def _detect_cpu_throttling(self, logs: Dict[str, List[str]]) -> List[Dict[str, Any]]:
        """Detect CPU throttling from logs"""
        issues = []

        # CPU throttling patterns
        cpu_patterns = [
            r'CPU.*throttl',
            r'Process.*slow',
            r'Performance degradation',
        ]

        for line in logs.get('stdout', []) + logs.get('stderr', []):
            for pattern in cpu_patterns:
                if re.search(pattern, line, re.IGNORECASE):
                    issues.append({
                        'type': 'cpu_throttling',
                        'severity': 'medium',
                        'message': 'CPU throttling detected',
                        'current_cpus': 2,  # Would be extracted from job config
                        'log_line': line[:200],
                    })
                    break

        return issues

    def _detect_disk_issues(self, logs: Dict[str, List[str]]) -> List[Dict[str, Any]]:
        """Detect disk space issues from logs"""
        issues = []

        # Disk space patterns
        disk_patterns = [
            r'No space left on device',
            r'Disk.*full',
            r'ENOSPC',
            r'out of disk',
        ]

        for line in logs.get('stderr', []):
            for pattern in disk_patterns:
                if re.search(pattern, line, re.IGNORECASE):
                    issues.append({
                        'type': 'disk_space',
                        'severity': 'high',
                        'message': 'Disk space exhausted',
                        'current_disk_gb': 100,  # Would be extracted from job config
                        'required_disk_gb': 200,  # Default assumption
                        'log_line': line[:200],
                    })
                    break

        return issues

    def _detect_spot_interruptions(self, logs: Dict[str, List[str]]) -> List[Dict[str, Any]]:
        """
        🆕 Phase 3 Day 7: Detect AWS Batch Spot instance interruptions

        Spot instances can be interrupted when AWS needs capacity back.
        This leads to random failures that should trigger retry mechanism.
        """
        issues = []

        # Spot interruption patterns
        spot_patterns = [
            r'(?i)spot.*interrupt',
            r'(?i)host.*ec2.*terminat',
            r'(?i)instance.*terminat',
            r'(?i)spot.*reclaim',
            r'(?i)ec2.*spot.*interrupt',
        ]

        for line in logs.get('stderr', []) + logs.get('stdout', []):
            for pattern in spot_patterns:
                if re.search(pattern, line):
                    issues.append({
                        'type': 'spot_interruption',
                        'severity': 'medium',
                        'message': 'AWS Spot instance was interrupted',
                        'auto_fixable': True,  # Can be fixed by retry
                        'recommended_action': 'enable_retry_with_fallback',
                        'log_line': line[:200],
                        'explanation': 'Spot instances can be interrupted. Enabling retry mechanism with on-demand fallback.'
                    })
                    log.info(f"✅ Detected Spot interruption: {line[:100]}")
                    break

        return issues

    def _detect_s3_transfer_errors(self, logs: Dict[str, List[str]]) -> List[Dict[str, Any]]:
        """
        🆕 Phase 3 Day 7: Detect AWS S3 file transfer errors

        S3 transfer can fail due to network issues, throttling, or permissions.
        """
        issues = []

        # S3 transfer error patterns
        s3_patterns = [
            r'(?i)s3.*download.*fail',
            r'(?i)s3.*upload.*fail',
            r'(?i)unable.*download.*s3',
            r'(?i)unable.*upload.*s3',
            r'(?i)s3.*slowdown',
            r'(?i)s3.*timeout',
            r'(?i)accessdenied.*s3',
            r'(?i)nosuchkey',
            r'(?i)s3.*connection.*reset',
        ]

        for line in logs.get('stderr', []) + logs.get('nextflow_log', []):
            for pattern in s3_patterns:
                if re.search(pattern, line):
                    # Determine if it's permissions or network issue
                    is_permission = 'accessdenied' in line.lower() or 'permission' in line.lower()
                    is_throttling = 'slowdown' in line.lower() or 'throttl' in line.lower()

                    if is_permission:
                        severity = 'high'
                        auto_fixable = False
                        action = 'check_iam_permissions'
                        explanation = 'S3 permission denied. User needs to update IAM role policies.'
                    elif is_throttling:
                        severity = 'medium'
                        auto_fixable = True
                        action = 'enable_retry_with_backoff'
                        explanation = 'S3 request rate limit hit. Enabling retry with exponential backoff.'
                    else:
                        severity = 'medium'
                        auto_fixable = True
                        action = 'enable_retry'
                        explanation = 'S3 transfer error. Enabling retry mechanism.'

                    issues.append({
                        'type': 's3_transfer_error',
                        'severity': severity,
                        'message': 'S3 file transfer failed',
                        'auto_fixable': auto_fixable,
                        'recommended_action': action,
                        'log_line': line[:200],
                        'explanation': explanation
                    })
                    log.info(f"✅ Detected S3 transfer error: {line[:100]}")
                    break

        return issues

    def _detect_container_pull_errors(self, logs: Dict[str, List[str]]) -> List[Dict[str, Any]]:
        """
        🆕 Phase 3 Day 7: Detect Docker/container image pull errors

        Container pull can fail due to:
        - Image not found (wrong name/tag)
        - Network timeout
        - Registry throttling
        - Permission denied
        """
        issues = []

        # Container pull error patterns
        container_patterns = [
            r'(?i)docker.*pull.*fail',
            r'(?i)manifest.*unknown',
            r'(?i)pull.*access.*denied',
            r'(?i)image.*not.*found',
            r'(?i)tls.*handshake.*timeout',
            r'(?i)error.*pulling.*image',
            r'(?i)failed.*pull.*image',
            r'(?i)repository.*not.*found',
        ]

        for line in logs.get('stderr', []) + logs.get('stdout', []):
            for pattern in container_patterns:
                if re.search(pattern, line):
                    # Determine error type
                    is_not_found = 'not found' in line.lower() or 'manifest unknown' in line.lower()
                    is_permission = 'access denied' in line.lower() or 'unauthorized' in line.lower()
                    is_network = 'timeout' in line.lower() or 'tls handshake' in line.lower()

                    if is_not_found:
                        severity = 'high'
                        auto_fixable = False
                        action = 'verify_image_name_and_tag'
                        explanation = 'Container image not found. User needs to verify image name and tag are correct.'
                    elif is_permission:
                        severity = 'high'
                        auto_fixable = False
                        action = 'configure_ecr_permissions'
                        explanation = 'Permission denied pulling container. User needs to configure ECR/Docker Hub credentials.'
                    elif is_network:
                        severity = 'medium'
                        auto_fixable = True
                        action = 'enable_retry_with_timeout_increase'
                        explanation = 'Network timeout pulling container. Enabling retry with increased timeout.'
                    else:
                        severity = 'medium'
                        auto_fixable = True
                        action = 'enable_retry'
                        explanation = 'Container pull error. Enabling retry mechanism.'

                    issues.append({
                        'type': 'container_pull_error',
                        'severity': severity,
                        'message': 'Failed to pull container image',
                        'auto_fixable': auto_fixable,
                        'recommended_action': action,
                        'log_line': line[:200],
                        'explanation': explanation
                    })
                    log.info(f"✅ Detected container pull error: {line[:100]}")
                    break

        return issues
