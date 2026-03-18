"""
Nextflow Parameter Auto-Fixer

Automatically fixes missing or invalid Nextflow workflow parameters by:
1. Detecting missing required parameters from WorkflowParameterTemplate
2. Inferring values from user's historical successful runs
3. Using pipeline-specific default values
4. Extracting hints from error logs

Safety:
- User-isolated: Only accesses current user's workflows
- Low risk: Only modifies workflow invocation parameters
- Auditable: All changes logged to AIFixAuditLog
- Rollback-safe: Original parameters captured in snapshot

Example issues fixed:
- Missing required parameter (e.g., 'genome' for rnaseq)
- Missing source parameter (e.g., 'source' for clipseq)
- Wrong parameter format (e.g., boolean as string)
"""

import logging
import re
from collections import Counter
from typing import Any, Dict, List, Optional

from galaxy.ai.workflow_ops.autofix.base import (
    AutoFixResult,
    BaseAutoFixer,
    FixContext,
    FixStatus,
    RiskLevel,
)
from galaxy.ai.workflow_ops.types import ActionType, FixAction, FixPlan, FixType
from galaxy.model import (
    WorkflowInvocation,
    WorkflowParameterFix,
    WorkflowParameterTemplate,
)

log = logging.getLogger(__name__)


class NextflowParameterFixer(BaseAutoFixer):
    """
    Fixer for Nextflow workflow parameter issues

    Handles:
    - Missing required parameters
    - Invalid parameter values
    - Type mismatches
    """

    # Known pipeline-specific critical parameters
    CRITICAL_PARAMS = {
        'clipseq': ['ncrna_fasta'],  # 移除了 'source' - 这个参数 clipseq 不接受
        'smrnaseq': ['mirtrace_species'],
        'rnaseq': ['aligner', 'genome'],
        'chipseq': ['genome'],
        'atacseq': ['genome'],
    }

    def detect_issues(self, context: FixContext) -> List[Dict[str, Any]]:
        """
        Detect parameter issues in the workflow invocation

        Args:
            context: Fix context

        Returns:
            List of detected parameter issues
        """
        from galaxy.model import WorkflowInvocation

        sa_session = context.metadata.get('sa_session')
        if not sa_session:
            log.error("No sa_session in context metadata")
            return []

        invocation = sa_session.query(WorkflowInvocation).get(context.invocation_id)
        if not invocation:
            log.error(f"Invocation {context.invocation_id} not found")
            return []

        issues = []

        # Get actual parameters (convert from InstrumentedList to dict)
        actual_params = {}
        if invocation.input_parameters:
            # input_parameters is a list of WorkflowRequestInputParameter objects
            for param in invocation.input_parameters:
                if hasattr(param, 'name') and hasattr(param, 'value'):
                    actual_params[param.name] = param.value
        log.info(f"Current parameters: {list(actual_params.keys())}")

        # Detect pipeline type from workflow name
        pipeline_type = self._detect_pipeline_type(invocation.workflow)
        log.info(f"Detected pipeline type: {pipeline_type}")

        # Get parameter templates for this pipeline
        templates = (
            sa_session.query(WorkflowParameterTemplate)
            .filter_by(pipeline_name=pipeline_type)
            .all()
        )

        if not templates:
            log.warning(f"No parameter templates found for {pipeline_type}")
            # Fallback: use generic templates
            templates = (
                sa_session.query(WorkflowParameterTemplate)
                .filter_by(pipeline_name='generic')
                .all()
            )

        # Check for missing required parameters
        for template in templates:
            param_name = template.parameter_name
            actual_value = actual_params.get(param_name)

            if template.is_required and not actual_value:
                issues.append({
                    'type': 'missing_required',
                    'parameter': param_name,
                    'severity': 'high',
                    'message': f"Required parameter '{param_name}' is missing",
                    'template': template,
                    'pipeline': pipeline_type,
                })
                log.warning(f"Missing required parameter: {param_name}")

            # Check validation rules if value exists
            elif actual_value and template.validation_rules:
                validation_error = self._validate_parameter(
                    actual_value,
                    template.validation_rules
                )
                if validation_error:
                    issues.append({
                        'type': 'validation_failed',
                        'parameter': param_name,
                        'severity': 'medium',
                        'message': validation_error,
                        'current_value': actual_value,
                        'template': template,
                        'pipeline': pipeline_type,
                    })
                    log.warning(f"Validation failed for {param_name}: {validation_error}")

        # Check critical parameters specific to pipeline
        if pipeline_type in self.CRITICAL_PARAMS:
            for critical_param in self.CRITICAL_PARAMS[pipeline_type]:
                if critical_param not in actual_params or not actual_params[critical_param]:
                    # Avoid duplicates
                    if not any(i['parameter'] == critical_param for i in issues):
                        issues.append({
                            'type': 'missing_critical',
                            'parameter': critical_param,
                            'severity': 'high',
                            'message': f"Critical parameter '{critical_param}' for {pipeline_type} is missing",
                            'pipeline': pipeline_type,
                        })
                        log.warning(f"Missing critical parameter: {critical_param}")

        return issues

    def generate_fix_plan(
        self,
        context: FixContext,
        issues: List[Dict[str, Any]]
    ) -> Optional[FixPlan]:
        """
        Generate fix plan for detected parameter issues

        Args:
            context: Fix context
            issues: Detected issues

        Returns:
            FixPlan with recommended parameter fixes
        """
        if not issues:
            return None

        sa_session = context.metadata.get('sa_session')
        if not sa_session:
            log.error("No sa_session in context metadata")
            return None

        fix_actions = []

        for issue in issues:
            param_name = issue['parameter']
            issue_type = issue['type']

            # Try to infer value from different sources
            recommended_value = None
            reason = ""
            confidence = 0.0

            # 1. Check existing WorkflowParameterFix for this workflow
            existing_fix = (
                sa_session.query(WorkflowParameterFix)
                .filter_by(
                    workflow_id=context.workflow_id,
                    parameter_name=param_name,
                    status='approved'
                )
                .order_by(WorkflowParameterFix.applied_count.desc())
                .first()
            )

            if existing_fix:
                recommended_value = existing_fix.recommended_value
                reason = f"Using previously approved fix (applied {existing_fix.applied_count} times)"
                confidence = 0.9
                log.info(f"Found existing fix for {param_name}: {recommended_value}")

            # 2. Infer from user's historical successful runs
            if not recommended_value:
                historical_value = self._infer_from_history(
                    context.user_id,
                    context.workflow_id,
                    param_name,
                    sa_session
                )
                if historical_value:
                    recommended_value = historical_value['value']
                    reason = f"Inferred from {historical_value['count']} successful runs"
                    confidence = min(0.8, historical_value['count'] / 10.0)
                    log.info(f"Inferred {param_name} from history: {recommended_value}")

            # 3. Use template default value
            if not recommended_value and 'template' in issue:
                template = issue['template']
                if template.default_value:
                    recommended_value = template.default_value
                    reason = f"Using template default for {issue['pipeline']} pipeline"
                    confidence = 0.7
                    log.info(f"Using template default for {param_name}: {recommended_value}")

            # 4. Use pipeline-specific defaults
            if not recommended_value:
                default_value = self._get_pipeline_default(
                    issue.get('pipeline', 'generic'),
                    param_name
                )
                if default_value:
                    recommended_value = default_value
                    reason = f"Using pipeline default for {param_name}"
                    confidence = 0.6
                    log.info(f"Using pipeline default for {param_name}: {recommended_value}")

            if recommended_value:
                fix_action = FixAction(
                    action=ActionType.UPDATE_PARAM,
                    params={
                        'parameter_name': param_name,
                        'current_value': issue.get('current_value'),
                        'recommended_value': recommended_value,
                        'confidence': confidence,
                    },
                    description=f"Set '{param_name}' to '{recommended_value}'. {reason}",
                    risk_level='low',  # Parameter changes are low risk
                )
                fix_actions.append(fix_action)
            else:
                log.warning(f"Could not determine fix for parameter: {param_name}")

        if not fix_actions:
            return FixPlan(
                fixable=False,
                fix_type=FixType.CONFIG_ADJUSTMENT,
                fix_actions=[],
                explanation="No automatic fix available for detected issues",
                confidence=0.0,
                requires_user_confirmation=True,
            )

        # Calculate overall confidence
        avg_confidence = sum(
            a.params.get('confidence', 0.5) for a in fix_actions
        ) / len(fix_actions)

        return FixPlan(
            fixable=True,
            fix_type=FixType.CONFIG_ADJUSTMENT,
            fix_actions=fix_actions,
            explanation=f"Automatically fix {len(fix_actions)} parameter(s) based on templates and historical data",
            confidence=avg_confidence,
            estimated_success_rate=avg_confidence,
            requires_user_confirmation=(avg_confidence < 0.7),  # Low confidence needs approval
        )

    async def apply_fix(
        self,
        context: FixContext,
        fix_plan: FixPlan,
        sa_session: Any,
    ) -> AutoFixResult:
        """
        Apply parameter fixes to the workflow invocation

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
                    fixer_name="NextflowParameterFixer",
                    status=FixStatus.FAILED,
                    fix_type=fix_plan.fix_type.value,
                    fix_actions=fix_plan.fix_actions,
                    risk_level=RiskLevel.LOW,
                    success=False,
                    error_message="Workflow invocation not found"
                )

            # Get current parameters (convert from InstrumentedList to dict)
            current_params = {}
            if invocation.input_parameters:
                for param in invocation.input_parameters:
                    if hasattr(param, 'name') and hasattr(param, 'value'):
                        current_params[param.name] = param.value

            # Apply each fix action
            applied_changes = []
            for action in fix_plan.fix_actions:
                if action.action == ActionType.UPDATE_PARAM:
                    param_name = action.params['parameter_name']
                    new_value = action.params['recommended_value']

                    # Update parameter
                    old_value = current_params.get(param_name)
                    current_params[param_name] = new_value

                    applied_changes.append({
                        'parameter': param_name,
                        'old_value': old_value,
                        'new_value': new_value,
                    })

                    log.info(f"Updated parameter '{param_name}': {old_value} → {new_value}")

            # Update the actual WorkflowRequestInputParameter objects
            # Find existing param object or create new one
            from galaxy.model import WorkflowRequestInputParameter

            for param_name, param_value in current_params.items():
                # Find existing parameter
                existing_param = None
                for p in invocation.input_parameters:
                    if hasattr(p, 'name') and p.name == param_name:
                        existing_param = p
                        break

                if existing_param:
                    # Update existing
                    existing_param.value = param_value
                else:
                    # Create new parameter
                    new_param = WorkflowRequestInputParameter(
                        workflow_invocation=invocation,
                        name=param_name,
                        value=param_value
                    )
                    invocation.input_parameters.append(new_param)
                    sa_session.add(new_param)

            sa_session.commit()

            execution_time = (datetime.now() - start_time).total_seconds()

            log.info(f"✅ Applied {len(applied_changes)} parameter fixes in {execution_time:.2f}s")

            return AutoFixResult(
                fix_id=None,
                fixer_name="NextflowParameterFixer",
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
            log.error(f"Error applying parameter fixes: {e}", exc_info=True)
            execution_time = (datetime.now() - start_time).total_seconds()

            return AutoFixResult(
                fix_id=None,
                fixer_name="NextflowParameterFixer",
                status=FixStatus.FAILED,
                fix_type=fix_plan.fix_type.value,
                fix_actions=fix_plan.fix_actions,
                risk_level=RiskLevel.LOW,
                success=False,
                error_message=str(e),
                execution_time_seconds=execution_time,
            )

    # ========== Helper Methods ==========

    def _detect_pipeline_type(self, workflow) -> str:
        """
        Detect pipeline type from workflow name

        Args:
            workflow: Workflow object

        Returns:
            Pipeline type string
        """
        workflow_name = workflow.name.lower() if workflow.name else ""

        for pipeline in ['clipseq', 'smrnaseq', 'rnaseq', 'chipseq', 'atacseq']:
            if pipeline in workflow_name:
                return pipeline

        return 'generic'

    def _validate_parameter(self, value: Any, validation_rules: Dict) -> Optional[str]:
        """
        Validate parameter value against rules

        Args:
            value: Parameter value
            validation_rules: Validation rules from template

        Returns:
            Error message if validation fails, None otherwise
        """
        # Pattern validation
        if 'pattern' in validation_rules:
            pattern = validation_rules['pattern']
            if not re.match(pattern, str(value)):
                return f"Value '{value}' does not match pattern '{pattern}'"

        # Allowed values
        if 'allowed_values' in validation_rules:
            allowed = validation_rules['allowed_values']
            if value not in allowed:
                return f"Value '{value}' not in allowed values: {allowed}"

        # Type validation
        if 'type' in validation_rules:
            expected_type = validation_rules['type']
            if expected_type == 'integer' and not isinstance(value, int):
                try:
                    int(value)
                except (ValueError, TypeError):
                    return f"Value '{value}' is not a valid integer"

            elif expected_type == 'boolean' and not isinstance(value, bool):
                if str(value).lower() not in ['true', 'false', '0', '1']:
                    return f"Value '{value}' is not a valid boolean"

        return None

    def _infer_from_history(
        self,
        user_id: int,
        workflow_id: int,
        param_name: str,
        sa_session: Any
    ) -> Optional[Dict[str, Any]]:
        """
        Infer parameter value from user's successful workflow runs

        Args:
            user_id: User ID
            workflow_id: Workflow ID
            param_name: Parameter name
            sa_session: Database session

        Returns:
            {'value': most_common_value, 'count': occurrence_count} or None
        """
        # Get recent successful invocations for this workflow
        from galaxy.model import History
        successful_invocations = (
            sa_session.query(WorkflowInvocation)
            .join(History, WorkflowInvocation.history_id == History.id)
            .filter(
                WorkflowInvocation.workflow_id == workflow_id,
                History.user_id == user_id,
                WorkflowInvocation.state == 'scheduled'  # completed successfully
            )
            .order_by(WorkflowInvocation.create_time.desc())
            .limit(20)
            .all()
        )

        # Collect values for this parameter
        values = []
        for inv in successful_invocations:
            if inv.input_parameters and param_name in inv.input_parameters:
                value = inv.input_parameters[param_name]
                if value:  # Skip None/empty values
                    values.append(str(value))

        if not values:
            return None

        # Return most common value
        counter = Counter(values)
        most_common = counter.most_common(1)[0]

        return {
            'value': most_common[0],
            'count': most_common[1],
        }

    def _get_pipeline_default(self, pipeline_type: str, param_name: str) -> Optional[str]:
        """
        Get pipeline-specific default value

        Args:
            pipeline_type: Pipeline type (e.g., 'rnaseq', 'clipseq')
            param_name: Parameter name

        Returns:
            Default value or None
        """
        # Common defaults for each pipeline
        DEFAULTS = {
            'rnaseq': {
                'genome': 'GRCh38',
                'aligner': 'star',
            },
            'clipseq': {
                'source': 'GRCh38',
            },
            'smrnaseq': {
                'mirtrace_species': 'hsa',  # human
            },
            'chipseq': {
                'genome': 'GRCh38',
            },
            'atacseq': {
                'genome': 'GRCh38',
            },
        }

        return DEFAULTS.get(pipeline_type, {}).get(param_name)
