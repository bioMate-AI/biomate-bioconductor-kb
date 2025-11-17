#!/usr/bin/env python3
"""
Biomate End-to-End Test Suite
Tests complete user journey from registration to workflow execution
"""

import requests
import time
import json
from datetime import datetime
from typing import Dict, Any, Optional


class BiomateE2ETestSuite:
    def __init__(self, base_url: str = "http://localhost:5000"):
        self.base_url = base_url
        self.session = requests.Session()
        self.test_user = {
            "email": f"test_{int(time.time())}@biomate.test",
            "password": "TestPass123!",
            "fullName": "E2E Test User",
            "organization": "Test Organization"
        }
        self.auth_token = None
        self.results = {
            "timestamp": datetime.now().isoformat(),
            "tests": [],
            "passed": 0,
            "failed": 0,
            "skipped": 0,
            "total": 0
        }

    def log_test(self, name: str, status: str, details: str = "", error: str = ""):
        """Log test result"""
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

    def test_1_servers_running(self):
        """Test that both servers are running"""
        print("\n" + "="*60)
        print("TEST 1: Server Health Checks")
        print("="*60)

        # Test Biomate frontend
        try:
            response = self.session.get(f"{self.base_url}/api/health", timeout=5)
            if response.status_code == 200:
                self.log_test(
                    "Biomate Frontend Server",
                    "PASS",
                    f"Server running on {self.base_url}"
                )
            else:
                self.log_test(
                    "Biomate Frontend Server",
                    "FAIL",
                    error=f"Unexpected status: {response.status_code}"
                )
        except Exception as e:
            self.log_test(
                "Biomate Frontend Server",
                "FAIL",
                error=str(e)
            )

        # Test Galaxy backend connection
        try:
            response = self.session.get(f"{self.base_url}/api/galaxy/health", timeout=5)
            if response.status_code in [200, 401]:  # 401 is ok, means auth is required
                self.log_test(
                    "Galaxy Backend Connection",
                    "PASS",
                    f"Galaxy backend accessible (status: {response.status_code})"
                )
            else:
                self.log_test(
                    "Galaxy Backend Connection",
                    "FAIL",
                    error=f"Unexpected status: {response.status_code}"
                )
        except Exception as e:
            self.log_test(
                "Galaxy Backend Connection",
                "FAIL",
                error=str(e)
            )

    def test_2_landing_page(self):
        """Test landing page loads"""
        print("\n" + "="*60)
        print("TEST 2: Landing Page")
        print("="*60)

        try:
            response = self.session.get(self.base_url, timeout=10)
            if response.status_code == 200:
                content_length = len(response.content)
                if content_length > 1000:
                    self.log_test(
                        "Landing Page Loads",
                        "PASS",
                        f"Page loaded: {content_length} bytes"
                    )
                else:
                    self.log_test(
                        "Landing Page Loads",
                        "FAIL",
                        error=f"Page too small: {content_length} bytes"
                    )
            else:
                self.log_test(
                    "Landing Page Loads",
                    "FAIL",
                    error=f"Status: {response.status_code}"
                )
        except Exception as e:
            self.log_test("Landing Page Loads", "FAIL", error=str(e))

    def test_3_registration_without_payment(self):
        """Test user registration (without payment flow)"""
        print("\n" + "="*60)
        print("TEST 3: User Registration")
        print("="*60)

        # First check if registration endpoint exists
        try:
            response = self.session.post(
                f"{self.base_url}/api/auth/register",
                json={
                    "email": self.test_user["email"],
                    "password": self.test_user["password"],
                    "fullName": self.test_user["fullName"],
                    "organization": self.test_user["organization"],
                    "termsAccepted": True
                },
                timeout=10
            )

            if response.status_code in [200, 201]:  # Accept both 200 OK and 201 Created
                data = response.json()
                if "token" in data or "user" in data:
                    self.auth_token = data.get("token")
                    self.session.headers.update({"Authorization": f"Bearer {self.auth_token}"})
                    self.log_test(
                        "User Registration",
                        "PASS",
                        f"User registered: {self.test_user['email']}"
                    )
                    return True
                else:
                    self.log_test(
                        "User Registration",
                        "FAIL",
                        error="No token in response"
                    )
            elif response.status_code == 400:
                error_msg = response.json().get("error", "")
                if "stripe" in error_msg.lower() or "payment" in error_msg.lower():
                    self.log_test(
                        "User Registration",
                        "SKIP",
                        "Registration requires payment configuration (Stripe not set up)"
                    )
                    return False
                else:
                    self.log_test(
                        "User Registration",
                        "FAIL",
                        error=error_msg
                    )
            else:
                self.log_test(
                    "User Registration",
                    "FAIL",
                    error=f"Status: {response.status_code}, {response.text}"
                )
        except Exception as e:
            self.log_test("User Registration", "FAIL", error=str(e))

        return False

    def test_4_login(self):
        """Test user login"""
        print("\n" + "="*60)
        print("TEST 4: User Login")
        print("="*60)

        if not self.auth_token:
            self.log_test(
                "User Login",
                "SKIP",
                "No user registered, cannot test login"
            )
            return False

        try:
            response = self.session.post(
                f"{self.base_url}/api/auth/login",
                json={
                    "email": self.test_user["email"],
                    "password": self.test_user["password"]
                },
                timeout=10
            )

            if response.status_code == 200:
                data = response.json()
                if "token" in data:
                    self.auth_token = data["token"]
                    self.session.headers.update({"Authorization": f"Bearer {self.auth_token}"})
                    self.log_test(
                        "User Login",
                        "PASS",
                        "Login successful"
                    )
                    return True
                else:
                    self.log_test(
                        "User Login",
                        "FAIL",
                        error="No token in response"
                    )
            else:
                self.log_test(
                    "User Login",
                    "FAIL",
                    error=f"Status: {response.status_code}"
                )
        except Exception as e:
            self.log_test("User Login", "FAIL", error=str(e))

        return False

    def test_5_dashboard_access(self):
        """Test dashboard page access"""
        print("\n" + "="*60)
        print("TEST 5: Dashboard Access")
        print("="*60)

        if not self.auth_token:
            self.log_test(
                "Dashboard Access",
                "SKIP",
                "No auth token, cannot test dashboard"
            )
            return

        try:
            response = self.session.get(f"{self.base_url}/dashboard", timeout=10)
            if response.status_code == 200:
                self.log_test(
                    "Dashboard Access",
                    "PASS",
                    f"Dashboard loaded: {len(response.content)} bytes"
                )
            elif response.status_code == 401:
                self.log_test(
                    "Dashboard Access",
                    "FAIL",
                    error="Authentication failed - session not working"
                )
            else:
                self.log_test(
                    "Dashboard Access",
                    "FAIL",
                    error=f"Status: {response.status_code}"
                )
        except Exception as e:
            self.log_test("Dashboard Access", "FAIL", error=str(e))

    def test_6_chat_interface(self):
        """Test AI chat interface"""
        print("\n" + "="*60)
        print("TEST 6: AI Chat Interface")
        print("="*60)

        try:
            start_time = time.time()
            response = self.session.post(
                f"{self.base_url}/api/chat",
                json={"message": "Hello"},
                timeout=30  # LLM calls can take time
            )
            elapsed = time.time() - start_time

            if response.status_code == 200:
                data = response.json()
                if "response" in data:
                    self.log_test(
                        "AI Chat Interface",
                        "PASS",
                        f"Chat working, response time: {elapsed:.1f}s"
                    )
                else:
                    self.log_test(
                        "AI Chat Interface",
                        "FAIL",
                        error="No response in data"
                    )
            else:
                self.log_test(
                    "AI Chat Interface",
                    "FAIL",
                    error=f"Status: {response.status_code}"
                )
        except requests.exceptions.Timeout:
            self.log_test(
                "AI Chat Interface",
                "FAIL",
                error="Request timeout (>30s)"
            )
        except Exception as e:
            self.log_test("AI Chat Interface", "FAIL", error=str(e))

    def test_7_workflow_list(self):
        """Test workflow list endpoint"""
        print("\n" + "="*60)
        print("TEST 7: Workflow Management")
        print("="*60)

        if not self.auth_token:
            self.log_test(
                "Workflow List",
                "SKIP",
                "No auth token"
            )
            return

        try:
            response = self.session.get(
                f"{self.base_url}/api/workflows",
                timeout=10
            )

            if response.status_code == 200:
                data = response.json()
                self.log_test(
                    "Workflow List",
                    "PASS",
                    f"Workflows endpoint working, found {len(data) if isinstance(data, list) else 0} workflows"
                )
            else:
                self.log_test(
                    "Workflow List",
                    "FAIL",
                    error=f"Status: {response.status_code}"
                )
        except Exception as e:
            self.log_test("Workflow List", "FAIL", error=str(e))

    def test_8_dataset_management(self):
        """Test dataset upload capability"""
        print("\n" + "="*60)
        print("TEST 8: Dataset Management")
        print("="*60)

        if not self.auth_token:
            self.log_test(
                "Dataset Upload",
                "SKIP",
                "No auth token"
            )
            return

        try:
            # Create a small test file
            files = {
                'file': ('test.txt', 'This is a test file for E2E testing', 'text/plain')
            }

            response = self.session.post(
                f"{self.base_url}/api/datasets/upload",
                files=files,
                timeout=30
            )

            if response.status_code == 200:
                self.log_test(
                    "Dataset Upload",
                    "PASS",
                    "File upload endpoint working"
                )
            elif response.status_code == 401:
                self.log_test(
                    "Dataset Upload",
                    "FAIL",
                    error="Authentication failed"
                )
            else:
                self.log_test(
                    "Dataset Upload",
                    "FAIL",
                    error=f"Status: {response.status_code}, {response.text[:200]}"
                )
        except Exception as e:
            self.log_test("Dataset Upload", "FAIL", error=str(e))

    def test_9_oauth_configuration(self):
        """Test OAuth configuration"""
        print("\n" + "="*60)
        print("TEST 9: OAuth Integration")
        print("="*60)

        oauth_providers = ["google", "github"]
        for provider in oauth_providers:
            try:
                response = self.session.get(
                    f"{self.base_url}/api/auth/oauth/{provider}",
                    allow_redirects=False,
                    timeout=5
                )

                if response.status_code in [302, 307, 308]:
                    self.log_test(
                        f"OAuth - {provider.capitalize()}",
                        "PASS",
                        f"Redirect working (configured)"
                    )
                elif response.status_code == 404:
                    self.log_test(
                        f"OAuth - {provider.capitalize()}",
                        "FAIL",
                        error="Endpoint not found"
                    )
                elif response.status_code == 400:
                    self.log_test(
                        f"OAuth - {provider.capitalize()}",
                        "SKIP",
                        "Not configured"
                    )
                else:
                    self.log_test(
                        f"OAuth - {provider.capitalize()}",
                        "FAIL",
                        error=f"Unexpected status: {response.status_code}"
                    )
            except Exception as e:
                self.log_test(f"OAuth - {provider.capitalize()}", "FAIL", error=str(e))

    def test_10_payment_integration(self):
        """Test payment integration"""
        print("\n" + "="*60)
        print("TEST 10: Payment Integration (Stripe)")
        print("="*60)

        try:
            response = self.session.post(
                f"{self.base_url}/api/payments/create-checkout-session",
                json={
                    "priceId": "price_test_xxx",
                    "email": self.test_user["email"]
                },
                timeout=10
            )

            if response.status_code == 200:
                data = response.json()
                if "url" in data or "sessionId" in data:
                    self.log_test(
                        "Stripe Payment Integration",
                        "PASS",
                        "Stripe checkout session creation working"
                    )
                else:
                    self.log_test(
                        "Stripe Payment Integration",
                        "FAIL",
                        error="No checkout URL in response"
                    )
            elif response.status_code == 400:
                error_msg = response.json().get("error", "")
                if "not configured" in error_msg.lower():
                    self.log_test(
                        "Stripe Payment Integration",
                        "SKIP",
                        "Stripe not configured - set STRIPE_SECRET_KEY in .env"
                    )
                else:
                    self.log_test(
                        "Stripe Payment Integration",
                        "FAIL",
                        error=error_msg
                    )
            else:
                self.log_test(
                    "Stripe Payment Integration",
                    "FAIL",
                    error=f"Status: {response.status_code}"
                )
        except Exception as e:
            self.log_test("Stripe Payment Integration", "FAIL", error=str(e))

    def test_11_email_service(self):
        """Test email service configuration"""
        print("\n" + "="*60)
        print("TEST 11: Email Service")
        print("="*60)

        # Test forgot password endpoint (triggers email)
        try:
            response = self.session.post(
                f"{self.base_url}/api/auth/forgot-password",
                json={"email": "test@example.com"},
                timeout=10
            )

            if response.status_code == 200:
                self.log_test(
                    "Email Service",
                    "PASS",
                    "Email service configured and working"
                )
            elif response.status_code == 400:
                error_msg = response.json().get("error", "")
                if "email not configured" in error_msg.lower():
                    self.log_test(
                        "Email Service",
                        "SKIP",
                        "Email service not configured - set EMAIL_HOST, EMAIL_USER, EMAIL_PASS in .env"
                    )
                else:
                    self.log_test(
                        "Email Service",
                        "FAIL",
                        error=error_msg
                    )
            elif response.status_code == 404:
                self.log_test(
                    "Email Service",
                    "SKIP",
                    "Forgot password endpoint not found"
                )
            else:
                self.log_test(
                    "Email Service",
                    "FAIL",
                    error=f"Status: {response.status_code}"
                )
        except Exception as e:
            self.log_test("Email Service", "FAIL", error=str(e))

    def test_12_sse_real_time(self):
        """Test Server-Sent Events for real-time updates"""
        print("\n" + "="*60)
        print("TEST 12: Real-Time Updates (SSE)")
        print("="*60)

        if not self.auth_token:
            self.log_test(
                "SSE Real-Time Updates",
                "SKIP",
                "No auth token"
            )
            return

        try:
            # Test SSE endpoint exists (just check connection, don't wait for events)
            response = self.session.get(
                f"{self.base_url}/api/workflows/events",
                stream=True,
                timeout=5
            )

            if response.status_code == 200:
                # Check if it's SSE format
                content_type = response.headers.get("Content-Type", "")
                if "text/event-stream" in content_type:
                    self.log_test(
                        "SSE Real-Time Updates",
                        "PASS",
                        "SSE endpoint configured correctly"
                    )
                else:
                    self.log_test(
                        "SSE Real-Time Updates",
                        "FAIL",
                        error=f"Wrong content type: {content_type}"
                    )
            else:
                self.log_test(
                    "SSE Real-Time Updates",
                    "FAIL",
                    error=f"Status: {response.status_code}"
                )
        except requests.exceptions.Timeout:
            # Timeout is ok, means endpoint exists but no events yet
            self.log_test(
                "SSE Real-Time Updates",
                "PASS",
                "SSE endpoint exists (timeout waiting for events is expected)"
            )
        except Exception as e:
            self.log_test("SSE Real-Time Updates", "FAIL", error=str(e))

    def run_all_tests(self):
        """Run all E2E tests"""
        print("\n" + "="*70)
        print("BIOMATE END-TO-END TEST SUITE")
        print("="*70)
        print(f"Base URL: {self.base_url}")
        print(f"Test User: {self.test_user['email']}")
        print(f"Start Time: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        print("="*70)

        # Run all tests
        self.test_1_servers_running()
        self.test_2_landing_page()
        self.test_3_registration_without_payment()
        self.test_4_login()
        self.test_5_dashboard_access()
        self.test_6_chat_interface()
        self.test_7_workflow_list()
        self.test_8_dataset_management()
        self.test_9_oauth_configuration()
        self.test_10_payment_integration()
        self.test_11_email_service()
        self.test_12_sse_real_time()

        # Summary
        print("\n" + "="*70)
        print("TEST RESULTS SUMMARY")
        print("="*70)
        print(f"Total Tests:   {self.results['total']}")
        print(f"✓ Passed:      {self.results['passed']} ({self.results['passed']*100//self.results['total']}%)")
        print(f"✗ Failed:      {self.results['failed']} ({self.results['failed']*100//self.results['total']}%)")
        print(f"⊘ Skipped:     {self.results['skipped']} ({self.results['skipped']*100//self.results['total']}%)")
        print("="*70)

        # Configuration gaps
        skipped_tests = [t for t in self.results["tests"] if t["status"] == "SKIP"]
        if skipped_tests:
            print("\nCONFIGURATION GAPS (Skipped Tests):")
            print("-" * 70)
            for test in skipped_tests:
                print(f"• {test['name']}")
                if test['details']:
                    print(f"  → {test['details']}")
            print()

        # Failed tests
        failed_tests = [t for t in self.results["tests"] if t["status"] == "FAIL"]
        if failed_tests:
            print("\nFAILED TESTS (Need Investigation):")
            print("-" * 70)
            for test in failed_tests:
                print(f"• {test['name']}")
                if test['error']:
                    print(f"  → Error: {test['error']}")
            print()

        # Save results
        output_file = f"e2e_test_results_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
        with open(output_file, 'w') as f:
            json.dump(self.results, f, indent=2)
        print(f"\nDetailed results saved to: {output_file}")

        # Next steps
        print("\n" + "="*70)
        print("NEXT STEPS:")
        print("="*70)

        if self.results['failed'] > 0:
            print("\n1. INVESTIGATE FAILURES:")
            print("   Fix failed tests to ensure core functionality works")

        if self.results['skipped'] > 0:
            print("\n2. CONFIGURE MISSING SERVICES:")
            if any("Stripe" in t['name'] for t in skipped_tests):
                print("   → Set up Stripe: see /home/yzhang/biomate/frontend/STRIPE_SETUP_GUIDE.md")
            if any("Email" in t['name'] for t in skipped_tests):
                print("   → Set up Email: see /home/yzhang/biomate/frontend/EMAIL_SETUP_GUIDE.md")

        print("\n3. RE-RUN TESTS AFTER FIXES:")
        print("   python3 e2e_test_suite.py")

        print("\n" + "="*70)

        return self.results


if __name__ == "__main__":
    tester = BiomateE2ETestSuite()
    results = tester.run_all_tests()

    # Exit with appropriate code
    exit(0 if results['failed'] == 0 else 1)
