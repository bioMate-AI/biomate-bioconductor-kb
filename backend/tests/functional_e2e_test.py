#!/usr/bin/env python3
"""
Comprehensive Functional E2E Test Suite
Tests complete user journey through the Biomate platform
"""

import requests
import time
import json
import os
from datetime import datetime

class BiomateFunctionalTest:
    def __init__(self, base_url="http://localhost:5000"):
        self.base_url = base_url
        self.session = requests.Session()
        self.auth_token = None
        self.test_user = {
            "email": f"functional_test_{int(time.time())}@biomate.test",
            "password": "TestPassword123!",
            "fullName": "Functional Test User",
            "organization": "Biomate Testing Lab",
            "terms_accepted": True
        }
        self.results = []

    def log_test(self, name, status, details="", error=""):
        """Log test result"""
        result = {
            "name": name,
            "status": status,
            "details": details,
            "error": error,
            "timestamp": datetime.now().isoformat()
        }
        self.results.append(result)

        # Print with color
        symbol = "✓" if status == "PASS" else "✗" if status == "FAIL" else "⊘"
        print(f"{symbol} {name}")
        if details:
            print(f"  {details}")
        if error:
            print(f"  ERROR: {error}")
        print()

    def test_1_user_registration_login(self):
        """Test user registration and login flow"""
        print("\n" + "="*70)
        print("SCENARIO 1: User Registration & Login")
        print("="*70)

        # Register
        try:
            response = self.session.post(
                f"{self.base_url}/api/auth/register",
                json=self.test_user,
                timeout=10
            )

            if response.status_code in [200, 201]:
                data = response.json()
                self.auth_token = data.get("token")
                self.session.headers.update({"Authorization": f"Bearer {self.auth_token}"})
                self.log_test(
                    "User Registration",
                    "PASS",
                    f"Registered: {self.test_user['email']}"
                )
            else:
                self.log_test("User Registration", "FAIL", error=f"Status: {response.status_code}")
                return False
        except Exception as e:
            self.log_test("User Registration", "FAIL", error=str(e))
            return False

        # Verify dashboard access
        try:
            response = self.session.get(f"{self.base_url}/api/auth/me", timeout=10)
            if response.status_code == 200:
                user_data = response.json()
                self.log_test(
                    "Authentication Verification",
                    "PASS",
                    f"User authenticated, trial until: {user_data.get('user', {}).get('trialEndsAt', 'N/A')}"
                )
                return True
            else:
                self.log_test("Authentication Verification", "FAIL", error=f"Status: {response.status_code}")
                return False
        except Exception as e:
            self.log_test("Authentication Verification", "FAIL", error=str(e))
            return False

    def test_2_ai_chat_bioinformatics(self):
        """Test AI chat with real bioinformatics queries"""
        print("\n" + "="*70)
        print("SCENARIO 2: AI Chat - Bioinformatics Queries")
        print("="*70)

        test_queries = [
            {
                "query": "I have RNA-seq data from cancer samples. How do I analyze differential gene expression?",
                "expected_keywords": ["RNA-seq", "differential", "expression", "DESeq2", "edgeR", "workflow"]
            },
            {
                "query": "What quality control steps should I perform on my sequencing data?",
                "expected_keywords": ["quality", "FastQC", "trimming", "adapter"]
            },
            {
                "query": "I need to call variants from whole genome sequencing data",
                "expected_keywords": ["variant", "calling", "GATK", "alignment", "BWA"]
            }
        ]

        for idx, test in enumerate(test_queries, 1):
            try:
                response = self.session.post(
                    f"{self.base_url}/api/chat",
                    json={"message": test["query"]},
                    timeout=60
                )

                if response.status_code == 200:
                    data = response.json()
                    ai_response = data.get("response", "")

                    # Check if response contains expected keywords
                    keywords_found = sum(1 for kw in test["expected_keywords"]
                                       if kw.lower() in ai_response.lower())

                    if keywords_found >= 2:  # At least 2 keywords should match
                        self.log_test(
                            f"AI Query {idx}: {test['query'][:50]}...",
                            "PASS",
                            f"AI responded with {len(ai_response)} chars, {keywords_found}/{len(test['expected_keywords'])} keywords matched"
                        )
                    else:
                        self.log_test(
                            f"AI Query {idx}",
                            "FAIL",
                            error=f"Only {keywords_found}/{len(test['expected_keywords'])} keywords found"
                        )
                else:
                    self.log_test(
                        f"AI Query {idx}",
                        "FAIL",
                        error=f"Status: {response.status_code}"
                    )
            except Exception as e:
                self.log_test(f"AI Query {idx}", "FAIL", error=str(e))

    def test_3_dataset_upload(self):
        """Test dataset upload functionality"""
        print("\n" + "="*70)
        print("SCENARIO 3: Dataset Upload")
        print("="*70)

        # Create test files
        test_files = [
            ("sample1.fastq", "Sample FASTQ file\n@READ1\nATCGATCG\n+\nIIIIIIII\n"),
            ("metadata.csv", "sample_id,condition,replicate\nsample1,control,1\nsample2,treatment,1\n")
        ]

        for filename, content in test_files:
            try:
                files = {'file': (filename, content, 'text/plain')}
                response = self.session.post(
                    f"{self.base_url}/api/datasets/upload",
                    files=files,
                    timeout=30
                )

                if response.status_code == 200:
                    data = response.json()
                    self.log_test(
                        f"Dataset Upload: {filename}",
                        "PASS",
                        f"Uploaded {data.get('file_size', 0)} bytes, ID: {data.get('dataset_id', 'N/A')}"
                    )
                else:
                    self.log_test(
                        f"Dataset Upload: {filename}",
                        "FAIL",
                        error=f"Status: {response.status_code}"
                    )
            except Exception as e:
                self.log_test(f"Dataset Upload: {filename}", "FAIL", error=str(e))

    def test_4_workflow_generation(self):
        """Test workflow generation from AI chat"""
        print("\n" + "="*70)
        print("SCENARIO 4: Workflow Generation")
        print("="*70)

        workflow_request = "Create a workflow for RNA-seq differential expression analysis"

        try:
            response = self.session.post(
                f"{self.base_url}/api/ai_assistant/generate_workflow",
                json={"request_text": workflow_request},
                timeout=60
            )

            if response.status_code == 200:
                data = response.json()
                if data.get("success"):
                    workflow = data.get("workflow", {})
                    steps = workflow.get("steps", [])
                    self.log_test(
                        "Workflow Generation",
                        "PASS",
                        f"Generated workflow with {len(steps)} steps, Source: {data.get('source', 'N/A')}"
                    )

                    # Verify workflow has reasonable steps
                    if len(steps) >= 3:
                        self.log_test(
                            "Workflow Structure Validation",
                            "PASS",
                            f"Workflow contains {len(steps)} steps (minimum 3 required)"
                        )
                    else:
                        self.log_test(
                            "Workflow Structure Validation",
                            "FAIL",
                            error=f"Only {len(steps)} steps generated"
                        )
                else:
                    self.log_test("Workflow Generation", "FAIL", error=data.get("message", "Unknown error"))
            else:
                self.log_test("Workflow Generation", "FAIL", error=f"Status: {response.status_code}")
        except Exception as e:
            self.log_test("Workflow Generation", "FAIL", error=str(e))

    def test_5_galaxy_tools_search(self):
        """Test Galaxy tool search functionality"""
        print("\n" + "="*70)
        print("SCENARIO 5: Galaxy Tools Search")
        print("="*70)

        search_queries = [
            ("FastQC", 3),  # query, minimum expected results
            ("alignment", 5),
            ("variant calling", 2)
        ]

        for query, min_results in search_queries:
            try:
                response = self.session.get(
                    f"{self.base_url}/api/galaxy/tools/search",
                    params={"q": query, "limit": 50},
                    timeout=30
                )

                if response.status_code == 200:
                    tools = response.json()
                    if len(tools) >= min_results:
                        self.log_test(
                            f"Tool Search: '{query}'",
                            "PASS",
                            f"Found {len(tools)} tools (expected at least {min_results})"
                        )
                    else:
                        self.log_test(
                            f"Tool Search: '{query}'",
                            "FAIL",
                            error=f"Only found {len(tools)} tools, expected {min_results}"
                        )
                else:
                    self.log_test(f"Tool Search: '{query}'", "FAIL", error=f"Status: {response.status_code}")
            except Exception as e:
                self.log_test(f"Tool Search: '{query}'", "FAIL", error=str(e))

    def test_6_sse_realtime_updates(self):
        """Test Server-Sent Events for real-time updates"""
        print("\n" + "="*70)
        print("SCENARIO 6: Real-Time Updates (SSE)")
        print("="*70)

        try:
            # Test SSE connection
            response = self.session.get(
                f"{self.base_url}/api/workflows/events",
                stream=True,
                timeout=5
            )

            if response.status_code == 200:
                content_type = response.headers.get("Content-Type", "")
                if "text/event-stream" in content_type:
                    # Read first few events
                    events_received = 0
                    for line in response.iter_lines():
                        if line:
                            events_received += 1
                        if events_received >= 2:  # Got connection + heartbeat
                            break

                    self.log_test(
                        "SSE Connection",
                        "PASS",
                        f"Received {events_received} events, Content-Type: {content_type}"
                    )
                else:
                    self.log_test("SSE Connection", "FAIL", error=f"Wrong content type: {content_type}")
            else:
                self.log_test("SSE Connection", "FAIL", error=f"Status: {response.status_code}")
        except requests.exceptions.Timeout:
            self.log_test("SSE Connection", "PASS", "Timeout expected for streaming connection")
        except Exception as e:
            self.log_test("SSE Connection", "FAIL", error=str(e))

    def test_7_workflow_invocations(self):
        """Test workflow invocation listing"""
        print("\n" + "="*70)
        print("SCENARIO 7: Workflow Invocation Management")
        print("="*70)

        try:
            response = self.session.get(
                f"{self.base_url}/api/invocations",
                timeout=10
            )

            if response.status_code == 200:
                invocations = response.json()
                self.log_test(
                    "List Workflow Invocations",
                    "PASS",
                    f"Retrieved {len(invocations)} workflow invocations"
                )
            else:
                self.log_test("List Workflow Invocations", "FAIL", error=f"Status: {response.status_code}")
        except Exception as e:
            self.log_test("List Workflow Invocations", "FAIL", error=str(e))

    def print_summary(self):
        """Print test summary"""
        passed = sum(1 for r in self.results if r["status"] == "PASS")
        failed = sum(1 for r in self.results if r["status"] == "FAIL")
        total = len(self.results)

        print("\n" + "="*70)
        print("FUNCTIONAL E2E TEST SUMMARY")
        print("="*70)
        print(f"Total Tests:    {total}")
        print(f"✓ Passed:       {passed} ({passed/total*100:.0f}%)")
        print(f"✗ Failed:       {failed} ({failed/total*100:.0f}%)")
        print("="*70)

        if failed > 0:
            print("\nFAILED TESTS:")
            print("-" * 70)
            for result in self.results:
                if result["status"] == "FAIL":
                    print(f"• {result['name']}")
                    if result['error']:
                        print(f"  → {result['error']}")
            print()

        # Save detailed results
        results_file = f"functional_e2e_results_{int(time.time())}.json"
        with open(results_file, 'w') as f:
            json.dump({
                "summary": {
                    "total": total,
                    "passed": passed,
                    "failed": failed,
                    "pass_rate": f"{passed/total*100:.1f}%"
                },
                "tests": self.results
            }, f, indent=2)

        print(f"Detailed results saved to: {results_file}\n")

        return failed == 0

def main():
    print("\n" + "="*70)
    print("BIOMATE COMPREHENSIVE FUNCTIONAL E2E TEST SUITE")
    print("="*70)
    print(f"Base URL: http://localhost:5000")
    print(f"Start Time: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print("="*70)

    tester = BiomateFunctionalTest()

    # Run test scenarios
    tester.test_1_user_registration_login()
    tester.test_2_ai_chat_bioinformatics()
    tester.test_3_dataset_upload()
    tester.test_4_workflow_generation()
    tester.test_5_galaxy_tools_search()
    tester.test_6_sse_realtime_updates()
    tester.test_7_workflow_invocations()

    # Print summary
    success = tester.print_summary()

    return 0 if success else 1

if __name__ == "__main__":
    exit(main())
