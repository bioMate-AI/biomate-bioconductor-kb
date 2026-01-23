#!/usr/bin/env python
"""
Comparison Test: ProposeValidate V1 vs V2

Tests both implementations side-by-side to compare:
- Reference context gathering (V2 only)
- Iteration count
- Confidence scores
- Tool availability
- Performance
"""

import sys
import os
import json
import time

# Ensure proper imports
os.chdir(os.path.dirname(os.path.abspath(__file__)))


class MockLLMClient:
    """Mock LLM client for consistent testing."""

    def __init__(self):
        self.call_count = 0
        self.call_history = []

    def generate(self, prompt: str, max_tokens: int = 1000) -> str:
        self.call_count += 1
        self.call_history.append(prompt[:500])

        # Check if it's a refinement prompt
        if "refine" in prompt.lower() or "issues found" in prompt.lower():
            return self._refinement_response()

        # Initial proposal
        return self._proposal_response(prompt)

    def _proposal_response(self, prompt: str) -> str:
        # If prompt mentions available tools, use them
        if "AVAILABLE TOOLS" in prompt:
            # V2 style - informed proposal using available tools
            return json.dumps({
                "workflow_name": "RNA-seq Analysis (Informed)",
                "description": "RNA-seq pipeline using available tools",
                "steps": [
                    {"step": 1, "tool_name": "FastQC", "purpose": "Quality control",
                     "key_parameters": {}, "justification": "Available in system"},
                    {"step": 2, "tool_name": "HISAT2", "purpose": "Alignment",
                     "key_parameters": {}, "justification": "Available in system"},
                    {"step": 3, "tool_name": "featureCounts", "purpose": "Quantification",
                     "key_parameters": {}, "justification": "Available in system"},
                    {"step": 4, "tool_name": "DESeq2", "purpose": "DE analysis",
                     "key_parameters": {}, "justification": "Available in system"}
                ]
            })
        else:
            # V1 style - may propose unavailable tools
            return json.dumps({
                "workflow_name": "RNA-seq Analysis (Uninformed)",
                "description": "RNA-seq pipeline from LLM knowledge",
                "steps": [
                    {"step": 1, "tool_name": "FastQC", "purpose": "Quality control",
                     "key_parameters": {}, "justification": "Best QC tool"},
                    {"step": 2, "tool_name": "STAR", "purpose": "Alignment",
                     "key_parameters": {}, "justification": "Best aligner"},
                    {"step": 3, "tool_name": "htseq-count", "purpose": "Counting",
                     "key_parameters": {}, "justification": "Popular counter"},
                    {"step": 4, "tool_name": "DESeq2", "purpose": "DE analysis",
                     "key_parameters": {}, "justification": "Gold standard"}
                ]
            })

    def _refinement_response(self) -> str:
        return json.dumps({
            "workflow_name": "RNA-seq Analysis (Refined)",
            "description": "Refined pipeline with available tools",
            "steps": [
                {"step": 1, "tool_name": "FastQC", "purpose": "Quality control",
                 "key_parameters": {}, "justification": "Available"},
                {"step": 2, "tool_name": "HISAT2", "purpose": "Alignment",
                 "key_parameters": {}, "justification": "Available replacement for STAR"},
                {"step": 3, "tool_name": "featureCounts", "purpose": "Counting",
                 "key_parameters": {}, "justification": "Available"},
                {"step": 4, "tool_name": "DESeq2", "purpose": "DE analysis",
                 "key_parameters": {}, "justification": "Available"}
            ]
        })


def test_v1():
    """Test V1 (original) implementation."""
    print("\n" + "=" * 60)
    print("Testing V1 (Original ProposeValidateWorkflowGenerator)")
    print("=" * 60)

    try:
        from propose_validate_workflow_generator import ProposeValidateWorkflowGenerator

        generator = ProposeValidateWorkflowGenerator()
        generator.llm_client = MockLLMClient()

        start_time = time.time()
        result = generator.generate_workflow(
            user_intent="RNA-seq differential expression analysis"
        )
        elapsed = time.time() - start_time

        print(f"\nResults:")
        print(f"  Success: {result['success']}")
        print(f"  Confidence: {result.get('confidence', 0):.2f}")
        print(f"  All tools available: {result.get('all_tools_available', False)}")
        print(f"  Iterations: {len(result.get('refinement_history', []))}")
        print(f"  LLM calls: {generator.llm_client.call_count}")
        print(f"  Time: {elapsed:.2f}s")

        if result['success']:
            print(f"\nWorkflow: {result['workflow'].get('workflow_name')}")
            print(f"Steps:")
            for step in result.get('validation', {}).get('steps', []):
                status = "✓" if step['tool_status'] == 'FOUND' else "✗"
                print(f"  {status} {step['proposed_tool']}: {step['tool_status']}")

        return result

    except Exception as e:
        print(f"V1 test failed: {e}")
        import traceback
        traceback.print_exc()
        return None


def test_v2():
    """Test V2 (experimental) implementation."""
    print("\n" + "=" * 60)
    print("Testing V2 (Experimental ProposeValidateV2)")
    print("=" * 60)

    try:
        from propose_validate_v2_experimental import ProposeValidateV2Experimental

        generator = ProposeValidateV2Experimental()
        generator._llm_client = MockLLMClient()

        start_time = time.time()
        result = generator.generate_workflow(
            user_intent="RNA-seq differential expression analysis"
        )
        elapsed = time.time() - start_time

        print(f"\nResults:")
        print(f"  Success: {result['success']}")
        print(f"  Confidence: {result.get('confidence', 0):.2f}")
        print(f"  All tools available: {result.get('all_tools_available', False)}")
        print(f"  Iterations: {result.get('iterations', 0)}")
        print(f"  LLM calls: {generator._llm_client.call_count}")
        print(f"  Time: {elapsed:.2f}s")

        # V2 specific: context used
        context = result.get('context_used', {})
        print(f"\nContext gathered (V2 feature):")
        print(f"  Similar workflows found: {context.get('similar_workflows', 0)}")
        print(f"  Available tools checked: {context.get('available_tools', 0)}")
        print(f"  Decision rules loaded: {context.get('decision_rules', 0)}")

        if result['success']:
            print(f"\nWorkflow: {result['workflow'].get('workflow_name')}")
            print(f"Steps:")
            for step_val in result.get('validation', {}).get('step_validations', []):
                status = "✓" if step_val['status'] == 'FOUND' else "✗"
                print(f"  {status} {step_val['tool_name']}: {step_val['status']}")

        return result

    except Exception as e:
        print(f"V2 test failed: {e}")
        import traceback
        traceback.print_exc()
        return None


def test_user_feedback():
    """Test V2 user feedback refinement."""
    print("\n" + "=" * 60)
    print("Testing V2 User Feedback Refinement")
    print("=" * 60)

    try:
        from propose_validate_v2_experimental import ProposeValidateV2Experimental

        generator = ProposeValidateV2Experimental()
        generator._llm_client = MockLLMClient()

        # Generate initial workflow
        result = generator.generate_workflow(
            user_intent="RNA-seq differential expression analysis"
        )

        if not result['success']:
            print("Initial generation failed")
            return

        print(f"Initial workflow generated with {len(result['workflow']['steps'])} steps")

        # Simulate user feedback
        feedback_result = generator.refine_with_user_feedback(
            workflow=result['workflow'],
            user_feedback="Use Salmon instead of HISAT2 for faster quantification"
        )

        print(f"\nFeedback refinement:")
        print(f"  Success: {feedback_result['success']}")
        if feedback_result['success']:
            print(f"  Applied: {feedback_result.get('feedback_applied')}")
            print(f"  New confidence: {feedback_result['validation']['confidence']:.2f}")

    except Exception as e:
        print(f"User feedback test failed: {e}")
        import traceback
        traceback.print_exc()


def compare_results(v1_result, v2_result):
    """Compare V1 and V2 results."""
    print("\n" + "=" * 60)
    print("Comparison Summary")
    print("=" * 60)

    if not v1_result or not v2_result:
        print("Cannot compare - one or both tests failed")
        return

    print(f"\n{'Metric':<30} {'V1':<15} {'V2':<15}")
    print("-" * 60)

    metrics = [
        ('Success', v1_result['success'], v2_result['success']),
        ('Confidence', f"{v1_result.get('confidence', 0):.2f}",
         f"{v2_result.get('confidence', 0):.2f}"),
        ('All Tools Available',
         str(v1_result.get('all_tools_available', False)),
         str(v2_result.get('all_tools_available', False))),
        ('Iterations',
         str(len(v1_result.get('refinement_history', []))),
         str(v2_result.get('iterations', 0))),
        ('Context Search', 'No', 'Yes'),
        ('User Feedback Support', 'No', 'Yes'),
    ]

    for metric, v1, v2 in metrics:
        print(f"{metric:<30} {str(v1):<15} {str(v2):<15}")

    print("\n" + "=" * 60)


def main():
    print("\n" + "#" * 60)
    print("# ProposeValidate V1 vs V2 Comparison Test")
    print("#" * 60)

    # Run tests
    v1_result = test_v1()
    v2_result = test_v2()

    # Compare
    compare_results(v1_result, v2_result)

    # Test user feedback (V2 only)
    test_user_feedback()

    print("\n" + "#" * 60)
    print("# Tests Complete")
    print("#" * 60)


if __name__ == '__main__':
    main()
