#!/usr/bin/env python
"""
Quick comparison of V1 vs V2 workflow generators.
Run from backend directory: python lib/galaxy/ai/tests/workflow_generators/quick_compare.py
"""

import sys
import os
import json
import time

# Add backend to path
backend_path = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..', '..', '..'))
sys.path.insert(0, backend_path)


class MockLLM:
    """Mock LLM for testing without API calls."""
    call_count = 0

    def generate(self, prompt, max_tokens=1000):
        self.call_count += 1
        # If V2 style prompt with context, use available tools
        if 'AVAILABLE TOOLS' in prompt:
            tools = ['FastQC', 'HISAT2', 'featureCounts', 'DESeq2']
        else:
            tools = ['FastQC', 'STAR', 'htseq-count', 'DESeq2']

        return json.dumps({
            'workflow_name': 'Test RNA-seq Pipeline',
            'description': 'RNA-seq differential expression analysis',
            'steps': [
                {'step': i+1, 'tool_name': t, 'purpose': f'Step {i+1}',
                 'key_parameters': {}, 'justification': 'Standard tool'}
                for i, t in enumerate(tools)
            ]
        })


def test_v1(intent):
    """Test V1 approach."""
    from lib.galaxy.ai.propose_validate_workflow_generator import ProposeValidateWorkflowGenerator

    gen = ProposeValidateWorkflowGenerator()
    gen.llm_client = MockLLM()

    start = time.time()
    result = gen.generate_workflow(user_intent=intent)
    elapsed = time.time() - start

    return {
        'success': result['success'],
        'steps': len(result.get('workflow', {}).get('steps', [])),
        'confidence': result.get('confidence', 0),
        'all_tools_available': result.get('all_tools_available', False),
        'time': elapsed,
        'llm_calls': gen.llm_client.call_count,
        'iterations': len(result.get('refinement_history', []))
    }


def test_v2(intent):
    """Test V2 approach."""
    from lib.galaxy.ai.propose_validate_v2_experimental import ProposeValidateV2Experimental

    gen = ProposeValidateV2Experimental()
    gen._llm_client = MockLLM()

    start = time.time()
    result = gen.generate_workflow(user_intent=intent)
    elapsed = time.time() - start

    ctx = result.get('context_used', {})
    return {
        'success': result['success'],
        'steps': len(result.get('workflow', {}).get('steps', [])),
        'confidence': result.get('confidence', 0),
        'all_tools_available': result.get('all_tools_available', False),
        'time': elapsed,
        'llm_calls': gen._llm_client.call_count,
        'iterations': result.get('iterations', 0),
        'context_workflows': ctx.get('similar_workflows', 0),
        'context_tools': ctx.get('available_tools', 0)
    }


def main():
    print("=" * 60)
    print("Workflow Generator Comparison: V1 vs V2")
    print("=" * 60)

    intents = [
        "RNA-seq differential expression analysis",
        "Variant calling from whole genome sequencing",
        "ChIP-seq peak calling analysis",
    ]

    for intent in intents:
        print(f"\nIntent: {intent[:50]}...")
        print("-" * 60)

        v1 = test_v1(intent)
        v2 = test_v2(intent)

        print(f"{'Metric':<25} {'V1':<15} {'V2':<15}")
        print("-" * 55)
        print(f"{'Success':<25} {str(v1['success']):<15} {str(v2['success']):<15}")
        print(f"{'Steps':<25} {v1['steps']:<15} {v2['steps']:<15}")
        print(f"{'Confidence':<25} {v1['confidence']:.2f}{'':<13} {v2['confidence']:.2f}")
        print(f"{'Tools Available':<25} {str(v1['all_tools_available']):<15} {str(v2['all_tools_available']):<15}")
        print(f"{'Time (s)':<25} {v1['time']:.3f}{'':<12} {v2['time']:.3f}")
        print(f"{'LLM Calls':<25} {v1['llm_calls']:<15} {v2['llm_calls']:<15}")
        print(f"{'Iterations':<25} {v1['iterations']:<15} {v2['iterations']:<15}")
        if 'context_workflows' in v2:
            print(f"{'Context (wf/tools)':<25} {'N/A':<15} {v2['context_workflows']}/{v2['context_tools']}")

    print("\n" + "=" * 60)
    print("Key: V2 gathers context (workflows + tools) before proposing")
    print("=" * 60)


if __name__ == '__main__':
    main()
