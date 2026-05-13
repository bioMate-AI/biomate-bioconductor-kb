"""
Auto-Fix Orchestrator

Coordinates the entire fix lifecycle:
1. Check permissions
2. Detect issues
3. Generate fix plan
4. Evaluate risk and cost
5. Request approval (if needed)
6. Apply fix with rollback support
7. Log to audit trail
"""

import logging
from datetime import datetime
from typing import Any, Dict, List, Optional

from galaxy.ai.workflow_ops.autofix.base import (
    AutoFixResult,
    BaseAutoFixer,
    FixContext,
    FixStatus,
    RiskLevel,
    StateSnapshot,
)
# 🆕 Phase 3.3: Import validation module
from galaxy.ai.workflow_ops.autofix.validation import (
    FixSimulator,
    FixSuccessTracker,
    FixValidator,
)
# Galaxy ORM models are imported lazily inside methods so the module can load
# even when the tables (AIFixAuditLog, UserCloudPreferences, UserResourceUsage)
# have not yet been migrated into BioMate's schema. All consumers tolerate
# None / missing rows via documented defaults.

log = logging.getLogger(__name__)


class AutoFixOrchestrator:
    """
    Orchestrates the auto-fix workflow with safety guarantees

    This class coordinates all fixers and ensures:
    - User isolation
    - Risk-based approval
    - Cost control
    - Audit logging
    - Rollback on failure

    Example:
        >>> orchestrator = AutoFixOrchestrator(trans)
        >>> fixer = NextflowParameterFixer()
        >>> result = await orchestrator.run_fixer(
        ...     invocation_id=123,
        ...     fixer=fixer,
        ...     auto_approve_low_risk=True
        ... )
    """

    def __init__(self, trans):
        """
        Initialize orchestrator

        Args:
            trans: Galaxy transaction context (provides user, sa_session, etc.)
        """
        if not trans.user:
            raise ValueError("AutoFix requires authenticated user - trans.user is None")

        self.trans = trans
        self.sa_session = trans.sa_session
        self.user_id = trans.user.id

        # 🆕 Phase 3.3: Initialize validation components
        self.validator = FixValidator(self.sa_session)
        self.success_tracker = FixSuccessTracker(self.sa_session)
        self.simulator = FixSimulator(self.sa_session)

    def _build_fix_context(self, invocation_id: int) -> FixContext:
        """
        Build FixContext from invocation and user preferences

        Args:
            invocation_id: Workflow invocation ID

        Returns:
            FixContext with user preferences and budget info
        """
        from galaxy.model import WorkflowInvocation
        invocation = self.sa_session.query(WorkflowInvocation).get(invocation_id)
        if not invocation:
            raise ValueError(f"Invocation {invocation_id} not found")

        # Get user preferences (table may not exist yet in BioMate)
        try:
            from galaxy.model import UserCloudPreferences
            user_prefs = (
                self.sa_session.query(UserCloudPreferences)
                .filter_by(user_id=self.user_id)
                .first()
            )
        except (ImportError, Exception) as e:
            log.debug("UserCloudPreferences unavailable, using defaults: %s", e)
            user_prefs = None

        # Get today's usage for budget tracking
        from datetime import date
        try:
            from galaxy.model import UserResourceUsage
            today_usage = (
                self.sa_session.query(UserResourceUsage)
                .filter_by(user_id=self.user_id, usage_date=date.today())
                .first()
            )
        except (ImportError, Exception) as e:
            log.debug("UserResourceUsage unavailable, using defaults: %s", e)
            today_usage = None

        # Calculate remaining budgets
        if user_prefs and today_usage:
            daily_remaining = user_prefs.daily_budget_usd - today_usage.estimated_total_cost
            monthly_remaining = user_prefs.monthly_budget_usd - self._get_monthly_cost()
        else:
            # Defaults if no preferences set
            daily_remaining = 50.0
            monthly_remaining = 1000.0

        return FixContext(
            user_id=self.user_id,
            invocation_id=invocation_id,
            workflow_id=invocation.workflow_id,
            ai_auto_fix_enabled=user_prefs.ai_auto_fix_enabled if user_prefs else True,
            ai_auto_fix_mode=user_prefs.ai_auto_fix_mode if user_prefs else "safe",
            ai_require_approval_for_cost=user_prefs.ai_require_approval_for_cost if user_prefs else 10.0,
            max_memory_gb=user_prefs.max_memory_gb if user_prefs else 64,
            max_cpus=user_prefs.max_cpus if user_prefs else 16,
            max_concurrent_jobs=user_prefs.max_concurrent_jobs if user_prefs else 10,
            daily_budget_remaining=daily_remaining,
            monthly_budget_remaining=monthly_remaining,
        )

    def _get_monthly_cost(self) -> float:
        """Get total cost for the current month"""
        from datetime import date
        from sqlalchemy import func, extract

        try:
            from galaxy.model import UserResourceUsage
        except ImportError:
            return 0.0

        try:
            result = (
                self.sa_session.query(func.sum(UserResourceUsage.estimated_total_cost))
                .filter(
                    UserResourceUsage.user_id == self.user_id,
                    extract('month', UserResourceUsage.usage_date) == date.today().month,
                    extract('year', UserResourceUsage.usage_date) == date.today().year
                )
                .scalar()
            )
            return result or 0.0
        except Exception as e:
            log.debug("Monthly cost query failed: %s", e)
            return 0.0

    async def run_fixer(
        self,
        invocation_id: int,
        fixer: BaseAutoFixer,
        auto_approve_low_risk: bool = True,
        force_apply: bool = False,
    ) -> AutoFixResult:
        """
        Run a single fixer on a workflow invocation

        This is the main entry point for applying fixes.

        Workflow:
        1. Build context with user preferences and budgets
        2. Check permissions (user isolation)
        3. Detect issues using the fixer
        4. Generate fix plan
        5. Evaluate risk and cost
        6. Check budget availability
        7. Determine if approval needed
        8. Capture state snapshot
        9. Apply fix with error handling
        10. Log to audit trail
        11. Rollback on failure

        Args:
            invocation_id: Workflow invocation ID to fix
            fixer: The fixer instance to use
            auto_approve_low_risk: Auto-approve low-risk fixes (default: True)
            force_apply: Skip approval checks (USE WITH CAUTION, mainly for testing)

        Returns:
            AutoFixResult with execution outcome

        Raises:
            ValueError: Invalid invocation ID
            PermissionError: User doesn't have permission
        """
        log.info(f"🔧 Running fixer {fixer.name} on invocation {invocation_id}")

        # Step 1: Build context
        context = self._build_fix_context(invocation_id)
        # Add sa_session and app_config to context metadata for fixer access
        context.metadata['sa_session'] = self.sa_session
        context.metadata['app_config'] = self.trans.app.config

        # Step 2: Check permissions
        allowed, error_msg = fixer.check_permissions(context, self.sa_session)
        if not allowed:
            log.error(f"❌ Permission denied: {error_msg}")
            raise PermissionError(error_msg)

        log.info(f"✅ Permission check passed")

        # Step 3: Detect issues
        issues = fixer.detect_issues(context)
        if not issues:
            log.info(f"ℹ️  No issues detected by {fixer.name}")
            return AutoFixResult(
                fix_id=None,
                fixer_name=fixer.name if hasattr(fixer, 'name') else fixer.__class__.__name__,
                status=FixStatus.PENDING,
                fix_type=fixer.name,
                fix_actions=[],
                risk_level=RiskLevel.LOW,
                success=True,
                error_message="No issues detected"
            )

        log.info(f"🔍 Detected {len(issues)} issues: {[i.get('type', 'unknown') for i in issues]}")

        # Step 4: Generate fix plan
        fix_plan = fixer.generate_fix_plan(context, issues)
        if not fix_plan or not fix_plan.fixable:
            log.warning(f"⚠️  No fix plan generated (not fixable)")

            # 🆕 收集 User Guidance（如果存在）
            user_guidance_list = []
            for issue in issues:
                if issue.get('user_guidance'):
                    user_guidance_list.append({
                        'issue_type': issue.get('type'),
                        'severity': issue.get('severity'),
                        'description': issue.get('description'),
                        'guidance': issue.get('user_guidance'),
                    })

            log.info(f"📋 Collected {len(user_guidance_list)} User Guidance entries")

            # 🔧 FIX: Pass through fix_actions even if not fixable (for DIAGNOSTIC actions)
            fix_actions_to_return = []
            if fix_plan and fix_plan.fix_actions:
                fix_actions_to_return = fix_plan.fix_actions
                log.info(f"📋 Including {len(fix_actions_to_return)} diagnostic/informational actions")

            return AutoFixResult(
                fix_id=None,
                fixer_name=fixer.name if hasattr(fixer, 'name') else fixer.__class__.__name__,
                status=FixStatus.PENDING,
                fix_type=fixer.name,
                fix_actions=fix_actions_to_return,  # 🔧 FIX: Include DIAGNOSTIC actions
                risk_level=RiskLevel.LOW,
                success=False,
                error_message="Issues not auto-fixable",
                original_issue={  # 🆕 将 User Guidance 放入 original_issue
                    'user_guidance': user_guidance_list,
                    'issues': issues,
                }
            )

        log.info(f"📋 Generated fix plan with {len(fix_plan.fix_actions)} actions")

        # 🆕 Phase 3.3: Pre-validate fix plan
        is_valid, validation_error = self.validator.pre_validate(context, fix_plan)
        if not is_valid:
            log.error(f"❌ Pre-validation failed: {validation_error}")

            # 🔑 收集 User Guidance（如果存在）
            user_guidance_list = []
            for issue in issues:
                if issue.get('user_guidance'):
                    user_guidance_list.append({
                        'issue_type': issue.get('type'),
                        'severity': issue.get('severity'),
                        'description': issue.get('description'),
                        'guidance': issue.get('user_guidance'),
                    })
            log.info(f"📋 Collected {len(user_guidance_list)} User Guidance entries on pre-validation failure")

            # 🔑 即使 pre-validation 失败，也保留 validated_issues 和 user_guidance
            return AutoFixResult(
                fix_id=None,
                fixer_name=fixer.name if hasattr(fixer, 'name') else fixer.__class__.__name__,
                status=FixStatus.FAILED,
                fix_type=fixer.name,
                fix_actions=fix_plan.fix_actions,
                risk_level=RiskLevel.LOW,
                success=False,
                error_message=f"Pre-validation failed: {validation_error}",
                original_issue={  # 🆕 保留 User Guidance 和 issues 信息
                    'user_guidance': user_guidance_list,
                    'issues': issues,
                }
            )

        # 🆕 Phase 3.3: Simulate fix to predict outcome
        likely_success, sim_message = self.simulator.simulate_parameter_fix(context, fix_plan)
        if not likely_success:
            log.warning(f"⚠️  Simulation predicts failure: {sim_message}")
            # Continue anyway, but log the warning

        # 🆕 Phase 3.3: Estimate fix impact
        impact = self.simulator.estimate_fix_impact(context, fix_plan)
        log.info(f"📊 Estimated impact: +{impact['resource_changes']['memory_delta_gb']:.1f}GB memory, "
                 f"${impact['estimated_cost_change_usd']:.2f} cost change")

        # Step 5: Evaluate risk and cost
        risk_level = fixer.evaluate_risk(context, fix_plan)
        estimated_cost = fixer.estimate_cost(context, fix_plan)

        log.info(f"⚖️  Risk: {risk_level.value}, Estimated cost: ${estimated_cost:.2f}")

        # Step 6: Check budget
        has_budget, budget_error = context.check_budget(estimated_cost)
        if not has_budget:
            log.error(f"❌ Budget check failed: {budget_error}")
            return AutoFixResult(
                fix_id=None,
                fixer_name=fixer.name if hasattr(fixer, 'name') else fixer.__class__.__name__,
                status=FixStatus.REJECTED,
                fix_type=fixer.name,
                fix_actions=fix_plan.fix_actions,
                risk_level=risk_level,
                success=False,
                error_message=budget_error,
                estimated_cost=estimated_cost,
            )

        # Step 7: Determine approval status
        auto_approved = False
        user_approved = False

        if force_apply:
            user_approved = True
            log.warning("⚠️  FORCE_APPLY enabled - skipping approval checks")
        elif context.can_auto_approve(risk_level, estimated_cost):
            auto_approved = True
            log.info("✅ Auto-approved (low risk + within budget)")
        else:
            # Requires user approval
            log.info(f"⏸️  Requires user approval (risk={risk_level.value}, cost=${estimated_cost:.2f})")
            # In a real implementation, this would:
            # 1. Save to AIFixAuditLog with status='pending'
            # 2. Send notification to user
            # 3. Return result with status='pending'
            # 4. User approves via API call, then we resume from here

            # For now, we'll create the audit log and return pending
            audit_log = self._create_audit_log(
                context=context,
                fix_plan=fix_plan,
                risk_level=risk_level,
                estimated_cost=estimated_cost,
                auto_approved=False,
                user_approved=False
            )

            return AutoFixResult(
                fix_id=audit_log.id,
                fixer_name=fixer.name if hasattr(fixer, 'name') else fixer.__class__.__name__,
                status=FixStatus.PENDING,
                fix_type=fixer.name,
                fix_actions=fix_plan.fix_actions,
                risk_level=risk_level,
                success=False,
                error_message=f"Requires user approval (risk: {risk_level.value})",
                estimated_cost=estimated_cost,
                auto_approved=False,
                user_approved=False,
            )

        # Step 8: Capture state snapshot
        log.info("📸 Capturing state snapshot for rollback")
        snapshot = fixer.capture_state(context, self.sa_session)

        # Step 9: Apply fix with error handling
        start_time = datetime.now()
        result = None

        try:
            log.info("🚀 Applying fix...")
            result = await fixer.apply_fix(context, fix_plan, self.sa_session)
            result.risk_level = risk_level
            result.estimated_cost = estimated_cost
            result.auto_approved = auto_approved
            result.user_approved = user_approved
            result.state_before = snapshot

            execution_time = (datetime.now() - start_time).total_seconds()
            result.execution_time_seconds = execution_time

            # 🆕 Phase 3.3: Post-validate fix result
            if result.success:
                is_valid, validation_error = self.validator.post_validate(context, result)
                if not is_valid:
                    log.error(f"❌ Post-validation failed: {validation_error}")
                    result.success = False
                    result.error_message = f"Post-validation failed: {validation_error}"
                    result.status = FixStatus.FAILED
                else:
                    log.info(f"✅ Fix applied and validated successfully in {execution_time:.2f}s")

            # 🆕 Phase 3.3: Record fix attempt for statistics
            issue_type = issues[0].get('type') if issues else None
            self.success_tracker.record_fix_attempt(
                fixer_name=fixer.name if hasattr(fixer, 'name') else fixer.__class__.__name__,
                fix_type=fix_plan.fix_type.value,
                success=result.success,
                issue_type=issue_type,
                confidence=fix_plan.confidence,
                execution_time=execution_time
            )

            if not result.success:
                log.error(f"❌ Fix failed: {result.error_message}")

                # Attempt rollback
                if snapshot:
                    log.info("🔄 Attempting rollback...")
                    rollback_success = await fixer.rollback(context, snapshot, self.sa_session)
                    if rollback_success:
                        log.info("✅ Rollback successful")
                        result.status = FixStatus.ROLLED_BACK
                    else:
                        log.error("❌ Rollback failed")

        except Exception as e:
            log.error(f"❌ Exception during fix application: {e}", exc_info=True)

            # Attempt rollback
            if snapshot:
                log.info("🔄 Attempting rollback after exception...")
                try:
                    rollback_success = await fixer.rollback(context, snapshot, self.sa_session)
                    status = FixStatus.ROLLED_BACK if rollback_success else FixStatus.FAILED
                except Exception as rollback_error:
                    log.error(f"❌ Rollback exception: {rollback_error}")
                    status = FixStatus.FAILED
            else:
                status = FixStatus.FAILED

            execution_time = (datetime.now() - start_time).total_seconds()

            result = AutoFixResult(
                fix_id=None,
                fixer_name=fixer.name if hasattr(fixer, 'name') else fixer.__class__.__name__,
                status=status,
                fix_type=fixer.name,
                fix_actions=fix_plan.fix_actions,
                risk_level=risk_level,
                success=False,
                error_message=str(e),
                estimated_cost=estimated_cost,
                auto_approved=auto_approved,
                user_approved=user_approved,
                execution_time_seconds=execution_time,
                state_before=snapshot,
            )

        # Step 10: Create/update audit log
        if result:
            audit_log = self._create_audit_log(
                context=context,
                fix_plan=fix_plan,
                risk_level=risk_level,
                estimated_cost=estimated_cost,
                auto_approved=auto_approved,
                user_approved=user_approved,
                result=result,
            )
            result.fix_id = audit_log.id if audit_log is not None else None

            # Update resource usage if successful and has cost
            if result.success and estimated_cost > 0:
                self._update_resource_usage(estimated_cost, ai_fix_applied=True)

        return result

    def _create_audit_log(
        self,
        context: FixContext,
        fix_plan,
        risk_level: RiskLevel,
        estimated_cost: float,
        auto_approved: bool,
        user_approved: bool,
        result: Optional[AutoFixResult] = None,
    ):
        """Create audit log entry. Returns None if AIFixAuditLog table is not available."""

        try:
            from galaxy.model import AIFixAuditLog
        except ImportError:
            log.debug("AIFixAuditLog unavailable — skipping persistent audit (in-memory session record still kept)")
            return None

        # Add estimated_cost to fix_details since it's not a direct column in the table
        fix_details_dict = fix_plan.to_dict()
        fix_details_dict['estimated_cost'] = estimated_cost

        audit_log = AIFixAuditLog(
            user_id=context.user_id,
            invocation_id=context.invocation_id,
            fix_type=fix_plan.fix_type.value if hasattr(fix_plan.fix_type, 'value') else str(fix_plan.fix_type),
            fix_details=fix_details_dict,
            risk_level=risk_level.value,
            auto_approved=auto_approved,
            user_approved=user_approved,
        )

        if result:
            audit_log.applied = result.status == FixStatus.APPLIED
            audit_log.success = result.success
            audit_log.error_message = result.error_message
            audit_log.execution_time = datetime.now()
            audit_log.duration_seconds = result.execution_time_seconds

        self.sa_session.add(audit_log)
        self.sa_session.commit()

        log.info(f"📝 Audit log created: ID={audit_log.id}")
        return audit_log

    def _update_resource_usage(self, cost: float, ai_fix_applied: bool = False):
        """Update user's resource usage tracking. No-op if table is unavailable."""
        from datetime import date

        try:
            from galaxy.model import UserResourceUsage
        except ImportError:
            return

        try:
            today = date.today()
            usage = (
                self.sa_session.query(UserResourceUsage)
                .filter_by(user_id=self.user_id, date=today)
                .first()
            )

            if not usage:
                usage = UserResourceUsage(
                    user_id=self.user_id,
                    date=today,
                )
                self.sa_session.add(usage)

            usage.estimated_total_cost += cost
            if ai_fix_applied:
                usage.total_ai_fixes_applied += 1

            self.sa_session.commit()
        except Exception as e:
            log.debug("Resource usage update skipped: %s", e)

    async def run_all_fixers(
        self,
        invocation_id: int,
        fixers: List[BaseAutoFixer],
        stop_on_first_success: bool = False,
    ) -> List[AutoFixResult]:
        """
        Run multiple fixers on an invocation

        Args:
            invocation_id: Workflow invocation ID
            fixers: List of fixers to run
            stop_on_first_success: Stop after first successful fix

        Returns:
            List of AutoFixResult for each fixer
        """
        results = []

        for fixer in fixers:
            try:
                result = await self.run_fixer(invocation_id, fixer)
                results.append(result)

                if stop_on_first_success and result.success:
                    log.info(f"✅ Stopping after successful fix by {fixer.name}")
                    break

            except Exception as e:
                log.error(f"❌ Error running fixer {fixer.name}: {e}", exc_info=True)
                # Continue with other fixers

        return results

    def get_fix_effectiveness_report(self, days: int = 7) -> Dict[str, Any]:
        """
        🆕 Phase 3.3: Generate fix effectiveness report

        Args:
            days: Number of days to analyze (default 7)

        Returns:
            Comprehensive effectiveness report
        """
        return self.success_tracker.generate_effectiveness_report(days=days)

    def get_success_rate(
        self,
        fixer_name: Optional[str] = None,
        fix_type: Optional[str] = None,
        days: int = 30
    ) -> Dict[str, Any]:
        """
        🆕 Phase 3.3: Get fix success rate statistics

        Args:
            fixer_name: Filter by fixer name (optional)
            fix_type: Filter by fix type (optional)
            days: Number of days to analyze (default 30)

        Returns:
            Success rate statistics
        """
        return self.success_tracker.get_success_rate(
            fixer_name=fixer_name,
            fix_type=fix_type,
            days=days
        )
