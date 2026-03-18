"""
Unit tests for NextflowParameterFixer
"""

import pytest
from unittest.mock import Mock, MagicMock, patch
from datetime import datetime

from galaxy.ai.workflow_ops.autofix.base import FixContext, RiskLevel, FixStatus
from galaxy.ai.workflow_ops.autofix.fixers.nextflow_parameter_fixer import NextflowParameterFixer
from galaxy.ai.workflow_ops.types import FixType, ActionType


class TestNextflowParameterFixer:
    """Test NextflowParameterFixer"""

    @pytest.fixture
    def fixer(self):
        return NextflowParameterFixer()

    @pytest.fixture
    def mock_context(self):
        """Create mock FixContext"""
        context = Mock(spec=FixContext)
        context.user_id = 1
        context.workflow_id = 100
        context.invocation_id = 200
        context.max_memory_gb = 64
        context.max_cpus = 16
        context.metadata = {'sa_session': Mock()}
        return context

    def test_detect_pipeline_type_clipseq(self, fixer):
        """Test pipeline type detection for clipseq"""
        workflow = Mock()
        workflow.name = "nf-core-clipseq-analysis"

        pipeline_type = fixer._detect_pipeline_type(workflow)
        assert pipeline_type == 'clipseq'

    def test_detect_pipeline_type_rnaseq(self, fixer):
        """Test pipeline type detection for rnaseq"""
        workflow = Mock()
        workflow.name = "RNA-Seq Pipeline"

        pipeline_type = fixer._detect_pipeline_type(workflow)
        assert pipeline_type == 'rnaseq'

    def test_detect_pipeline_type_generic(self, fixer):
        """Test pipeline type detection for unknown workflow"""
        workflow = Mock()
        workflow.name = "custom-workflow"

        pipeline_type = fixer._detect_pipeline_type(workflow)
        assert pipeline_type == 'generic'

    def test_get_pipeline_default_rnaseq_genome(self, fixer):
        """Test pipeline default value for rnaseq genome"""
        default = fixer._get_pipeline_default('rnaseq', 'genome')
        assert default == 'GRCh38'

    def test_get_pipeline_default_clipseq_source(self, fixer):
        """Test pipeline default value for clipseq source"""
        default = fixer._get_pipeline_default('clipseq', 'source')
        assert default == 'GRCh38'

    def test_get_pipeline_default_nonexistent(self, fixer):
        """Test pipeline default for non-existent parameter"""
        default = fixer._get_pipeline_default('rnaseq', 'nonexistent')
        assert default is None

    def test_validate_parameter_pattern_match(self, fixer):
        """Test parameter validation with regex pattern"""
        validation_rules = {'pattern': r'^GRCh\d+$'}

        # Valid value
        error = fixer._validate_parameter('GRCh38', validation_rules)
        assert error is None

        # Invalid value
        error = fixer._validate_parameter('hg38', validation_rules)
        assert error is not None
        assert 'does not match pattern' in error

    def test_validate_parameter_allowed_values(self, fixer):
        """Test parameter validation with allowed values"""
        validation_rules = {'allowed_values': ['star', 'hisat2', 'salmon']}

        # Valid value
        error = fixer._validate_parameter('star', validation_rules)
        assert error is None

        # Invalid value
        error = fixer._validate_parameter('bowtie2', validation_rules)
        assert error is not None
        assert 'not in allowed values' in error

    def test_validate_parameter_type_integer(self, fixer):
        """Test parameter type validation for integer"""
        validation_rules = {'type': 'integer'}

        # Valid integer
        error = fixer._validate_parameter(10, validation_rules)
        assert error is None

        # Invalid (string that cannot be converted)
        error = fixer._validate_parameter('abc', validation_rules)
        assert error is not None
        assert 'not a valid integer' in error

    def test_infer_from_history_no_data(self, fixer, mock_context):
        """Test history inference with no historical data"""
        sa_session = mock_context.metadata['sa_session']
        sa_session.query().filter().filter().order_by().limit().all.return_value = []

        result = fixer._infer_from_history(1, 100, 'genome', sa_session)
        assert result is None

    def test_infer_from_history_with_data(self, fixer, mock_context):
        """Test history inference with historical data"""
        # Mock invocations with parameters
        mock_inv1 = Mock()
        mock_inv1.input_parameters = {'genome': 'GRCh38'}

        mock_inv2 = Mock()
        mock_inv2.input_parameters = {'genome': 'GRCh38'}

        mock_inv3 = Mock()
        mock_inv3.input_parameters = {'genome': 'GRCh37'}

        sa_session = mock_context.metadata['sa_session']
        sa_session.query().filter().filter().order_by().limit().all.return_value = [
            mock_inv1, mock_inv2, mock_inv3
        ]

        result = fixer._infer_from_history(1, 100, 'genome', sa_session)

        assert result is not None
        assert result['value'] == 'GRCh38'  # Most common value
        assert result['count'] == 2

    @pytest.mark.asyncio
    async def test_apply_fix_success(self, fixer, mock_context):
        """Test successful fix application"""
        from galaxy.ai.workflow_ops.types import FixPlan, FixAction

        # Mock invocation
        mock_invocation = Mock()
        mock_invocation.input_parameters = {'existing_param': 'value'}

        sa_session = mock_context.metadata['sa_session']
        sa_session.query().get.return_value = mock_invocation

        # Create fix plan
        fix_action = FixAction(
            action=ActionType.UPDATE_PARAM,
            params={
                'parameter_name': 'genome',
                'current_value': None,
                'recommended_value': 'GRCh38',
                'confidence': 0.9,
            },
            description="Set 'genome' to 'GRCh38'",
            risk_level='low',
        )

        fix_plan = FixPlan(
            fixable=True,
            fix_type=FixType.CONFIG_ADJUSTMENT,
            fix_actions=[fix_action],
            explanation="Test fix",
            confidence=0.9,
        )

        # Apply fix
        result = await fixer.apply_fix(mock_context, fix_plan, sa_session)

        assert result.success is True
        assert result.status == FixStatus.APPLIED
        assert len(result.fix_actions) == 1

        # Verify parameter was updated
        assert mock_invocation.input_parameters['genome'] == 'GRCh38'
        sa_session.commit.assert_called_once()

    def test_check_permissions_owner(self, fixer, mock_context):
        """Test permission check for workflow owner"""
        mock_invocation = Mock()
        mock_invocation.user_id = 1  # Same as context.user_id

        sa_session = mock_context.metadata['sa_session']
        sa_session.query().get.return_value = mock_invocation

        allowed, error = fixer.check_permissions(mock_context, sa_session)

        assert allowed is True
        assert error is None

    def test_check_permissions_other_user(self, fixer, mock_context):
        """Test permission check for non-owner"""
        mock_invocation = Mock()
        mock_invocation.user_id = 999  # Different from context.user_id

        sa_session = mock_context.metadata['sa_session']
        sa_session.query().get.return_value = mock_invocation

        allowed, error = fixer.check_permissions(mock_context, sa_session)

        assert allowed is False
        assert "Access denied" in error


if __name__ == '__main__':
    pytest.main([__file__, '-v'])
