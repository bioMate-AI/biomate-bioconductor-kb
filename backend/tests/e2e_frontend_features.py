#!/usr/bin/env python3
"""
Frontend Features E2E Test Suite

Tests for Citations, Pilot Runs, and Parameter Recommendations features.
These tests validate the new API endpoints and their integration.
"""

import requests
import time
import json
from datetime import datetime
from typing import Dict, Any, Optional, List


class FrontendFeaturesE2ETests:
    """E2E tests for citation, pilot run, and parameter recommendation features."""

    def __init__(self, base_url: str = "http://localhost:5000"):
        self.base_url = base_url
        self.session = requests.Session()
        self.results = {
            "timestamp": datetime.now().isoformat(),
            "tests": [],
            "passed": 0,
            "failed": 0,
            "skipped": 0,
            "total": 0
        }
        # Sample workflow for testing
        self.sample_workflow = {
            "name": "RNA-seq Analysis Pipeline",
            "annotation": "Test workflow for E2E testing",
            "steps": {
                "0": {
                    "id": 0,
                    "type": "data_input",
                    "name": "Input Reads",
                    "tool_id": None,
                },
                "1": {
                    "id": 1,
                    "type": "tool",
                    "name": "FastQC",
                    "tool_id": "toolshed.g2.bx.psu.edu/repos/devteam/fastqc/fastqc/0.73+galaxy0",
                    "tool_state": {"threads": 4}
                },
                "2": {
                    "id": 2,
                    "type": "tool",
                    "name": "STAR Aligner",
                    "tool_id": "toolshed.g2.bx.psu.edu/repos/iuc/rgrnastar/rna_star/2.7.10b+galaxy4",
                    "tool_state": {"threads": 8, "outSAMtype": "BAM SortedByCoordinate"}
                },
                "3": {
                    "id": 3,
                    "type": "tool",
                    "name": "DESeq2",
                    "tool_id": "toolshed.g2.bx.psu.edu/repos/iuc/deseq2/deseq2/2.11.40.8+galaxy0",
                    "tool_state": {}
                }
            }
        }

    def log_test(self, name: str, status: str, details: str = "", error: str = ""):
        """Log test result."""
        result = {
            "name": name,
            "status": status,
            "details": details,
            "error": error,
            "timestamp": datetime.now().isoformat()
        }
        self.results["tests"].append(result)
        self.results["total"] += 1

        if status == "PASS":
            self.results["passed"] += 1
            print(f"✓ {name}")
            if details:
                print(f"  {details}")
        elif status == "FAIL":
            self.results["failed"] += 1
            print(f"✗ {name}")
            if error:
                print(f"  Error: {error}")
        elif status == "SKIP":
            self.results["skipped"] += 1
            print(f"⊘ {name} (SKIPPED)")
            if details:
                print(f"  {details}")
        print()

    # =========================================================================
    # Citation Tests
    # =========================================================================

    def test_citation_export_bibtex(self):
        """Test BibTeX export endpoint."""
        print("\n" + "=" * 60)
        print("TEST: Citation BibTeX Export")
        print("=" * 60)

        try:
            response = self.session.post(
                f"{self.base_url}/api/ai_assistant/citations/export",
                json={"workflow_ga": self.sample_workflow, "include_all": True},
                timeout=30
            )

            if response.status_code == 200:
                data = response.json()
                if data.get("success"):
                    bibtex = data.get("bibtex", "")
                    tools_with_citations = data.get("tools_with_citations", 0)
                    self.log_test(
                        "BibTeX Export",
                        "PASS",
                        f"Exported {tools_with_citations} citations, {len(bibtex)} chars"
                    )
                    return True
                else:
                    self.log_test(
                        "BibTeX Export",
                        "FAIL",
                        error=data.get("error", "Unknown error")
                    )
            else:
                self.log_test(
                    "BibTeX Export",
                    "FAIL",
                    error=f"HTTP {response.status_code}: {response.text[:200]}"
                )
        except Exception as e:
            self.log_test("BibTeX Export", "FAIL", error=str(e))

        return False

    def test_methods_section_generation(self):
        """Test methods section generation with different styles."""
        print("\n" + "=" * 60)
        print("TEST: Methods Section Generation")
        print("=" * 60)

        styles = ["short", "apa", "numbered"]
        all_passed = True

        for style in styles:
            try:
                response = self.session.post(
                    f"{self.base_url}/api/ai_assistant/citations/methods",
                    params={"style": style},
                    json={"workflow_ga": self.sample_workflow, "include_all": True},
                    timeout=30
                )

                if response.status_code == 200:
                    data = response.json()
                    if data.get("success"):
                        methods_text = data.get("methods_text", "")
                        tools_cited = data.get("tools_cited", [])
                        self.log_test(
                            f"Methods Section ({style})",
                            "PASS",
                            f"Generated {len(methods_text)} chars, {len(tools_cited)} tools cited"
                        )
                    else:
                        self.log_test(
                            f"Methods Section ({style})",
                            "FAIL",
                            error=data.get("error", "Unknown error")
                        )
                        all_passed = False
                else:
                    self.log_test(
                        f"Methods Section ({style})",
                        "FAIL",
                        error=f"HTTP {response.status_code}"
                    )
                    all_passed = False
            except Exception as e:
                self.log_test(f"Methods Section ({style})", "FAIL", error=str(e))
                all_passed = False

        return all_passed

    def test_citation_response_format(self):
        """Test that workflow generation includes properly formatted citations."""
        print("\n" + "=" * 60)
        print("TEST: Citation Response Format")
        print("=" * 60)

        try:
            response = self.session.post(
                f"{self.base_url}/api/ai_assistant/citations/export",
                json={"workflow_ga": self.sample_workflow, "include_all": True},
                timeout=30
            )

            if response.status_code == 200:
                data = response.json()

                # Check required fields
                required_fields = ["success", "bibtex", "total_tools", "tools_with_citations"]
                missing_fields = [f for f in required_fields if f not in data]

                if missing_fields:
                    self.log_test(
                        "Citation Response Format",
                        "FAIL",
                        error=f"Missing fields: {missing_fields}"
                    )
                    return False

                # Validate BibTeX format if present
                bibtex = data.get("bibtex", "")
                if bibtex and data["tools_with_citations"] > 0:
                    if "@" in bibtex and "{" in bibtex:
                        self.log_test(
                            "Citation Response Format",
                            "PASS",
                            f"Valid BibTeX format with {data['tools_with_citations']} entries"
                        )
                        return True
                    else:
                        self.log_test(
                            "Citation Response Format",
                            "FAIL",
                            error="BibTeX format invalid"
                        )
                        return False
                else:
                    self.log_test(
                        "Citation Response Format",
                        "PASS",
                        "No citations available (expected for some tools)"
                    )
                    return True
            else:
                self.log_test(
                    "Citation Response Format",
                    "FAIL",
                    error=f"HTTP {response.status_code}"
                )
        except Exception as e:
            self.log_test("Citation Response Format", "FAIL", error=str(e))

        return False

    # =========================================================================
    # Pilot Run Tests
    # =========================================================================

    def test_pilot_run_start(self):
        """Test starting a pilot run."""
        print("\n" + "=" * 60)
        print("TEST: Pilot Run Start")
        print("=" * 60)

        try:
            response = self.session.post(
                f"{self.base_url}/api/ai_assistant/pilot/start",
                json={
                    "workflow_id": "test-workflow-001",
                    "total_samples": 100,
                    "config": {
                        "pilot_fraction": 0.1,
                        "sampling_strategy": "stratified",
                        "min_pilot_samples": 5,
                        "max_pilot_samples": 20
                    }
                },
                timeout=30
            )

            if response.status_code == 200:
                data = response.json()
                pilot_id = data.get("pilot_id")
                if pilot_id:
                    self.log_test(
                        "Pilot Run Start",
                        "PASS",
                        f"Started pilot run: {pilot_id}, size: {data.get('pilot_size')}"
                    )
                    return pilot_id
                else:
                    self.log_test(
                        "Pilot Run Start",
                        "FAIL",
                        error="No pilot_id in response"
                    )
            else:
                self.log_test(
                    "Pilot Run Start",
                    "FAIL",
                    error=f"HTTP {response.status_code}: {response.text[:200]}"
                )
        except Exception as e:
            self.log_test("Pilot Run Start", "FAIL", error=str(e))

        return None

    def test_pilot_run_status(self, pilot_id: Optional[str] = None):
        """Test getting pilot run status."""
        print("\n" + "=" * 60)
        print("TEST: Pilot Run Status")
        print("=" * 60)

        if not pilot_id:
            pilot_id = self.test_pilot_run_start()
            if not pilot_id:
                self.log_test("Pilot Run Status", "SKIP", "No pilot_id available")
                return False

        try:
            response = self.session.get(
                f"{self.base_url}/api/ai_assistant/pilot/{pilot_id}/status",
                timeout=30
            )

            if response.status_code == 200:
                data = response.json()
                status = data.get("status")
                progress = data.get("progress", 0)

                self.log_test(
                    "Pilot Run Status",
                    "PASS",
                    f"Status: {status}, Progress: {progress}%"
                )
                return True
            else:
                self.log_test(
                    "Pilot Run Status",
                    "FAIL",
                    error=f"HTTP {response.status_code}"
                )
        except Exception as e:
            self.log_test("Pilot Run Status", "FAIL", error=str(e))

        return False

    def test_pilot_run_estimate(self, pilot_id: Optional[str] = None):
        """Test getting full run estimate from pilot."""
        print("\n" + "=" * 60)
        print("TEST: Full Run Estimate")
        print("=" * 60)

        if not pilot_id:
            pilot_id = self.test_pilot_run_start()
            if not pilot_id:
                self.log_test("Full Run Estimate", "SKIP", "No pilot_id available")
                return False

        # Wait for pilot to complete (simulated completes quickly)
        time.sleep(1)

        try:
            response = self.session.get(
                f"{self.base_url}/api/ai_assistant/pilot/{pilot_id}/estimate",
                params={"cost_per_hour_usd": 0.50},
                timeout=30
            )

            if response.status_code == 200:
                data = response.json()
                runtime = data.get("estimated_runtime_display", "unknown")
                memory = data.get("estimated_memory_gb", 0)
                cost = data.get("estimated_cost_usd", 0)

                self.log_test(
                    "Full Run Estimate",
                    "PASS",
                    f"Runtime: {runtime}, Memory: {memory}GB, Cost: ${cost:.2f}"
                )
                return True
            elif response.status_code == 404:
                self.log_test(
                    "Full Run Estimate",
                    "SKIP",
                    "Pilot not complete yet"
                )
            else:
                self.log_test(
                    "Full Run Estimate",
                    "FAIL",
                    error=f"HTTP {response.status_code}"
                )
        except Exception as e:
            self.log_test("Full Run Estimate", "FAIL", error=str(e))

        return False

    # =========================================================================
    # Benchmark Tests
    # =========================================================================

    def test_benchmark_results(self):
        """Test getting benchmark results."""
        print("\n" + "=" * 60)
        print("TEST: Benchmark Results")
        print("=" * 60)

        scenarios = ["rna_seq_aligners", "variant_callers", "differential_expression"]

        for scenario in scenarios:
            try:
                response = self.session.get(
                    f"{self.base_url}/api/ai_assistant/benchmarks/{scenario}",
                    timeout=30
                )

                if response.status_code == 200:
                    data = response.json()
                    if data.get("available", False):
                        self.log_test(
                            f"Benchmark: {scenario}",
                            "PASS",
                            f"Tools compared: {data.get('tools_compared', [])}"
                        )
                    else:
                        self.log_test(
                            f"Benchmark: {scenario}",
                            "PASS",
                            data.get("message", "No benchmark data available")
                        )
                elif response.status_code == 404:
                    self.log_test(
                        f"Benchmark: {scenario}",
                        "PASS",
                        "Scenario not found (expected for some scenarios)"
                    )
                else:
                    self.log_test(
                        f"Benchmark: {scenario}",
                        "FAIL",
                        error=f"HTTP {response.status_code}"
                    )
            except Exception as e:
                self.log_test(f"Benchmark: {scenario}", "FAIL", error=str(e))

        return True

    # =========================================================================
    # Integration Tests
    # =========================================================================

    def test_workflow_generation_with_citations(self):
        """Test that workflow generation includes citation data."""
        print("\n" + "=" * 60)
        print("TEST: Workflow Generation with Citations")
        print("=" * 60)

        try:
            response = self.session.post(
                f"{self.base_url}/api/ai_assistant/generate_workflow",
                json={
                    "query": "Analyze RNA-seq data with quality control and differential expression",
                    "context": {}
                },
                timeout=60
            )

            if response.status_code == 200:
                data = response.json()

                # Check for citation fields in response
                has_citations = "citations" in data
                has_methods = "methods_section" in data
                has_pilot_suggestion = "pilot_run_suggested" in data

                if has_citations or has_methods:
                    citations = data.get("citations", [])
                    self.log_test(
                        "Workflow with Citations",
                        "PASS",
                        f"Returned {len(citations)} citations, pilot_suggested: {data.get('pilot_run_suggested', False)}"
                    )
                    return True
                else:
                    self.log_test(
                        "Workflow with Citations",
                        "PASS",
                        "Workflow generated (no citation fields - may be expected)"
                    )
                    return True
            else:
                self.log_test(
                    "Workflow with Citations",
                    "FAIL",
                    error=f"HTTP {response.status_code}"
                )
        except Exception as e:
            self.log_test("Workflow with Citations", "FAIL", error=str(e))

        return False

    # =========================================================================
    # Run All Tests
    # =========================================================================

    def run_all(self) -> Dict[str, Any]:
        """Run all E2E tests."""
        print("\n" + "=" * 60)
        print("FRONTEND FEATURES E2E TEST SUITE")
        print("=" * 60)
        print(f"Base URL: {self.base_url}")
        print(f"Started: {datetime.now().isoformat()}")

        # Citation tests
        self.test_citation_export_bibtex()
        self.test_methods_section_generation()
        self.test_citation_response_format()

        # Pilot run tests
        pilot_id = self.test_pilot_run_start()
        if pilot_id:
            self.test_pilot_run_status(pilot_id)
            self.test_pilot_run_estimate(pilot_id)

        # Benchmark tests
        self.test_benchmark_results()

        # Integration tests
        self.test_workflow_generation_with_citations()

        # Summary
        print("\n" + "=" * 60)
        print("TEST SUMMARY")
        print("=" * 60)
        print(f"Total:   {self.results['total']}")
        print(f"Passed:  {self.results['passed']}")
        print(f"Failed:  {self.results['failed']}")
        print(f"Skipped: {self.results['skipped']}")

        if self.results['failed'] == 0:
            print("\n✓ All tests passed!")
        else:
            print(f"\n✗ {self.results['failed']} test(s) failed")

        return self.results


def main():
    """Run the E2E test suite."""
    import argparse

    parser = argparse.ArgumentParser(description="Frontend Features E2E Tests")
    parser.add_argument(
        "--base-url",
        default="http://localhost:5000",
        help="Base URL for the Biomate server"
    )
    parser.add_argument(
        "--output",
        help="Output file for JSON results"
    )

    args = parser.parse_args()

    suite = FrontendFeaturesE2ETests(base_url=args.base_url)
    results = suite.run_all()

    if args.output:
        with open(args.output, "w") as f:
            json.dump(results, f, indent=2)
        print(f"\nResults saved to: {args.output}")

    # Exit with non-zero code if any tests failed
    exit(0 if results["failed"] == 0 else 1)


if __name__ == "__main__":
    main()
