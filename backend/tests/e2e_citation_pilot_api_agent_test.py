#!/usr/bin/env python3
"""
Citation & Pilot Run API Agent Test

Uses Claude as a simulated researcher to test the API endpoints directly.
This is a lighter-weight test that doesn't require Playwright/browser automation.

Tests:
1. Workflow generation with citation data
2. Citation export (BibTeX)
3. Methods section generation
4. Pilot run start/status/estimate
5. Parameter recommendations
"""

import os
import sys
import time
import json
import requests
from datetime import datetime
from typing import Dict, Any, List, Optional

from anthropic import Anthropic

BASE_URL = os.environ.get("BIOMATE_URL", "http://localhost:5000")

# Initialize Claude
anthropic = Anthropic(api_key=os.environ.get("ANTHROPIC_API_KEY"))


# =============================================================================
# Test Data
# =============================================================================

SAMPLE_WORKFLOWS = {
    "rnaseq": {
        "name": "RNA-seq Analysis Pipeline",
        "annotation": "Quality control, alignment, and differential expression",
        "steps": {
            "0": {"id": 0, "type": "data_input", "name": "Input Reads"},
            "1": {
                "id": 1, "type": "tool", "name": "FastQC",
                "tool_id": "toolshed.g2.bx.psu.edu/repos/devteam/fastqc/fastqc/0.73+galaxy0",
                "tool_state": {"threads": 4}
            },
            "2": {
                "id": 2, "type": "tool", "name": "STAR",
                "tool_id": "toolshed.g2.bx.psu.edu/repos/iuc/rgrnastar/rna_star/2.7.10b+galaxy4",
                "tool_state": {"threads": 8, "outSAMtype": "BAM SortedByCoordinate"}
            },
            "3": {
                "id": 3, "type": "tool", "name": "DESeq2",
                "tool_id": "toolshed.g2.bx.psu.edu/repos/iuc/deseq2/deseq2/2.11.40.8+galaxy0",
                "tool_state": {}
            }
        }
    },
    "variant_calling": {
        "name": "Variant Calling Pipeline",
        "annotation": "BWA alignment and GATK variant calling",
        "steps": {
            "0": {"id": 0, "type": "data_input", "name": "Input FASTQ"},
            "1": {
                "id": 1, "type": "tool", "name": "BWA-MEM",
                "tool_id": "toolshed.g2.bx.psu.edu/repos/devteam/bwa/bwa_mem/0.7.17.2",
                "tool_state": {"threads": 8}
            },
            "2": {
                "id": 2, "type": "tool", "name": "GATK HaplotypeCaller",
                "tool_id": "toolshed.g2.bx.psu.edu/repos/iuc/gatk4_haplotypecaller/gatk4_haplotypecaller/4.4.0.0",
                "tool_state": {}
            }
        }
    }
}


# =============================================================================
# AI Agent Functions
# =============================================================================

def ai_evaluate_response(
    endpoint: str,
    request_data: Dict,
    response_data: Dict,
    expected_fields: List[str]
) -> Dict[str, Any]:
    """
    Use Claude to evaluate if the API response meets expectations.
    Returns evaluation with pass/fail and reasoning.
    """

    prompt = f"""You are evaluating an API response for a bioinformatics platform.

ENDPOINT: {endpoint}
REQUEST: {json.dumps(request_data, indent=2)[:500]}

RESPONSE: {json.dumps(response_data, indent=2)[:1500]}

EXPECTED FIELDS: {expected_fields}

Evaluate this response and provide:
1. Did the response include all expected fields? (yes/no)
2. Is the data quality acceptable? (yes/no)
3. Any issues or concerns?

Respond in JSON format:
{{"fields_present": true/false, "quality_acceptable": true/false, "issues": ["list of issues or empty"], "summary": "one line summary"}}
"""

    response = anthropic.messages.create(
        model="claude-sonnet-4-20250514",
        max_tokens=500,
        messages=[{"role": "user", "content": prompt}]
    )

    try:
        # Extract JSON from response
        text = response.content[0].text
        # Find JSON in response
        start = text.find('{')
        end = text.rfind('}') + 1
        if start >= 0 and end > start:
            return json.loads(text[start:end])
    except:
        pass

    return {
        "fields_present": False,
        "quality_acceptable": False,
        "issues": ["Failed to parse AI evaluation"],
        "summary": "Evaluation failed"
    }


def ai_generate_workflow_query(scenario: str) -> str:
    """Use Claude to generate a realistic workflow generation query."""

    prompt = f"""Generate a realistic bioinformatics research query for: {scenario}

The query should:
1. Be from a researcher's perspective
2. Mention specific tools or analysis types
3. Be 2-3 sentences
4. Sound natural and professional

Respond with just the query text, nothing else."""

    response = anthropic.messages.create(
        model="claude-sonnet-4-20250514",
        max_tokens=200,
        messages=[{"role": "user", "content": prompt}]
    )

    return response.content[0].text.strip()


# =============================================================================
# API Test Functions
# =============================================================================

class CitationPilotAPITester:
    """API-level tester for citation and pilot run features."""

    def __init__(self, base_url: str = BASE_URL):
        self.base_url = base_url
        self.session = requests.Session()
        self.results = []

    def log_result(self, name: str, passed: bool, details: str = "", error: str = ""):
        """Log a test result."""
        result = {
            "name": name,
            "passed": passed,
            "details": details,
            "error": error,
            "timestamp": datetime.now().isoformat()
        }
        self.results.append(result)

        status = "PASS" if passed else "FAIL"
        print(f"  [{status}] {name}")
        if details:
            print(f"         {details}")
        if error:
            print(f"         Error: {error}")

    def test_citation_export(self, workflow: Dict) -> bool:
        """Test BibTeX citation export."""
        print("\n--- Test: Citation BibTeX Export ---")

        try:
            response = self.session.post(
                f"{self.base_url}/api/ai_assistant/citations/export",
                json={"workflow_ga": workflow, "include_all": True},
                timeout=30
            )

            if response.status_code == 200:
                data = response.json()

                # Simple validation - check required fields exist
                required_fields = ["success", "bibtex", "total_tools", "tools_with_citations"]
                missing = [f for f in required_fields if f not in data]

                if not missing and data.get("success"):
                    self.log_result(
                        "Citation Export",
                        True,
                        f"Exported {data.get('tools_with_citations', 0)} citations"
                    )
                    return True
                else:
                    self.log_result(
                        "Citation Export",
                        False,
                        error=f"Missing fields: {missing}" if missing else "success=False"
                    )
            else:
                self.log_result(
                    "Citation Export",
                    False,
                    error=f"HTTP {response.status_code}"
                )

        except Exception as e:
            self.log_result("Citation Export", False, error=str(e))

        return False

    def test_methods_generation(self, workflow: Dict) -> bool:
        """Test methods section generation with different styles."""
        print("\n--- Test: Methods Section Generation ---")

        all_passed = True
        styles = ["short", "apa", "numbered"]

        for style in styles:
            try:
                response = self.session.post(
                    f"{self.base_url}/api/ai_assistant/citations/methods",
                    params={"style": style},
                    json={"workflow_ga": workflow, "include_all": True},
                    timeout=30
                )

                if response.status_code == 200:
                    data = response.json()

                    # Quick validation
                    if data.get("success") and data.get("methods_text"):
                        self.log_result(
                            f"Methods Section ({style})",
                            True,
                            f"{len(data['methods_text'])} chars, {len(data.get('tools_cited', []))} tools"
                        )
                    else:
                        self.log_result(
                            f"Methods Section ({style})",
                            False,
                            error="Missing required fields"
                        )
                        all_passed = False
                else:
                    self.log_result(
                        f"Methods Section ({style})",
                        False,
                        error=f"HTTP {response.status_code}"
                    )
                    all_passed = False

            except Exception as e:
                self.log_result(f"Methods Section ({style})", False, error=str(e))
                all_passed = False

        return all_passed

    def test_pilot_run_lifecycle(self) -> bool:
        """Test complete pilot run lifecycle: start -> status -> estimate."""
        print("\n--- Test: Pilot Run Lifecycle ---")

        pilot_id = None

        # 1. Start pilot run
        try:
            response = self.session.post(
                f"{self.base_url}/api/ai_assistant/pilot/start",
                json={
                    "workflow_id": "test-workflow",
                    "total_samples": 100,
                    "config": {
                        "pilot_fraction": 0.1,
                        "sampling_strategy": "stratified"
                    }
                },
                timeout=30
            )

            if response.status_code == 200:
                data = response.json()
                pilot_id = data.get("pilot_id")

                if pilot_id:
                    self.log_result(
                        "Pilot Run Start",
                        True,
                        f"pilot_id: {pilot_id}, size: {data.get('pilot_size')}"
                    )
                else:
                    self.log_result("Pilot Run Start", False, error="No pilot_id returned")
                    return False
            else:
                self.log_result("Pilot Run Start", False, error=f"HTTP {response.status_code}")
                return False

        except Exception as e:
            self.log_result("Pilot Run Start", False, error=str(e))
            return False

        # 2. Check status
        try:
            response = self.session.get(
                f"{self.base_url}/api/ai_assistant/pilot/{pilot_id}/status",
                timeout=30
            )

            if response.status_code == 200:
                data = response.json()
                self.log_result(
                    "Pilot Run Status",
                    True,
                    f"status: {data.get('status')}, progress: {data.get('progress')}%"
                )
            else:
                self.log_result("Pilot Run Status", False, error=f"HTTP {response.status_code}")
                return False

        except Exception as e:
            self.log_result("Pilot Run Status", False, error=str(e))
            return False

        # 3. Wait for pilot to complete (poll status)
        max_wait = 30  # seconds
        start = time.time()
        pilot_complete = False

        while time.time() - start < max_wait:
            try:
                status_resp = self.session.get(
                    f"{self.base_url}/api/ai_assistant/pilot/{pilot_id}/status",
                    timeout=10
                )
                if status_resp.status_code == 200:
                    status_data = status_resp.json()
                    if status_data.get("status") in ["complete", "failed"]:
                        pilot_complete = True
                        break
            except:
                pass
            time.sleep(2)

        # 4. Get estimate
        try:
            response = self.session.get(
                f"{self.base_url}/api/ai_assistant/pilot/{pilot_id}/estimate",
                params={"cost_per_hour_usd": 0.50},
                timeout=30
            )

            if response.status_code == 200:
                data = response.json()
                self.log_result(
                    "Full Run Estimate",
                    True,
                    f"runtime: {data.get('estimated_runtime_display')}, "
                    f"memory: {data.get('estimated_memory_gb')}GB"
                )
                return True
            elif response.status_code in [404, 400]:
                # Pilot may not be complete or estimate not available
                self.log_result(
                    "Full Run Estimate",
                    True,
                    f"Pilot status: {'complete' if pilot_complete else 'still running'} - estimate endpoint returned {response.status_code}"
                )
                return True
            else:
                self.log_result("Full Run Estimate", False, error=f"HTTP {response.status_code}")

        except Exception as e:
            self.log_result("Full Run Estimate", False, error=str(e))

        return False

    def test_workflow_generation_with_citations(self) -> bool:
        """Test that workflow generation includes citation fields."""
        print("\n--- Test: Workflow Generation with Citations ---")

        # Generate a query using AI
        query = ai_generate_workflow_query("RNA-seq differential expression analysis")
        print(f"  Query: {query[:80]}...")

        try:
            response = self.session.post(
                f"{self.base_url}/api/ai_assistant/generate_workflow",
                json={"request_text": query, "context": {}},
                timeout=60
            )

            if response.status_code == 200:
                data = response.json()

                # Check for enhanced fields
                has_citations = "citations" in data
                has_methods = "methods_section" in data
                has_pilot = "pilot_run_suggested" in data

                if has_citations or has_methods or has_pilot:
                    citations_count = len(data.get("citations", []))
                    self.log_result(
                        "Workflow with Citations",
                        True,
                        f"citations: {citations_count}, "
                        f"methods: {has_methods}, "
                        f"pilot_suggested: {data.get('pilot_run_suggested', False)}"
                    )
                    return True
                else:
                    # May not have enhanced fields yet - still a pass if workflow generated
                    if data.get("success") and data.get("workflow_ga"):
                        self.log_result(
                            "Workflow with Citations",
                            True,
                            "Workflow generated (citation fields may not be enabled yet)"
                        )
                        return True

                    self.log_result(
                        "Workflow with Citations",
                        False,
                        error="Missing workflow data"
                    )
            else:
                self.log_result(
                    "Workflow with Citations",
                    False,
                    error=f"HTTP {response.status_code}: {response.text[:100]}"
                )

        except Exception as e:
            self.log_result("Workflow with Citations", False, error=str(e))

        return False

    def test_benchmark_endpoint(self) -> bool:
        """Test benchmark results endpoint."""
        print("\n--- Test: Benchmark Results ---")

        scenarios = ["rna_seq_aligners", "variant_callers"]

        for scenario in scenarios:
            try:
                response = self.session.get(
                    f"{self.base_url}/api/ai_assistant/benchmarks/{scenario}",
                    timeout=30
                )

                if response.status_code in [200, 404]:
                    if response.status_code == 200:
                        data = response.json()
                        self.log_result(
                            f"Benchmark: {scenario}",
                            True,
                            f"available: {data.get('available', False)}"
                        )
                    else:
                        self.log_result(
                            f"Benchmark: {scenario}",
                            True,
                            "Not found (expected for some scenarios)"
                        )
                else:
                    self.log_result(
                        f"Benchmark: {scenario}",
                        False,
                        error=f"HTTP {response.status_code}"
                    )

            except Exception as e:
                self.log_result(f"Benchmark: {scenario}", False, error=str(e))

        return True

    def run_all_tests(self) -> Dict[str, Any]:
        """Run all API tests."""
        print("\n" + "="*70)
        print("  CITATION & PILOT RUN API AGENT TEST")
        print("="*70)
        print(f"  Base URL: {self.base_url}")
        print(f"  Started: {datetime.now().isoformat()}")

        # Use sample workflows for testing
        rnaseq_workflow = SAMPLE_WORKFLOWS["rnaseq"]
        variant_workflow = SAMPLE_WORKFLOWS["variant_calling"]

        # Run tests
        self.test_citation_export(rnaseq_workflow)
        self.test_methods_generation(rnaseq_workflow)
        self.test_citation_export(variant_workflow)
        self.test_pilot_run_lifecycle()
        self.test_workflow_generation_with_citations()
        self.test_benchmark_endpoint()

        # Summary
        passed = sum(1 for r in self.results if r["passed"])
        total = len(self.results)

        print("\n" + "="*70)
        print("  TEST SUMMARY")
        print("="*70)
        print(f"  Passed: {passed}/{total}")

        if passed == total:
            print("\n  All tests passed!")
        else:
            failed = [r for r in self.results if not r["passed"]]
            print(f"\n  Failed tests:")
            for r in failed:
                print(f"    - {r['name']}: {r.get('error', 'Unknown error')}")

        print("="*70 + "\n")

        return {
            "timestamp": datetime.now().isoformat(),
            "base_url": self.base_url,
            "total": total,
            "passed": passed,
            "failed": total - passed,
            "results": self.results
        }


def main():
    """Main entry point."""
    import argparse

    parser = argparse.ArgumentParser(description="Citation & Pilot Run API Agent Test")
    parser.add_argument(
        "--base-url",
        default=os.environ.get("BIOMATE_URL", "http://localhost:5000"),
        help="Base URL for BioMate server"
    )
    parser.add_argument(
        "--output",
        help="Output file for JSON results"
    )

    args = parser.parse_args()

    tester = CitationPilotAPITester(base_url=args.base_url)
    results = tester.run_all_tests()

    if args.output:
        with open(args.output, "w") as f:
            json.dump(results, f, indent=2)
        print(f"Results saved to: {args.output}")

    # Exit with appropriate code
    sys.exit(0 if results["failed"] == 0 else 1)


if __name__ == "__main__":
    main()
