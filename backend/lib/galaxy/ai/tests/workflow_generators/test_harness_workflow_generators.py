#!/usr/bin/env python
"""
Test Harness: Workflow Generator Comparison

Compares three workflow generation approaches:
1. Original: GalaxyWorkflowGenerator (constrained, search-first)
2. V1: ProposeValidateWorkflowGenerator (propose then validate)
3. V2: ProposeValidateV2Experimental (propose with context search)

Metrics compared:
- Success rate
- Tool availability (are all tools found in index?)
- Confidence score
- Number of LLM calls
- Generation time
- Workflow quality (step count, structure)
"""

import json
import time
import sys
import os
from typing import Dict, List, Any, Optional
from dataclasses import dataclass, field

# Ensure we can import from the package
# Navigate: tests/workflow_generators -> tests -> ai -> galaxy -> lib -> backend
backend_path = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..', '..', '..'))
sys.path.insert(0, backend_path)


@dataclass
class TestResult:
    """Result of a single test run."""
    approach: str
    test_case: str
    success: bool
    confidence: float = 0.0
    all_tools_available: bool = False
    step_count: int = 0
    llm_calls: int = 0
    time_seconds: float = 0.0
    error: Optional[str] = None
    workflow: Optional[Dict] = None
    tool_statuses: List[Dict] = field(default_factory=list)


@dataclass
class TestCase:
    """A test case for workflow generation."""
    name: str
    intent: str
    expected_domain: str
    min_steps: int = 2
    data_characteristics: Dict = field(default_factory=dict)


# Define test cases
TEST_CASES = [
    TestCase(
        name="RNA-seq DE Analysis",
        intent="RNA-seq differential expression analysis comparing treatment vs control",
        expected_domain="transcriptomics",
        min_steps=3
    ),
    TestCase(
        name="Variant Calling",
        intent="Call variants from whole genome sequencing data",
        expected_domain="variant_calling",
        min_steps=3
    ),
    TestCase(
        name="ChIP-seq Peak Calling",
        intent="ChIP-seq analysis to identify transcription factor binding sites",
        expected_domain="chip_seq",
        min_steps=3
    ),
    TestCase(
        name="Simple QC",
        intent="Quality control analysis of FASTQ files",
        expected_domain="generic",
        min_steps=1
    ),
    TestCase(
        name="Metagenomics",
        intent="Taxonomic classification of metagenomic shotgun sequencing data",
        expected_domain="metagenomics",
        min_steps=2
    ),
]


class MockLLMClient:
    """Mock LLM for testing without API calls."""

    def __init__(self):
        self.call_count = 0

    def generate(self, prompt: str, max_tokens: int = 1000) -> str:
        self.call_count += 1

        # Determine response based on prompt content
        if "rna-seq" in prompt.lower() or "differential expression" in prompt.lower():
            return self._rna_seq_response(prompt)
        elif "variant" in prompt.lower() or "snp" in prompt.lower():
            return self._variant_response(prompt)
        elif "chip-seq" in prompt.lower() or "peak" in prompt.lower():
            return self._chipseq_response(prompt)
        elif "metagenomic" in prompt.lower() or "taxonomic" in prompt.lower():
            return self._metagenomics_response(prompt)
        else:
            return self._generic_response(prompt)

    def _rna_seq_response(self, prompt: str) -> str:
        # If prompt mentions available tools, use them
        if "AVAILABLE TOOLS" in prompt:
            tools = ["FastQC", "HISAT2", "featureCounts", "DESeq2"]
        else:
            tools = ["FastQC", "STAR", "htseq-count", "DESeq2"]

        return json.dumps({
            "workflow_name": "RNA-seq Differential Expression",
            "description": "Complete RNA-seq DE analysis pipeline",
            "steps": [
                {"step": i+1, "tool_name": tool, "purpose": f"Step {i+1}",
                 "key_parameters": {}, "justification": "Best practice"}
                for i, tool in enumerate(tools)
            ]
        })

    def _variant_response(self, prompt: str) -> str:
        if "AVAILABLE TOOLS" in prompt:
            tools = ["FastQC", "BWA", "SAMtools", "BCFtools"]
        else:
            tools = ["FastQC", "BWA-MEM2", "GATK", "VCFtools"]

        return json.dumps({
            "workflow_name": "Variant Calling Pipeline",
            "description": "WGS variant calling",
            "steps": [
                {"step": i+1, "tool_name": tool, "purpose": f"Step {i+1}",
                 "key_parameters": {}, "justification": "Standard"}
                for i, tool in enumerate(tools)
            ]
        })

    def _chipseq_response(self, prompt: str) -> str:
        if "AVAILABLE TOOLS" in prompt:
            tools = ["FastQC", "Bowtie2", "SAMtools", "MACS2"]
        else:
            tools = ["FastQC", "Bowtie2", "Picard", "MACS2"]

        return json.dumps({
            "workflow_name": "ChIP-seq Peak Calling",
            "description": "ChIP-seq analysis",
            "steps": [
                {"step": i+1, "tool_name": tool, "purpose": f"Step {i+1}",
                 "key_parameters": {}, "justification": "Standard"}
                for i, tool in enumerate(tools)
            ]
        })

    def _metagenomics_response(self, prompt: str) -> str:
        if "AVAILABLE TOOLS" in prompt:
            tools = ["FastQC", "Trimmomatic", "Kraken2"]
        else:
            tools = ["FastQC", "Trimmomatic", "MetaPhlAn"]

        return json.dumps({
            "workflow_name": "Metagenomics Classification",
            "description": "Taxonomic classification",
            "steps": [
                {"step": i+1, "tool_name": tool, "purpose": f"Step {i+1}",
                 "key_parameters": {}, "justification": "Standard"}
                for i, tool in enumerate(tools)
            ]
        })

    def _generic_response(self, prompt: str) -> str:
        return json.dumps({
            "workflow_name": "Generic Analysis",
            "description": "Basic analysis",
            "steps": [
                {"step": 1, "tool_name": "FastQC", "purpose": "Quality control",
                 "key_parameters": {}, "justification": "Standard QC"}
            ]
        })


class WorkflowGeneratorTestHarness:
    """Test harness for comparing workflow generators."""

    def __init__(self, use_mock_llm: bool = True):
        self.use_mock_llm = use_mock_llm
        self.results: List[TestResult] = []

    def run_all_tests(self) -> Dict[str, Any]:
        """Run all test cases against all approaches."""
        print("\n" + "=" * 70)
        print("WORKFLOW GENERATOR TEST HARNESS")
        print("=" * 70)

        for test_case in TEST_CASES:
            print(f"\n--- Test Case: {test_case.name} ---")
            print(f"Intent: {test_case.intent[:60]}...")

            # Test each approach
            self._test_original(test_case)
            self._test_v1(test_case)
            self._test_v2(test_case)

        return self._generate_report()

    def _test_original(self, test_case: TestCase):
        """Test Original approach (GalaxyWorkflowGenerator)."""
        print(f"  [Original] Testing...")

        try:
            from lib.galaxy.ai.galaxy_workflow_generator import GalaxyWorkflowGenerator

            generator = GalaxyWorkflowGenerator()
            if self.use_mock_llm:
                generator.llm_client = MockLLMClient()

            start = time.time()
            result = generator.generate_workflow(
                user_intent=test_case.intent,
                max_tools_search=30
            )
            elapsed = time.time() - start

            llm_calls = generator.llm_client.call_count if hasattr(generator.llm_client, 'call_count') else 0

            if result.get('success'):
                steps = result.get('workflow_structure', {}).get('steps', [])
                self.results.append(TestResult(
                    approach="Original",
                    test_case=test_case.name,
                    success=True,
                    confidence=result.get('confidence', 0),
                    all_tools_available=True,  # Original uses search, so tools exist
                    step_count=len(steps),
                    llm_calls=llm_calls,
                    time_seconds=elapsed,
                    workflow=result.get('workflow_structure')
                ))
                print(f"  [Original] SUCCESS - {len(steps)} steps, {elapsed:.2f}s")
            else:
                self.results.append(TestResult(
                    approach="Original",
                    test_case=test_case.name,
                    success=False,
                    error=result.get('error', 'Unknown error'),
                    time_seconds=elapsed
                ))
                print(f"  [Original] FAILED - {result.get('error', 'Unknown')}")

        except Exception as e:
            self.results.append(TestResult(
                approach="Original",
                test_case=test_case.name,
                success=False,
                error=str(e)
            ))
            print(f"  [Original] ERROR - {e}")

    def _test_v1(self, test_case: TestCase):
        """Test V1 approach (ProposeValidateWorkflowGenerator)."""
        print(f"  [V1] Testing...")

        try:
            from lib.galaxy.ai.propose_validate_workflow_generator import ProposeValidateWorkflowGenerator

            generator = ProposeValidateWorkflowGenerator()
            if self.use_mock_llm:
                generator.llm_client = MockLLMClient()

            start = time.time()
            result = generator.generate_workflow(
                user_intent=test_case.intent,
                data_characteristics=test_case.data_characteristics
            )
            elapsed = time.time() - start

            llm_calls = generator.llm_client.call_count if hasattr(generator.llm_client, 'call_count') else 0

            if result.get('success'):
                steps = result.get('workflow', {}).get('steps', [])
                validation = result.get('validation', {})

                # Get tool statuses
                tool_statuses = [
                    {'tool': s.get('proposed_tool'), 'status': s.get('tool_status')}
                    for s in validation.get('steps', [])
                ]

                self.results.append(TestResult(
                    approach="V1",
                    test_case=test_case.name,
                    success=True,
                    confidence=result.get('confidence', 0),
                    all_tools_available=result.get('all_tools_available', False),
                    step_count=len(steps),
                    llm_calls=llm_calls,
                    time_seconds=elapsed,
                    workflow=result.get('workflow'),
                    tool_statuses=tool_statuses
                ))
                print(f"  [V1] SUCCESS - {len(steps)} steps, conf={result.get('confidence', 0):.2f}, {elapsed:.2f}s")
            else:
                self.results.append(TestResult(
                    approach="V1",
                    test_case=test_case.name,
                    success=False,
                    error=result.get('error', 'Unknown error'),
                    time_seconds=elapsed
                ))
                print(f"  [V1] FAILED - {result.get('error', 'Unknown')}")

        except Exception as e:
            self.results.append(TestResult(
                approach="V1",
                test_case=test_case.name,
                success=False,
                error=str(e)
            ))
            print(f"  [V1] ERROR - {e}")

    def _test_v2(self, test_case: TestCase):
        """Test V2 approach (ProposeValidateV2Experimental)."""
        print(f"  [V2] Testing...")

        try:
            from lib.galaxy.ai.propose_validate_v2_experimental import ProposeValidateV2Experimental

            generator = ProposeValidateV2Experimental()
            if self.use_mock_llm:
                generator._llm_client = MockLLMClient()

            start = time.time()
            result = generator.generate_workflow(
                user_intent=test_case.intent,
                data_characteristics=test_case.data_characteristics
            )
            elapsed = time.time() - start

            llm_calls = generator._llm_client.call_count if hasattr(generator._llm_client, 'call_count') else 0

            if result.get('success'):
                steps = result.get('workflow', {}).get('steps', [])
                validation = result.get('validation', {})
                context = result.get('context_used', {})

                # Get tool statuses
                tool_statuses = [
                    {'tool': s.get('tool_name'), 'status': s.get('status')}
                    for s in validation.get('step_validations', [])
                ]

                self.results.append(TestResult(
                    approach="V2",
                    test_case=test_case.name,
                    success=True,
                    confidence=result.get('confidence', 0),
                    all_tools_available=result.get('all_tools_available', False),
                    step_count=len(steps),
                    llm_calls=llm_calls,
                    time_seconds=elapsed,
                    workflow=result.get('workflow'),
                    tool_statuses=tool_statuses
                ))
                ctx_info = f"ctx:{context.get('similar_workflows', 0)}wf,{context.get('available_tools', 0)}tools"
                print(f"  [V2] SUCCESS - {len(steps)} steps, conf={result.get('confidence', 0):.2f}, {ctx_info}, {elapsed:.2f}s")
            else:
                self.results.append(TestResult(
                    approach="V2",
                    test_case=test_case.name,
                    success=False,
                    error=result.get('error', 'Unknown error'),
                    time_seconds=elapsed
                ))
                print(f"  [V2] FAILED - {result.get('error', 'Unknown')}")

        except Exception as e:
            self.results.append(TestResult(
                approach="V2",
                test_case=test_case.name,
                success=False,
                error=str(e)
            ))
            print(f"  [V2] ERROR - {e}")

    def _generate_report(self) -> Dict[str, Any]:
        """Generate comparison report."""
        print("\n" + "=" * 70)
        print("COMPARISON REPORT")
        print("=" * 70)

        # Group by approach
        by_approach = {}
        for result in self.results:
            if result.approach not in by_approach:
                by_approach[result.approach] = []
            by_approach[result.approach].append(result)

        # Calculate metrics per approach
        summary = {}
        for approach, results in by_approach.items():
            successful = [r for r in results if r.success]
            summary[approach] = {
                'total_tests': len(results),
                'successful': len(successful),
                'success_rate': len(successful) / len(results) if results else 0,
                'avg_confidence': sum(r.confidence for r in successful) / len(successful) if successful else 0,
                'avg_steps': sum(r.step_count for r in successful) / len(successful) if successful else 0,
                'avg_llm_calls': sum(r.llm_calls for r in successful) / len(successful) if successful else 0,
                'avg_time': sum(r.time_seconds for r in successful) / len(successful) if successful else 0,
                'tools_available_rate': sum(1 for r in successful if r.all_tools_available) / len(successful) if successful else 0
            }

        # Print summary table
        print(f"\n{'Metric':<25} {'Original':<15} {'V1':<15} {'V2':<15}")
        print("-" * 70)

        metrics = [
            ('Success Rate', 'success_rate', '{:.0%}'),
            ('Avg Confidence', 'avg_confidence', '{:.2f}'),
            ('Avg Steps', 'avg_steps', '{:.1f}'),
            ('Avg LLM Calls', 'avg_llm_calls', '{:.1f}'),
            ('Avg Time (s)', 'avg_time', '{:.3f}'),
            ('Tools Available Rate', 'tools_available_rate', '{:.0%}'),
        ]

        for label, key, fmt in metrics:
            row = f"{label:<25}"
            for approach in ['Original', 'V1', 'V2']:
                if approach in summary:
                    val = summary[approach].get(key, 0)
                    row += f"{fmt.format(val):<15}"
                else:
                    row += f"{'N/A':<15}"
            print(row)

        # Print detailed results
        print("\n" + "-" * 70)
        print("DETAILED RESULTS")
        print("-" * 70)

        for test_case in TEST_CASES:
            print(f"\n{test_case.name}:")
            for result in self.results:
                if result.test_case == test_case.name:
                    status = "✓" if result.success else "✗"
                    if result.success:
                        tools_status = "✓" if result.all_tools_available else "~"
                        print(f"  {status} {result.approach:<10} conf={result.confidence:.2f} "
                              f"steps={result.step_count} tools={tools_status} "
                              f"llm={result.llm_calls} time={result.time_seconds:.2f}s")
                    else:
                        print(f"  {status} {result.approach:<10} ERROR: {result.error[:40]}")

        return {
            'summary': summary,
            'results': [
                {
                    'approach': r.approach,
                    'test_case': r.test_case,
                    'success': r.success,
                    'confidence': r.confidence,
                    'all_tools_available': r.all_tools_available,
                    'step_count': r.step_count,
                    'llm_calls': r.llm_calls,
                    'time_seconds': r.time_seconds,
                    'error': r.error
                }
                for r in self.results
            ]
        }


def main():
    """Run the test harness."""
    harness = WorkflowGeneratorTestHarness(use_mock_llm=True)
    report = harness.run_all_tests()

    # Save report
    report_path = os.path.join(os.path.dirname(__file__), 'test_harness_report.json')
    with open(report_path, 'w') as f:
        json.dump(report, f, indent=2)
    print(f"\nReport saved to: {report_path}")

    return report


if __name__ == '__main__':
    main()
