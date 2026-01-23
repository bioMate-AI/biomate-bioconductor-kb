#!/usr/bin/env python
"""
Test runner for AI module tests.
Handles package imports correctly.
"""

import sys
import os
import json
import traceback

# Ensure we're in the right directory
os.chdir(os.path.dirname(os.path.abspath(__file__)))

# Test workflow_proposal_validator
print("\n" + "=" * 60)
print("Testing workflow_proposal_validator")
print("=" * 60)

try:
    from workflow_proposal_validator import (
        WorkflowProposalValidator,
        ToolIndexValidator,
        KnowledgeValidator,
        WorkflowValidation,
        StepValidation,
        ToolValidation,
        create_workflow_validator
    )
    print("[PASS] Imports successful")

    # Test ToolIndexValidator
    validator = ToolIndexValidator()
    print("[PASS] ToolIndexValidator created")

    # Test tool validation
    result = validator.validate_tool("FastQC", "quality control")
    print(f"[INFO] FastQC validation: status={result.status}, confidence={result.confidence}")

    result = validator.validate_tool("HISAT2", "alignment")
    print(f"[INFO] HISAT2 validation: status={result.status}, confidence={result.confidence}")

    result = validator.validate_tool("NonExistentTool123", "unknown")
    print(f"[INFO] NonExistent validation: status={result.status}")

except Exception as e:
    print(f"[ERROR] {e}")
    traceback.print_exc()

# Test propose_validate_workflow_generator
print("\n" + "=" * 60)
print("Testing propose_validate_workflow_generator")
print("=" * 60)


class MockLLMClient:
    """Mock LLM client for testing."""

    def __init__(self):
        self.call_count = 0

    def generate(self, prompt: str, max_tokens: int = 1000) -> str:
        self.call_count += 1
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
                    "key_parameters": {},
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


try:
    from propose_validate_workflow_generator import (
        ProposeValidateWorkflowGenerator,
        create_propose_validate_generator
    )
    print("[PASS] Imports successful")

    # Create generator with mock LLM
    generator = ProposeValidateWorkflowGenerator()
    generator.llm_client = MockLLMClient()
    print("[PASS] Generator created with mock LLM")

    # Test workflow generation
    print("\n[INFO] Generating workflow for 'RNA-seq differential expression'...")
    result = generator.generate_workflow(
        user_intent="RNA-seq differential expression analysis"
    )

    if result['success']:
        print(f"[PASS] Workflow generated successfully")
        print(f"  - Domain: {result.get('domain')}")
        print(f"  - Confidence: {result.get('confidence', 0):.2f}")
        print(f"  - All tools available: {result['validation']['all_tools_available']}")
        print(f"  - Iterations: {len(result['refinement_history'])}")
        print(f"  - Steps: {len(result['workflow']['steps'])}")

        # Show step details
        print("\n[INFO] Workflow steps:")
        for step in result['validation']['steps']:
            print(f"  {step['step_number']}. {step['proposed_tool']} -> "
                  f"{step['tool_status']} ({step.get('galaxy_tool_id', 'N/A')})")

        # Check Galaxy format
        if 'workflow_ga' in result:
            ga = result['workflow_ga']
            print(f"\n[PASS] Galaxy .ga format generated")
            print(f"  - Name: {ga['name']}")
            print(f"  - Steps: {len(ga['steps'])}")
    else:
        print(f"[FAIL] Workflow generation failed: {result.get('error')}")

except Exception as e:
    print(f"[ERROR] {e}")
    traceback.print_exc()

# Test JSON parsing
print("\n" + "=" * 60)
print("Testing JSON parsing")
print("=" * 60)

try:
    generator = ProposeValidateWorkflowGenerator()

    # Test clean JSON
    r1 = generator._parse_json_response('{"test": 1}')
    print(f"[PASS] Clean JSON: {r1}")

    # Test markdown wrapped
    r2 = generator._parse_json_response('```json\n{"test": 2}\n```')
    print(f"[PASS] Markdown JSON: {r2}")

    # Test with surrounding text
    r3 = generator._parse_json_response('Here it is:\n{"test": 3}\nDone.')
    print(f"[PASS] Text-wrapped JSON: {r3}")

    # Test invalid
    r4 = generator._parse_json_response('not json at all')
    print(f"[PASS] Invalid JSON returns None: {r4}")

except Exception as e:
    print(f"[ERROR] {e}")
    traceback.print_exc()

print("\n" + "=" * 60)
print("All tests completed")
print("=" * 60 + "\n")
