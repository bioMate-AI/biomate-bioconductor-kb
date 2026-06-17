"""
Tests for ProposeValidateWorkflowGenerator

Tests the LLM-propose-then-validate workflow generation approach.
"""

import pytest
import json

# Import via the proper galaxy.ai package path — the module uses
# relative imports internally (from .workflow_proposal_validator) which
# only resolve when loaded as part of the galaxy.ai package, not as a
# top-level module.
from galaxy.ai.propose_validate_workflow_generator import (
    ProposeValidateWorkflowGenerator,
    create_propose_validate_generator,
)
from galaxy.ai.workflow_proposal_validator import (
    WorkflowProposalValidator,
    ToolIndexValidator,
    KnowledgeValidator,
    create_workflow_validator,
)


class MockLLMClient:
    """Mock LLM client for testing without actual API calls."""

    def __init__(self, responses=None):
        self.responses = responses or {}
        self.call_count = 0
        self.call_history = []

    def generate(self, prompt: str, max_tokens: int = 1000) -> str:
        self.call_count += 1
        self.call_history.append(prompt)

        # Return pre-defined responses based on prompt content
        if "propose a workflow" in prompt.lower():
            return self._get_proposal_response(prompt)
        elif "refining" in prompt.lower():
            return self._get_refinement_response(prompt)
        else:
            return json.dumps({"error": "Unknown prompt type"})

    def _get_proposal_response(self, prompt: str) -> str:
        """Generate mock workflow proposal."""
        if "rna-seq" in prompt.lower() or "differential expression" in prompt.lower():
            return json.dumps({
                "workflow_name": "RNA-seq Differential Expression Analysis",
                "description": "Standard RNA-seq DE analysis pipeline",
                "steps": [
                    {
                        "step": 1,
                        "tool_name": "FastQC",
                        "purpose": "Quality control of raw reads",
                        "key_parameters": {},
                        "justification": "Standard QC tool"
                    },
                    {
                        "step": 2,
                        "tool_name": "HISAT2",
                        "purpose": "Splice-aware alignment",
                        "key_parameters": {"--dta": True},
                        "justification": "Efficient splice-aware aligner"
                    },
                    {
                        "step": 3,
                        "tool_name": "featureCounts",
                        "purpose": "Read quantification",
                        "key_parameters": {},
                        "justification": "Fast and accurate counting"
                    },
                    {
                        "step": 4,
                        "tool_name": "DESeq2",
                        "purpose": "Differential expression analysis",
                        "key_parameters": {},
                        "justification": "Gold standard for DE"
                    }
                ]
            })
        elif "variant" in prompt.lower() or "snp" in prompt.lower():
            return json.dumps({
                "workflow_name": "Variant Calling Pipeline",
                "description": "DNA variant calling workflow",
                "steps": [
                    {
                        "step": 1,
                        "tool_name": "FastQC",
                        "purpose": "Quality control",
                        "key_parameters": {},
                        "justification": "Standard QC"
                    },
                    {
                        "step": 2,
                        "tool_name": "BWA-MEM",
                        "purpose": "Read alignment",
                        "key_parameters": {},
                        "justification": "Fast aligner for short reads"
                    },
                    {
                        "step": 3,
                        "tool_name": "GATK HaplotypeCaller",
                        "purpose": "Variant calling",
                        "key_parameters": {},
                        "justification": "Gold standard variant caller"
                    }
                ]
            })
        else:
            return json.dumps({
                "workflow_name": "Generic Analysis",
                "description": "Basic analysis workflow",
                "steps": [
                    {
                        "step": 1,
                        "tool_name": "FastQC",
                        "purpose": "Quality control",
                        "key_parameters": {},
                        "justification": "Standard QC"
                    }
                ]
            })

    def _get_refinement_response(self, prompt: str) -> str:
        """Generate mock refined workflow."""
        # Return a refined workflow using available tools
        return json.dumps({
            "workflow_name": "Refined RNA-seq Analysis",
            "description": "Refined pipeline using available tools",
            "steps": [
                {
                    "step": 1,
                    "tool_name": "fastqc",
                    "purpose": "Quality control of raw reads",
                    "key_parameters": {},
                    "justification": "Using exact Galaxy tool ID"
                },
                {
                    "step": 2,
                    "tool_name": "hisat2",
                    "purpose": "Splice-aware alignment",
                    "key_parameters": {},
                    "justification": "Available in Galaxy"
                },
                {
                    "step": 3,
                    "tool_name": "featurecounts",
                    "purpose": "Read quantification",
                    "key_parameters": {},
                    "justification": "Using available tool"
                },
                {
                    "step": 4,
                    "tool_name": "deseq2",
                    "purpose": "Differential expression",
                    "key_parameters": {},
                    "justification": "Available DE tool"
                }
            ]
        })


class TestProposeValidateGenerator:
    """Tests for ProposeValidateWorkflowGenerator."""

    @pytest.fixture
    def mock_generator(self):
        """Create generator with mock LLM client."""
        generator = ProposeValidateWorkflowGenerator()
        generator.llm_client = MockLLMClient()
        return generator

    def test_generate_workflow_basic(self, mock_generator):
        """Test basic workflow generation."""
        result = mock_generator.generate_workflow(
            user_intent="RNA-seq differential expression analysis"
        )

        assert result['success'] is True
        assert 'workflow' in result
        assert 'validation' in result
        assert 'refinement_history' in result
        assert len(result['refinement_history']) > 0

        # Check workflow structure
        workflow = result['workflow']
        assert 'steps' in workflow
        assert len(workflow['steps']) > 0

    def test_generate_workflow_with_data_characteristics(self, mock_generator):
        """Test workflow generation with data characteristics."""
        result = mock_generator.generate_workflow(
            user_intent="RNA-seq analysis",
            data_characteristics={
                'read_length': 150,
                'paired_end': True,
                'organism': 'human'
            }
        )

        assert result['success'] is True
        assert 'domain' in result

    def test_generate_workflow_returns_galaxy_format(self, mock_generator):
        """Test that Galaxy .ga format workflow is generated."""
        result = mock_generator.generate_workflow(
            user_intent="RNA-seq differential expression"
        )

        assert result['success'] is True
        assert 'workflow_ga' in result

        ga_workflow = result['workflow_ga']
        assert ga_workflow['a_galaxy_workflow'] == 'true'
        assert 'steps' in ga_workflow
        assert 'name' in ga_workflow

    def test_validation_info_included(self, mock_generator):
        """Test that validation info is included in result."""
        result = mock_generator.generate_workflow(
            user_intent="RNA-seq analysis"
        )

        assert 'validation' in result
        validation = result['validation']

        assert 'all_tools_available' in validation
        assert 'all_tools_recommended' in validation
        assert 'confidence_score' in validation
        assert 'steps' in validation

    def test_refinement_history_tracked(self, mock_generator):
        """Test that refinement iterations are tracked."""
        result = mock_generator.generate_workflow(
            user_intent="RNA-seq differential expression"
        )

        assert 'refinement_history' in result
        history = result['refinement_history']

        # Should have at least one iteration
        assert len(history) >= 1

        # Each iteration should have workflow and validation
        for entry in history:
            assert 'iteration' in entry
            assert 'workflow' in entry
            assert 'validation' in entry

    def test_domain_detection(self, mock_generator):
        """Test that domain is correctly detected."""
        result = mock_generator.generate_workflow(
            user_intent="RNA-seq differential expression analysis"
        )

        assert 'domain' in result
        assert result['domain'] in ['rna_seq', 'generic']

    def test_max_refinement_iterations(self, mock_generator):
        """Test that refinement respects max iterations."""
        result = mock_generator.generate_workflow(
            user_intent="RNA-seq analysis"
        )

        # Should not exceed MAX_REFINEMENT_ITERATIONS + 1
        max_iterations = mock_generator.MAX_REFINEMENT_ITERATIONS + 1
        assert len(result['refinement_history']) <= max_iterations


class TestJSONParsing:
    """Test JSON parsing from LLM responses."""

    @pytest.fixture
    def generator(self):
        return ProposeValidateWorkflowGenerator()

    def test_parse_clean_json(self, generator):
        """Test parsing clean JSON."""
        response = '{"workflow_name": "Test", "steps": []}'
        result = generator._parse_json_response(response)

        assert result is not None
        assert result['workflow_name'] == 'Test'

    def test_parse_json_with_markdown(self, generator):
        """Test parsing JSON wrapped in markdown code block."""
        response = '''```json
{"workflow_name": "Test", "steps": []}
```'''
        result = generator._parse_json_response(response)

        assert result is not None
        assert result['workflow_name'] == 'Test'

    def test_parse_json_with_text_before(self, generator):
        """Test parsing JSON with text before it."""
        response = '''Here's the workflow:
{"workflow_name": "Test", "steps": []}'''
        result = generator._parse_json_response(response)

        assert result is not None
        assert result['workflow_name'] == 'Test'

    def test_parse_invalid_json(self, generator):
        """Test handling of invalid JSON."""
        response = 'This is not JSON at all'
        result = generator._parse_json_response(response)

        assert result is None


class TestValidatorIntegration:
    """Test integration with validators."""

    def test_validator_created(self):
        """Test that validator is created."""
        generator = ProposeValidateWorkflowGenerator()
        assert generator.validator is not None
        assert isinstance(generator.validator, WorkflowProposalValidator)

    def test_validation_to_dict(self):
        """Test validation result conversion to dict."""
        from workflow_proposal_validator import (
            WorkflowValidation, StepValidation, ToolValidation
        )

        generator = ProposeValidateWorkflowGenerator()

        # Create a mock validation result
        step_validation = StepValidation(
            step_number=1,
            proposed_tool="FastQC",
            purpose="QC",
            tool_validation=ToolValidation(
                proposed_tool="FastQC",
                status="FOUND",
                galaxy_tool_id="fastqc",
                confidence=1.0
            )
        )

        validation = WorkflowValidation(
            workflow_name="Test",
            steps=[step_validation],
            all_tools_available=True,
            all_tools_recommended=True,
            needs_refinement=False,
            confidence_score=0.9,
            refinement_suggestions=[]
        )

        result = generator._validation_to_dict(validation)

        assert isinstance(result, dict)
        assert result['workflow_name'] == 'Test'
        assert result['all_tools_available'] is True
        assert len(result['steps']) == 1


class TestGalaxyWorkflowFormat:
    """Test Galaxy .ga format generation."""

    @pytest.fixture
    def mock_generator(self):
        generator = ProposeValidateWorkflowGenerator()
        generator.llm_client = MockLLMClient()
        return generator

    def test_galaxy_format_structure(self, mock_generator):
        """Test Galaxy workflow has correct structure."""
        result = mock_generator.generate_workflow(
            user_intent="RNA-seq analysis"
        )

        ga = result['workflow_ga']

        # Required fields
        assert 'a_galaxy_workflow' in ga
        assert 'format-version' in ga
        assert 'name' in ga
        assert 'steps' in ga

        # Check step structure
        for step_id, step in ga['steps'].items():
            assert 'id' in step
            assert 'tool_id' in step
            assert 'type' in step

    def test_biomni_tool_id_normalization(self, mock_generator):
        """Test that biomni tool IDs are normalized."""
        # This tests the _build_galaxy_workflow method's handling of biomni tools
        from workflow_proposal_validator import (
            WorkflowValidation, StepValidation, ToolValidation
        )

        step_validation = StepValidation(
            step_number=0,
            proposed_tool="biomni_query",
            purpose="Query database",
            tool_validation=ToolValidation(
                proposed_tool="biomni_query",
                status="FOUND",
                galaxy_tool_id="biomni/query/tool",
                confidence=1.0
            )
        )

        validation = WorkflowValidation(
            workflow_name="Test",
            steps=[step_validation],
            all_tools_available=True,
            all_tools_recommended=True,
            needs_refinement=False,
            confidence_score=0.9,
            refinement_suggestions=[]
        )

        workflow = {
            "workflow_name": "Test",
            "steps": [{"key_parameters": {}}]
        }

        ga = mock_generator._build_galaxy_workflow(workflow, validation, "test")

        # Check tool_id is normalized
        step = ga['steps']['0']
        assert '/' not in step['tool_id']  # Should be normalized


def run_tests():
    """Run all tests."""
    pytest.main([__file__, '-v', '--tb=short'])


if __name__ == '__main__':
    run_tests()
