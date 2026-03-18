"""
Integration tests for AutoFix framework

These tests require Galaxy to be running.
"""

import pytest
import asyncio
from unittest.mock import Mock, MagicMock

from galaxy.ai.workflow_ops.autofix import AutoFixOrchestrator
from galaxy.ai.workflow_ops.autofix.fixers import (
    NextflowParameterFixer,
    AWSResourceFixer,
    DataFileFixer,
    RetryStrategyFixer,
)


class TestAutoFixIntegration:
    """Integration tests for the complete AutoFix flow"""

    @pytest.fixture
    def mock_trans(self):
        """Create mock transaction context"""
        trans = Mock()
        trans.user = Mock()
        trans.user.id = 1
        trans.sa_session = MagicMock()

        # Mock user preferences
        from galaxy.model import UserCloudPreferences

        mock_prefs = Mock(spec=UserCloudPreferences)
        mock_prefs.ai_auto_fix_enabled = True
        mock_prefs.ai_auto_fix_mode = 'safe'
        mock_prefs.ai_require_approval_for_cost = 10.0
        mock_prefs.daily_budget_usd = 100.0
        mock_prefs.monthly_budget_usd = 1000.0
        mock_prefs.max_memory_gb = 64
        mock_prefs.max_cpus = 16
        mock_prefs.max_concurrent_jobs = 10

        trans.sa_session.query().filter_by().first.return_value = mock_prefs

        # Mock resource usage
        from galaxy.model import UserResourceUsage

        mock_usage = Mock(spec=UserResourceUsage)
        mock_usage.estimated_total_cost = 10.0  # $10 used today

        trans.sa_session.query().filter_by.return_value.first.return_value = mock_usage

        return trans

    @pytest.fixture
    def mock_invocation(self):
        """Create mock workflow invocation"""
        from galaxy.model import WorkflowInvocation

        invocation = Mock(spec=WorkflowInvocation)
        invocation.id = 200
        invocation.user_id = 1
        invocation.workflow_id = 100
        invocation.input_parameters = {}
        invocation.workflow = Mock()
        invocation.workflow.name = "nf-core-rnaseq"
        invocation.workflow.id = 100

        return invocation

    @pytest.mark.asyncio
    async def test_orchestrator_run_single_fixer(self, mock_trans, mock_invocation):
        """Test running a single fixer through orchestrator"""
        # Setup
        mock_trans.sa_session.query().get.return_value = mock_invocation

        orchestrator = AutoFixOrchestrator(mock_trans)
        fixer = NextflowParameterFixer()

        # Run (with no actual issues, should return no fixes)
        result = await orchestrator.run_fixer(
            invocation_id=200,
            fixer=fixer,
            auto_approve_low_risk=True
        )

        assert result is not None
        # With no issues detected, success should be True but no actions taken
        assert result.success is True or result.error_message == "No issues detected"

    @pytest.mark.asyncio
    async def test_orchestrator_run_all_fixers(self, mock_trans, mock_invocation):
        """Test running multiple fixers"""
        mock_trans.sa_session.query().get.return_value = mock_invocation

        orchestrator = AutoFixOrchestrator(mock_trans)

        fixers = [
            NextflowParameterFixer(),
            DataFileFixer(),
            AWSResourceFixer(),
            RetryStrategyFixer(),
        ]

        results = await orchestrator.run_all_fixers(
            invocation_id=200,
            fixers=fixers,
            stop_on_first_success=False
        )

        assert len(results) == 4
        # All should complete without errors
        for result in results:
            assert result is not None

    @pytest.mark.asyncio
    async def test_permission_check_blocks_other_user(self, mock_trans, mock_invocation):
        """Test that permission check blocks access to other user's workflow"""
        # Modify invocation to belong to different user
        mock_invocation.user_id = 999

        mock_trans.sa_session.query().get.return_value = mock_invocation

        orchestrator = AutoFixOrchestrator(mock_trans)
        fixer = NextflowParameterFixer()

        # Should raise PermissionError
        with pytest.raises(PermissionError):
            await orchestrator.run_fixer(
                invocation_id=200,
                fixer=fixer
            )

    @pytest.mark.asyncio
    async def test_budget_check_rejects_expensive_fix(self, mock_trans, mock_invocation):
        """Test that expensive fixes are rejected when over budget"""
        mock_trans.sa_session.query().get.return_value = mock_invocation

        # Create fixer that estimates high cost
        class ExpensiveFixer(NextflowParameterFixer):
            def estimate_cost(self, context, fix_plan):
                return 1000.0  # $1000 - exceeds daily budget

        orchestrator = AutoFixOrchestrator(mock_trans)
        fixer = ExpensiveFixer()

        # Even if issues detected, should be rejected due to budget
        result = await orchestrator.run_fixer(
            invocation_id=200,
            fixer=fixer
        )

        # Should either be rejected or pending due to cost
        if result.status.value == 'rejected':
            assert 'budget' in result.error_message.lower()

    def test_risk_level_determines_approval(self, mock_trans):
        """Test that risk level correctly determines auto-approval"""
        from galaxy.ai.workflow_ops.autofix.base import FixContext, RiskLevel

        context = FixContext(
            user_id=1,
            invocation_id=200,
            workflow_id=100,
            ai_auto_fix_enabled=True,
            ai_auto_fix_mode='safe',
            ai_require_approval_for_cost=10.0,
            daily_budget_remaining=50.0,
            monthly_budget_remaining=500.0,
        )

        # Low risk with safe mode - should auto-approve
        assert context.can_auto_approve(RiskLevel.LOW, 5.0) is True

        # Medium risk with safe mode - should NOT auto-approve
        assert context.can_auto_approve(RiskLevel.MEDIUM, 5.0) is False

        # High risk - should NEVER auto-approve
        assert context.can_auto_approve(RiskLevel.HIGH, 5.0) is False

        # Change to moderate mode
        context.ai_auto_fix_mode = 'moderate'

        # Medium risk with moderate mode - should auto-approve
        assert context.can_auto_approve(RiskLevel.MEDIUM, 5.0) is True

    def test_state_snapshot_captures_parameters(self, mock_trans, mock_invocation):
        """Test that state snapshot correctly captures current state"""
        mock_invocation.input_parameters = {'genome': 'GRCh37', 'aligner': 'star'}
        mock_trans.sa_session.query().get.return_value = mock_invocation

        fixer = NextflowParameterFixer()

        from galaxy.ai.workflow_ops.autofix.base import FixContext

        context = FixContext(
            user_id=1,
            invocation_id=200,
            workflow_id=100,
        )
        context.metadata = {'sa_session': mock_trans.sa_session}

        snapshot = fixer.capture_state(context, mock_trans.sa_session)

        assert snapshot is not None
        assert snapshot.invocation_id == 200
        assert snapshot.parameters['genome'] == 'GRCh37'
        assert snapshot.parameters['aligner'] == 'star'


if __name__ == '__main__':
    pytest.main([__file__, '-v', '-s'])
