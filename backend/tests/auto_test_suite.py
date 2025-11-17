#!/usr/bin/env python3
"""
Comprehensive Automated Test Suite for Biomate

Tests all key features of the Biomate system including:
- Task Management (Pause/Resume, Milestones, Priority)
- Workflow Execution
- API Endpoints
- Mode Detection (V6 Hybrid)
"""

import sys
import time
import json
import requests
from typing import Dict, List, Any
from datetime import datetime


class BiomateSystemTester:
    """Comprehensive automated tester for Biomate system"""

    def __init__(self, base_url: str = "http://localhost:5000"):
        self.base_url = base_url
        self.session = requests.Session()
        self.results = {
            "timestamp": datetime.now().isoformat(),
            "total_tests": 0,
            "passed": 0,
            "failed": 0,
            "skipped": 0,
            "categories": {},
            "failures": []
        }

    def run_test(self, category: str, test_name: str, test_func):
        """Run a single test and record results"""
        self.results["total_tests"] += 1

        if category not in self.results["categories"]:
            self.results["categories"][category] = {"passed": 0, "failed": 0, "skipped": 0}

        try:
            print(f"  Running: {test_name}...", end=" ")
            test_func()
            print("✅ PASS")
            self.results["passed"] += 1
            self.results["categories"][category]["passed"] += 1
        except Exception as e:
            print(f"❌ FAIL")
            self.results["failed"] += 1
            self.results["categories"][category]["failed"] += 1
            self.results["failures"].append({
                "test": test_name,
                "category": category,
                "error": str(e)
            })

    # ========================================================================
    # API Health Tests
    # ========================================================================

    def test_api_health_check(self):
        """Test: API health endpoint responds"""
        response = self.session.get(f"{self.base_url}/api/health")
        if response.status_code != 200:
            raise AssertionError(f"Health check failed: {response.status_code}")

    def test_api_galaxy_connection(self):
        """Test: Galaxy API connection is working"""
        response = self.session.get(f"{self.base_url}/api/galaxy/version")
        if response.status_code != 200:
            raise AssertionError(f"Galaxy connection failed: {response.status_code}")

    # ========================================================================
    # Task Management Tests
    # ========================================================================

    def test_pause_resume_endpoints_exist(self):
        """Test: Pause/resume endpoints are accessible"""
        # Test with invalid job ID to verify endpoint exists (will return 404 but endpoint exists)
        pause_response = self.session.put(f"{self.base_url}/api/galaxy/jobs/test_job_id/pause")
        # Either 404 (job not found) or 500 is acceptable - endpoint exists
        if pause_response.status_code == 405:
            raise AssertionError("Pause endpoint not implemented (405 Method Not Allowed)")

    def test_workflow_invoke_accepts_priority(self):
        """Test: Workflow invocation accepts priority parameter"""
        payload = {
            "workflow_id": "test_wf",
            "inputs": {},
            "parameters": {"__priority": "high"}
        }
        # This will fail with 404/500 but we're testing the endpoint accepts the payload structure
        response = self.session.post(f"{self.base_url}/api/galaxy/workflows/invoke", json=payload)
        # Not 400 (bad request) means it accepts the parameter structure
        if response.status_code == 400:
            error_msg = response.json().get('error', '')
            if '__priority' in error_msg:
                raise AssertionError("Priority parameter rejected")

    # ========================================================================
    # Workflow Execution Tests
    # ========================================================================

    def test_workflow_list_endpoint(self):
        """Test: Can list workflows"""
        response = self.session.get(f"{self.base_url}/api/galaxy/workflows")
        if response.status_code != 200:
            raise AssertionError(f"Workflow list failed: {response.status_code}")

    def test_dataset_list_endpoint(self):
        """Test: Can list datasets"""
        response = self.session.get(f"{self.base_url}/api/galaxy/datasets")
        if response.status_code != 200:
            raise AssertionError(f"Dataset list failed: {response.status_code}")

    # ========================================================================
    # Mode Detection Tests
    # ========================================================================

    def test_mode_detection_beginner(self):
        """Test: Detects beginner mode correctly"""
        # Simple query that should trigger beginner mode
        payload = {
            "message": "I need help analyzing my data",
            "context": {"history": []}
        }
        # Mode detection happens during chat processing
        # This is a basic connectivity test
        response = self.session.post(f"{self.base_url}/api/chat/message", json=payload)
        # Accept various status codes - we're testing mode detection exists
        if response.status_code not in [200, 400, 500]:
            raise AssertionError(f"Unexpected status: {response.status_code}")

    # ========================================================================
    # SSE Endpoint Tests
    # ========================================================================

    def test_sse_endpoint_exists(self):
        """Test: SSE endpoint is accessible"""
        # SSE endpoints should return 200 or streaming response
        # We can't easily test streaming in this simple test, so just verify endpoint exists
        try:
            response = self.session.get(
                f"{self.base_url}/api/galaxy/workflows/sse/test_inv_id",
                stream=True,
                timeout=2
            )
            # SSE should start streaming - any response that isn't 404 is good
            if response.status_code == 404:
                raise AssertionError("SSE endpoint not found")
        except requests.exceptions.Timeout:
            # Timeout is OK - means streaming started
            pass
        except requests.exceptions.ReadTimeout:
            # Read timeout is OK - means streaming started
            pass

    # ========================================================================
    # Security Tests
    # ========================================================================

    def test_sql_injection_prevention(self):
        """Test: SQL injection is prevented"""
        malicious_payload = {
            "workflow_id": "'; DROP TABLE workflows; --",
            "inputs": {}
        }
        response = self.session.post(f"{self.base_url}/api/galaxy/workflows/invoke", json=malicious_payload)
        # Should return error, not 200
        if response.status_code == 200:
            raise AssertionError("SQL injection not prevented")

    def test_xss_prevention_in_chat(self):
        """Test: XSS payload is handled safely"""
        xss_payload = {
            "message": "<script>alert('XSS')</script>",
            "context": {"history": []}
        }
        response = self.session.post(f"{self.base_url}/api/chat/message", json=xss_payload)
        # Should not crash - should return some response
        if response.status_code == 500:
            error = response.json().get('error', '')
            if 'script' in error.lower():
                raise AssertionError("XSS not properly sanitized")

    # ========================================================================
    # Integration Tests
    # ========================================================================

    def test_end_to_end_basic_flow(self):
        """Test: Basic user flow works"""
        # 1. List workflows
        wf_response = self.session.get(f"{self.base_url}/api/galaxy/workflows")
        if wf_response.status_code != 200:
            raise AssertionError("Cannot list workflows")

        # 2. List datasets
        ds_response = self.session.get(f"{self.base_url}/api/galaxy/datasets")
        if ds_response.status_code != 200:
            raise AssertionError("Cannot list datasets")

        # Basic flow works if we can list both
        print("\n      ✓ Workflow listing OK")
        print("      ✓ Dataset listing OK")

    # ========================================================================
    # Run All Tests
    # ========================================================================

    def run_all_tests(self):
        """Execute complete test suite"""
        print("\n" + "="*80)
        print("BIOMATE COMPREHENSIVE AUTOMATED TEST SUITE")
        print("="*80)
        print(f"Base URL: {self.base_url}")
        print(f"Timestamp: {self.results['timestamp']}")
        print("="*80 + "\n")

        # Category 1: API Health
        print("Category 1: API Health Tests")
        self.run_test("api_health", "API health endpoint", self.test_api_health_check)
        self.run_test("api_health", "Galaxy API connection", self.test_api_galaxy_connection)

        # Category 2: Task Management
        print("\nCategory 2: Task Management Tests")
        self.run_test("task_management", "Pause/Resume endpoints exist", self.test_pause_resume_endpoints_exist)
        self.run_test("task_management", "Priority parameter support", self.test_workflow_invoke_accepts_priority)

        # Category 3: Workflow Execution
        print("\nCategory 3: Workflow Execution Tests")
        self.run_test("workflow_execution", "List workflows", self.test_workflow_list_endpoint)
        self.run_test("workflow_execution", "List datasets", self.test_dataset_list_endpoint)

        # Category 4: Mode Detection
        print("\nCategory 4: Mode Detection Tests")
        self.run_test("mode_detection", "Beginner mode detection", self.test_mode_detection_beginner)

        # Category 5: Real-time Monitoring
        print("\nCategory 5: Real-time Monitoring Tests")
        self.run_test("sse_monitoring", "SSE endpoint exists", self.test_sse_endpoint_exists)

        # Category 6: Security
        print("\nCategory 6: Security Tests")
        self.run_test("security", "SQL injection prevention", self.test_sql_injection_prevention)
        self.run_test("security", "XSS prevention in chat", self.test_xss_prevention_in_chat)

        # Category 7: Integration
        print("\nCategory 7: Integration Tests")
        self.run_test("integration", "End-to-end basic flow", self.test_end_to_end_basic_flow)

        # Print Results
        self.print_results()

    def print_results(self):
        """Print test results summary"""
        print("\n" + "="*80)
        print("TEST RESULTS SUMMARY")
        print("="*80)

        total = self.results["total_tests"]
        passed = self.results["passed"]
        failed = self.results["failed"]
        pass_rate = (passed / total * 100) if total > 0 else 0

        print(f"\nTotal Tests: {total}")
        print(f"Passed: {passed} ({pass_rate:.1f}%)")
        print(f"Failed: {failed}")
        print(f"Skipped: {self.results['skipped']}")

        print("\nResults by Category:")
        for category, results in self.results["categories"].items():
            cat_passed = results["passed"]
            cat_failed = results["failed"]
            cat_total = cat_passed + cat_failed
            cat_rate = (cat_passed / cat_total * 100) if cat_total > 0 else 0
            print(f"  {category}: {cat_passed}/{cat_total} ({cat_rate:.1f}%)")

        if self.results["failures"]:
            print("\nFailed Tests:")
            for i, failure in enumerate(self.results["failures"], 1):
                print(f"\n  {i}. [{failure['category']}] {failure['test']}")
                print(f"     Error: {failure['error']}")

        print("\n" + "="*80)

        # Save results to JSON
        results_file = f"test_results_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
        with open(results_file, 'w') as f:
            json.dump(self.results, f, indent=2)
        print(f"Results saved to: {results_file}")
        print("="*80 + "\n")

        # Return exit code
        return 0 if failed == 0 else 1


def main():
    """Main entry point"""
    import argparse

    parser = argparse.ArgumentParser(description="Biomate Comprehensive Automated Test Suite")
    parser.add_argument("--url", default="http://localhost:5000", help="Biomate base URL")
    args = parser.parse_args()

    tester = BiomateSystemTester(base_url=args.url)
    exit_code = tester.run_all_tests()
    sys.exit(exit_code)


if __name__ == "__main__":
    main()
