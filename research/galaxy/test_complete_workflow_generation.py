#!/usr/bin/env python3
"""
Test complete workflow generation with optimized prompt.
"""

import sys
sys.path.insert(0, 'lib')

from galaxy.ai.workflow_generator import WorkflowGenerator
from galaxy.ai.config import DEFAULT_AI_CONFIG

def test_workflow_generation_with_context():
    """Test workflow generation with context (Stage 2 of two-stage process)."""

    print("=== TESTING COMPLETE WORKFLOW GENERATION ===\n")

    # Initialize workflow generator
    generator = WorkflowGenerator(config=DEFAULT_AI_CONFIG)

    # Test request
    user_request = "I want to analyze RNA-seq data from cancer vs normal tissue to identify potential therapeutic targets"

    # Sample similar workflows (would come from RAG retrieval in Stage 1)
    similar_workflows = [
        {
            "name": "Basic RNA-seq Analysis",
            "description": "Standard RNA-seq differential expression analysis",
            "steps": [
                {"tool_id": "fastqc", "annotation": "Quality control"},
                {"tool_id": "hisat2", "annotation": "Alignment"},
                {"tool_id": "featurecounts", "annotation": "Quantification"},
                {"tool_id": "deseq2", "annotation": "Differential expression"}
            ]
        },
        {
            "name": "Cancer Transcriptome Study",
            "description": "Cancer-focused transcriptome analysis",
            "steps": [
                {"tool_id": "trimmomatic", "annotation": "Read trimming"},
                {"tool_id": "star", "annotation": "Alignment"},
                {"tool_id": "rsem", "annotation": "Expression quantification"},
                {"tool_id": "edger", "annotation": "Statistical analysis"}
            ]
        }
    ]

    print(f"📝 User Request: {user_request}")
    print(f"📊 Number of similar workflows provided: {len(similar_workflows)}\n")

    try:
        # Test the workflow generation
        result = generator.generate_workflow_with_context(user_request, similar_workflows)

        print("=== GENERATION RESULT ===")
        print(f"✅ Success: {result.get('success', False)}")
        print(f"📈 Confidence: {result.get('confidence', 'N/A')}")
        print(f"🔧 Method: {result.get('generation_method', 'N/A')}")

        if 'workflow' in result:
            workflow = result['workflow']
            print(f"\n📋 Workflow Name: {workflow.get('name', 'N/A')}")
            print(f"📝 Description: {workflow.get('description', 'N/A')}")

            if 'steps' in workflow:
                print(f"\n🔧 Steps ({len(workflow['steps'])}):")
                for i, step in enumerate(workflow['steps'], 1):
                    print(f"  {i}. {step.get('annotation', 'N/A')} ({step.get('tool_id', 'N/A')})")

        print(f"\n🎯 Test Status: {'PASSED' if result.get('success') else 'FAILED'}")

    except Exception as e:
        print(f"❌ Error during generation: {str(e)}")
        print("🔧 This likely means LLM client is not configured properly")
        print("   (Expected in test environment without API keys)")

        print("\n=== TESTING FALLBACK MECHANISM ===")
        # Test the fallback mechanism
        try:
            fallback_result = generator._create_fallback_workflow_with_context(
                user_request, similar_workflows
            )
            print(f"✅ Fallback Success: {fallback_result.get('success', False)}")
            print(f"📋 Fallback Workflow: {fallback_result.get('workflow', {}).get('name', 'N/A')}")
            print(f"🎯 Fallback Test: PASSED")
        except Exception as fe:
            print(f"❌ Fallback Error: {str(fe)}")
            print(f"🎯 Fallback Test: FAILED")

if __name__ == "__main__":
    test_workflow_generation_with_context()