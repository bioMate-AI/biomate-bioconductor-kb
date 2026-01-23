"""
Simple tests for ProposeValidateWorkflowGenerator (no pytest required)
"""

import json
import sys
import os
import traceback

# Add parent directory to path for imports
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from propose_validate_workflow_generator import (
    ProposeValidateWorkflowGenerator,
    create_propose_validate_generator
)
from workflow_proposal_validator import (
    WorkflowProposalValidator,
    ToolIndexValidator,
    KnowledgeValidator,
    WorkflowValidation,
    StepValidation,
    ToolValidation
)


class MockLLMClient:
    """Mock LLM client for testing without actual API calls."""

    def __init__(self):
        self.call_count = 0
        self.call_history = []

    def generate(self, prompt: str, max_tokens: int = 1000) -> str:
        self.call_count += 1
        self.call_history.append(prompt[:200])  # Store first 200 chars

        # Return pre-defined responses based on prompt content
        if "propose a workflow" in prompt.lower() or "propose" in prompt.lower():
            return self._get_proposal_response(prompt)
        elif "refining" in prompt.lower() or "refinement" in prompt.lower():
            return self._get_refinement_response(prompt)
        else:
            # Default proposal response
            return self._get_proposal_response(prompt)

    def _get_proposal_response(self, prompt: str) -> str:
        """Generate mock workflow proposal."""
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

    def _get_refinement_response(self, prompt: str) -> str:
        """Generate mock refined workflow."""
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


def run_test(name, test_func):
    """Run a single test and report results."""
    try:
        test_func()
        print(f"  [PASS] {name}")
        return True
    except AssertionError as e:
        print(f"  [FAIL] {name}: {e}")
        return False
    except Exception as e:
        print(f"  [ERROR] {name}: {type(e).__name__}: {e}")
        traceback.print_exc()
        return False


def test_generator_creation():
    """Test that generator can be created."""
    generator = ProposeValidateWorkflowGenerator()
    assert generator is not None
    assert generator.validator is not None
    assert generator.llm_client is not None


def test_mock_llm_workflow_generation():
    """Test workflow generation with mock LLM."""
    generator = ProposeValidateWorkflowGenerator()
    generator.llm_client = MockLLMClient()

    result = generator.generate_workflow(
        user_intent="RNA-seq differential expression analysis"
    )

    assert result['success'] is True, f"Expected success=True, got {result.get('success')}"
    assert 'workflow' in result, "Missing 'workflow' in result"
    assert 'validation' in result, "Missing 'validation' in result"
    assert 'refinement_history' in result, "Missing 'refinement_history' in result"


def test_workflow_structure():
    """Test that workflow has correct structure."""
    generator = ProposeValidateWorkflowGenerator()
    generator.llm_client = MockLLMClient()

    result = generator.generate_workflow(
        user_intent="RNA-seq analysis"
    )

    workflow = result['workflow']
    assert 'steps' in workflow, "Workflow missing 'steps'"
    assert len(workflow['steps']) > 0, "Workflow has no steps"

    # Check step structure
    for step in workflow['steps']:
        assert 'tool_name' in step, "Step missing 'tool_name'"
        assert 'purpose' in step, "Step missing 'purpose'"


def test_galaxy_format_generation():
    """Test Galaxy .ga format generation."""
    generator = ProposeValidateWorkflowGenerator()
    generator.llm_client = MockLLMClient()

    result = generator.generate_workflow(
        user_intent="RNA-seq analysis"
    )

    assert 'workflow_ga' in result, "Missing 'workflow_ga' in result"

    ga = result['workflow_ga']
    assert ga['a_galaxy_workflow'] == 'true', "Invalid a_galaxy_workflow flag"
    assert 'steps' in ga, "Galaxy workflow missing 'steps'"
    assert 'name' in ga, "Galaxy workflow missing 'name'"


def test_validation_info():
    """Test that validation info is included."""
    generator = ProposeValidateWorkflowGenerator()
    generator.llm_client = MockLLMClient()

    result = generator.generate_workflow(
        user_intent="RNA-seq analysis"
    )

    validation = result['validation']
    assert 'all_tools_available' in validation
    assert 'all_tools_recommended' in validation
    assert 'confidence_score' in validation
    assert 'steps' in validation


def test_refinement_history():
    """Test that refinement history is tracked."""
    generator = ProposeValidateWorkflowGenerator()
    generator.llm_client = MockLLMClient()

    result = generator.generate_workflow(
        user_intent="RNA-seq analysis"
    )

    history = result['refinement_history']
    assert len(history) >= 1, "Should have at least 1 iteration"

    for entry in history:
        assert 'iteration' in entry
        assert 'workflow' in entry
        assert 'validation' in entry


def test_json_parsing_clean():
    """Test JSON parsing with clean input."""
    generator = ProposeValidateWorkflowGenerator()

    response = '{"workflow_name": "Test", "steps": []}'
    result = generator._parse_json_response(response)

    assert result is not None
    assert result['workflow_name'] == 'Test'


def test_json_parsing_markdown():
    """Test JSON parsing with markdown code block."""
    generator = ProposeValidateWorkflowGenerator()

    response = '''```json
{"workflow_name": "Test", "steps": []}
```'''
    result = generator._parse_json_response(response)

    assert result is not None
    assert result['workflow_name'] == 'Test'


def test_json_parsing_with_text():
    """Test JSON parsing with surrounding text."""
    generator = ProposeValidateWorkflowGenerator()

    response = '''Here's the workflow:
{"workflow_name": "Test", "steps": []}
That's it.'''
    result = generator._parse_json_response(response)

    assert result is not None
    assert result['workflow_name'] == 'Test'


def test_validation_to_dict():
    """Test validation result conversion."""
    generator = ProposeValidateWorkflowGenerator()

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


def test_domain_detection():
    """Test domain detection in result."""
    generator = ProposeValidateWorkflowGenerator()
    generator.llm_client = MockLLMClient()

    result = generator.generate_workflow(
        user_intent="RNA-seq differential expression"
    )

    assert 'domain' in result
    # Domain should be detected (rna_seq or generic)
    assert result['domain'] is not None


def test_data_characteristics():
    """Test workflow generation with data characteristics."""
    generator = ProposeValidateWorkflowGenerator()
    generator.llm_client = MockLLMClient()

    result = generator.generate_workflow(
        user_intent="RNA-seq analysis",
        data_characteristics={
            'read_length': 150,
            'paired_end': True,
            'organism': 'human'
        }
    )

    assert result['success'] is True


def test_factory_function():
    """Test factory function."""
    generator = create_propose_validate_generator()
    assert generator is not None
    assert isinstance(generator, ProposeValidateWorkflowGenerator)


def main():
    """Run all tests."""
    print("\n" + "=" * 60)
    print("ProposeValidateWorkflowGenerator Tests")
    print("=" * 60 + "\n")

    tests = [
        ("Generator Creation", test_generator_creation),
        ("Mock LLM Workflow Generation", test_mock_llm_workflow_generation),
        ("Workflow Structure", test_workflow_structure),
        ("Galaxy Format Generation", test_galaxy_format_generation),
        ("Validation Info", test_validation_info),
        ("Refinement History", test_refinement_history),
        ("JSON Parsing (Clean)", test_json_parsing_clean),
        ("JSON Parsing (Markdown)", test_json_parsing_markdown),
        ("JSON Parsing (With Text)", test_json_parsing_with_text),
        ("Validation to Dict", test_validation_to_dict),
        ("Domain Detection", test_domain_detection),
        ("Data Characteristics", test_data_characteristics),
        ("Factory Function", test_factory_function),
    ]

    passed = 0
    failed = 0

    for name, test_func in tests:
        if run_test(name, test_func):
            passed += 1
        else:
            failed += 1

    print("\n" + "-" * 60)
    print(f"Results: {passed} passed, {failed} failed, {len(tests)} total")
    print("-" * 60 + "\n")

    return failed == 0


if __name__ == '__main__':
    success = main()
    sys.exit(0 if success else 1)
