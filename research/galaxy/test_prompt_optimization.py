#!/usr/bin/env python3
"""
Test script to verify the optimized LLM prompt for workflow generation.
"""

import sys
sys.path.insert(0, 'lib')

from galaxy.ai.workflow_generator import WorkflowGenerator
from galaxy.ai.config import DEFAULT_AI_CONFIG

def test_prompt_optimization():
    """Test the optimized workflow generation prompt."""

    # Initialize workflow generator
    generator = WorkflowGenerator(config=DEFAULT_AI_CONFIG)

    # Test prompt generation
    user_request = "I want to analyze RNA-seq data from different conditions to find differentially expressed genes"

    # Sample context (similar workflows)
    context = """Similar workflows found:
1. Basic RNA-seq Pipeline:
   - FastQC quality control
   - HISAT2 alignment
   - featureCounts quantification
   - DESeq2 analysis

2. Advanced Transcriptome Analysis:
   - Trimmomatic preprocessing
   - STAR alignment
   - StringTie assembly
   - Ballgown differential expression
"""

    # Generate the prompt
    prompt = generator._create_workflow_generation_prompt(user_request, context)

    print("=== OPTIMIZED PROMPT FOR WORKFLOW GENERATION ===\n")
    print(prompt)
    print("\n" + "="*60)

    # Check if key anti-imitation phrases are present
    anti_imitation_checks = [
        "DO NOT copy or replicate",
        "use them ONLY for understanding common patterns",
        "FOCUS PRIMARILY on the user's specific request",
        "Be creative and innovative",
        "CUSTOM solution, not a copy"
    ]

    print("\n=== ANTI-IMITATION FEATURES CHECK ===")
    for check in anti_imitation_checks:
        if check in prompt:
            print(f"✅ Found: '{check}'")
        else:
            print(f"❌ Missing: '{check}'")

    print(f"\n✅ Prompt optimization test completed!")
    print(f"📝 Total prompt length: {len(prompt)} characters")

    return prompt

if __name__ == "__main__":
    test_prompt_optimization()