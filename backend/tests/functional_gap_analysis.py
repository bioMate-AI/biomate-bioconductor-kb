#!/usr/bin/env python3
"""
Comprehensive Functional Gap Analysis for Biomate
Tests entire user journey: Registration → Login → Platform → Workflow → Output
"""

import requests
import json
import time
from datetime import datetime
from typing import Dict, List, Any

class FunctionalGapAnalyzer:
    def __init__(self, base_url: str = "http://localhost:5000"):
        self.base_url = base_url
        self.results = {
            "timestamp": datetime.now().isoformat(),
            "categories": {},
            "gaps": [],
            "critical_issues": [],
            "passed": 0,
            "failed": 0,
            "warnings": 0
        }
        self.session = requests.Session()

    def test_category(self, category: str, description: str):
        """Start a new test category"""
        print(f"\n{'='*80}")
        print(f"CATEGORY: {category}")
        print(f"Description: {description}")
        print(f"{'='*80}")
        self.results["categories"][category] = {
            "description": description,
            "tests": [],
            "passed": 0,
            "failed": 0,
            "warnings": 0
        }
        self.current_category = category

    def test(self, name: str, test_func, critical: bool = False):
        """Run a single test"""
        print(f"\n[TEST] {name}...", end=" ")
        try:
            result = test_func()
            if result["status"] == "PASS":
                print("✓ PASS")
                self.results["passed"] += 1
                self.results["categories"][self.current_category]["passed"] += 1
            elif result["status"] == "FAIL":
                print("✗ FAIL")
                self.results["failed"] += 1
                self.results["categories"][self.current_category]["failed"] += 1
                if critical:
                    self.results["critical_issues"].append({
                        "category": self.current_category,
                        "test": name,
                        "error": result.get("error", "Unknown error")
                    })
                if result.get("gap"):
                    self.results["gaps"].append({
                        "category": self.current_category,
                        "test": name,
                        "gap": result["gap"]
                    })
            elif result["status"] == "WARN":
                print("⚠ WARNING")
                self.results["warnings"] += 1
                self.results["categories"][self.current_category]["warnings"] += 1

            self.results["categories"][self.current_category]["tests"].append({
                "name": name,
                "status": result["status"],
                "details": result.get("details", ""),
                "error": result.get("error"),
                "gap": result.get("gap")
            })

            if result.get("details"):
                print(f"    Details: {result['details']}")
            if result.get("error"):
                print(f"    Error: {result['error']}")
            if result.get("gap"):
                print(f"    Gap: {result['gap']}")

        except Exception as e:
            print(f"✗ EXCEPTION: {str(e)}")
            self.results["failed"] += 1
            self.results["categories"][self.current_category]["failed"] += 1
            if critical:
                self.results["critical_issues"].append({
                    "category": self.current_category,
                    "test": name,
                    "error": str(e)
                })

    # ========================================================================
    # CATEGORY 1: API HEALTH & CONNECTIVITY
    # ========================================================================

    def test_api_health(self):
        """Test API health endpoint"""
        try:
            response = self.session.get(f"{self.base_url}/api/health", timeout=5)
            if response.status_code == 200:
                data = response.json()
                return {"status": "PASS", "details": f"API healthy: {data}"}
            else:
                return {"status": "FAIL", "error": f"Status code: {response.status_code}"}
        except Exception as e:
            return {"status": "FAIL", "error": str(e)}

    def test_galaxy_connection(self):
        """Test Galaxy backend connection"""
        try:
            response = self.session.get(f"{self.base_url}/api/galaxy/version", timeout=5)
            if response.status_code == 200:
                data = response.json()
                return {"status": "PASS", "details": f"Galaxy v{data.get('version_major')}.{data.get('version_minor')}"}
            elif response.status_code == 401:
                return {"status": "WARN", "details": "Galaxy requires authentication (expected)", "gap": "Need to test with authentication"}
            else:
                return {"status": "FAIL", "error": f"Status code: {response.status_code}"}
        except Exception as e:
            return {"status": "FAIL", "error": str(e)}

    # ========================================================================
    # CATEGORY 2: REGISTRATION FLOW
    # ========================================================================

    def test_registration_page(self):
        """Test registration page loads"""
        try:
            response = self.session.get(f"{self.base_url}/register", timeout=5)
            if response.status_code == 200:
                html = response.text
                # Check for key elements
                has_email = 'email' in html.lower()
                has_password = 'password' in html.lower()
                has_terms = 'terms' in html.lower()

                if has_email and has_password and has_terms:
                    return {"status": "PASS", "details": "Registration form present"}
                else:
                    return {"status": "WARN", "details": f"Missing elements: email={has_email}, password={has_password}, terms={has_terms}"}
            else:
                return {"status": "FAIL", "error": f"Status code: {response.status_code}"}
        except Exception as e:
            return {"status": "FAIL", "error": str(e)}

    def test_registration_api_exists(self):
        """Test registration API endpoint exists"""
        try:
            # Try with empty data to see if endpoint exists
            response = self.session.post(
                f"{self.base_url}/api/auth/register",
                json={},
                timeout=5
            )
            # Any response other than 404 means endpoint exists
            if response.status_code != 404:
                return {"status": "PASS", "details": f"Registration API exists (status: {response.status_code})"}
            else:
                return {"status": "FAIL", "error": "Registration API not found", "gap": "Registration endpoint missing"}
        except Exception as e:
            return {"status": "FAIL", "error": str(e)}

    def test_payment_integration(self):
        """Test if Stripe payment is integrated"""
        try:
            # Check if Stripe is configured by looking for checkout endpoint
            response = self.session.post(
                f"{self.base_url}/api/payments/create-checkout-session",
                json={"priceId": "test", "email": "test@test.com"},
                timeout=5
            )

            if response.status_code == 200:
                return {"status": "PASS", "details": "Stripe checkout endpoint functional"}
            elif response.status_code == 400:
                error = response.json().get("error", "")
                if "not configured" in error.lower():
                    return {
                        "status": "FAIL",
                        "error": "Stripe not configured",
                        "gap": "CRITICAL: Payment integration not configured - User requirement!"
                    }
                else:
                    return {"status": "WARN", "details": "Stripe endpoint exists but returned error"}
            else:
                return {"status": "FAIL", "error": f"Unexpected status: {response.status_code}"}
        except Exception as e:
            return {"status": "FAIL", "error": str(e)}

    # ========================================================================
    # CATEGORY 3: LOGIN & AUTHENTICATION
    # ========================================================================

    def test_login_page(self):
        """Test login page loads"""
        try:
            response = self.session.get(f"{self.base_url}/login", timeout=5)
            if response.status_code == 200:
                return {"status": "PASS", "details": "Login page accessible"}
            else:
                return {"status": "FAIL", "error": f"Status code: {response.status_code}"}
        except Exception as e:
            return {"status": "FAIL", "error": str(e)}

    def test_login_api_exists(self):
        """Test login API endpoint exists"""
        try:
            response = self.session.post(
                f"{self.base_url}/api/auth/login",
                json={"email": "test@test.com", "password": "test"},
                timeout=5
            )
            if response.status_code != 404:
                return {"status": "PASS", "details": f"Login API exists (status: {response.status_code})"}
            else:
                return {"status": "FAIL", "error": "Login API not found"}
        except Exception as e:
            return {"status": "FAIL", "error": str(e)}

    def test_oauth_configured(self):
        """Test if OAuth is configured"""
        try:
            # Check for Google OAuth
            response_google = self.session.get(f"{self.base_url}/api/auth/google", timeout=5)
            google_configured = response_google.status_code != 404

            # Check for GitHub OAuth
            response_github = self.session.get(f"{self.base_url}/api/auth/github", timeout=5)
            github_configured = response_github.status_code != 404

            if google_configured or github_configured:
                providers = []
                if google_configured:
                    providers.append("Google")
                if github_configured:
                    providers.append("GitHub")
                return {"status": "PASS", "details": f"OAuth configured: {', '.join(providers)}"}
            else:
                return {
                    "status": "WARN",
                    "details": "OAuth endpoints not found",
                    "gap": "OAuth (Google/GitHub) not configured"
                }
        except Exception as e:
            return {"status": "WARN", "error": str(e), "gap": "Could not verify OAuth configuration"}

    # ========================================================================
    # CATEGORY 4: PLATFORM INTERFACE
    # ========================================================================

    def test_homepage(self):
        """Test main platform page"""
        try:
            response = self.session.get(f"{self.base_url}/", timeout=5)
            if response.status_code == 200:
                html = response.text
                # Check if it's just a minimal page
                if len(html) < 500:
                    return {
                        "status": "FAIL",
                        "error": "Homepage appears to be incomplete (< 500 bytes)",
                        "gap": "CRITICAL: Main platform interface missing (home.tsx is 75 bytes)"
                    }
                else:
                    return {"status": "PASS", "details": f"Homepage loads ({len(html)} bytes)"}
            else:
                return {"status": "FAIL", "error": f"Status code: {response.status_code}"}
        except Exception as e:
            return {"status": "FAIL", "error": str(e)}

    def test_dashboard(self):
        """Test dashboard page"""
        try:
            response = self.session.get(f"{self.base_url}/dashboard", timeout=5)
            if response.status_code == 200:
                return {"status": "PASS", "details": "Dashboard accessible"}
            elif response.status_code == 401 or response.status_code == 403:
                return {"status": "WARN", "details": "Dashboard requires authentication (expected)"}
            else:
                return {"status": "FAIL", "error": f"Status code: {response.status_code}"}
        except Exception as e:
            return {"status": "FAIL", "error": str(e)}

    def test_chat_interface(self):
        """Test chat interface endpoint"""
        try:
            response = self.session.post(
                f"{self.base_url}/api/chat",
                json={"message": "test"},
                timeout=5
            )
            if response.status_code == 200:
                return {"status": "PASS", "details": "Chat API functional"}
            elif response.status_code == 401:
                return {"status": "WARN", "details": "Chat requires authentication (expected)"}
            elif response.status_code == 400:
                return {"status": "WARN", "details": "Chat API exists but returned validation error"}
            else:
                return {"status": "FAIL", "error": f"Status code: {response.status_code}"}
        except Exception as e:
            return {"status": "FAIL", "error": str(e)}

    # ========================================================================
    # CATEGORY 5: WORKFLOW FUNCTIONALITY
    # ========================================================================

    def test_workflow_list_endpoint(self):
        """Test workflow listing endpoint"""
        try:
            response = self.session.get(f"{self.base_url}/api/galaxy/workflows", timeout=5)
            if response.status_code == 200:
                return {"status": "PASS", "details": "Workflow list endpoint functional"}
            elif response.status_code == 401:
                return {"status": "WARN", "details": "Workflows require authentication (expected)"}
            else:
                return {"status": "FAIL", "error": f"Status code: {response.status_code}"}
        except Exception as e:
            return {"status": "FAIL", "error": str(e)}

    def test_workflow_invoke_endpoint(self):
        """Test workflow invocation endpoint"""
        try:
            response = self.session.post(
                f"{self.base_url}/api/galaxy/workflows/invoke",
                json={"workflow_id": "test", "inputs": {}},
                timeout=5
            )
            if response.status_code != 404:
                return {"status": "PASS", "details": f"Workflow invoke endpoint exists (status: {response.status_code})"}
            else:
                return {"status": "FAIL", "error": "Workflow invoke endpoint not found"}
        except Exception as e:
            return {"status": "FAIL", "error": str(e)}

    def test_sse_endpoint(self):
        """Test Server-Sent Events endpoint for real-time updates"""
        try:
            # Just check if endpoint exists (don't wait for events)
            response = self.session.get(
                f"{self.base_url}/api/galaxy/workflows/sse/test_id",
                timeout=2,
                stream=True
            )
            if response.status_code == 200:
                return {"status": "PASS", "details": "SSE endpoint functional"}
            elif response.status_code == 401:
                return {"status": "WARN", "details": "SSE requires authentication", "gap": "SSE endpoint not authenticated (security issue)"}
            else:
                return {"status": "FAIL", "error": f"Status code: {response.status_code}"}
        except requests.exceptions.Timeout:
            return {"status": "WARN", "details": "SSE endpoint timeout (may be waiting for events)"}
        except Exception as e:
            return {"status": "FAIL", "error": str(e)}

    def test_pause_resume_endpoints(self):
        """Test job pause/resume functionality"""
        try:
            # Test pause endpoint
            response_pause = self.session.put(
                f"{self.base_url}/api/galaxy/jobs/test_job/pause",
                timeout=5
            )
            pause_exists = response_pause.status_code != 404

            # Test resume endpoint
            response_resume = self.session.put(
                f"{self.base_url}/api/galaxy/jobs/test_job/resume",
                timeout=5
            )
            resume_exists = response_resume.status_code != 404

            if pause_exists and resume_exists:
                return {"status": "PASS", "details": "Pause/resume endpoints exist"}
            elif pause_exists or resume_exists:
                return {"status": "WARN", "details": "Only one of pause/resume endpoints found"}
            else:
                return {"status": "FAIL", "error": "Pause/resume endpoints not found", "gap": "Job control features missing"}
        except Exception as e:
            return {"status": "FAIL", "error": str(e)}

    # ========================================================================
    # CATEGORY 6: DATASET MANAGEMENT
    # ========================================================================

    def test_dataset_list_endpoint(self):
        """Test dataset listing endpoint"""
        try:
            response = self.session.get(f"{self.base_url}/api/galaxy/datasets", timeout=5)
            if response.status_code == 200:
                return {"status": "PASS", "details": "Dataset list endpoint functional"}
            elif response.status_code == 401:
                return {"status": "WARN", "details": "Datasets require authentication (expected)"}
            else:
                return {"status": "FAIL", "error": f"Status code: {response.status_code}"}
        except Exception as e:
            return {"status": "FAIL", "error": str(e)}

    def test_dataset_upload_endpoint(self):
        """Test dataset upload endpoint"""
        try:
            response = self.session.post(
                f"{self.base_url}/api/datasets/upload",
                files={"file": ("test.txt", b"test data", "text/plain")},
                timeout=5
            )
            if response.status_code != 404:
                return {"status": "PASS", "details": f"Dataset upload endpoint exists (status: {response.status_code})"}
            else:
                return {"status": "FAIL", "error": "Dataset upload endpoint not found"}
        except Exception as e:
            return {"status": "FAIL", "error": str(e)}

    def test_s3_integration(self):
        """Test S3 file storage integration"""
        try:
            response = self.session.post(
                f"{self.base_url}/api/s3/upload/init",
                json={"filename": "test.txt", "contentType": "text/plain"},
                timeout=5
            )
            if response.status_code == 200:
                return {"status": "PASS", "details": "S3 integration functional"}
            elif response.status_code == 401:
                return {"status": "WARN", "details": "S3 requires authentication (expected)"}
            elif response.status_code == 400:
                error = response.json().get("error", "")
                if "not configured" in error.lower():
                    return {"status": "WARN", "details": "S3 not configured", "gap": "S3 storage not configured"}
                else:
                    return {"status": "WARN", "details": f"S3 endpoint exists: {error}"}
            else:
                return {"status": "FAIL", "error": f"Status code: {response.status_code}"}
        except Exception as e:
            return {"status": "FAIL", "error": str(e)}

    # ========================================================================
    # CATEGORY 7: INFRASTRUCTURE SERVICES
    # ========================================================================

    def test_redis_configured(self):
        """Test if Redis is configured (check session behavior)"""
        # This is indirect - we can't directly test Redis without auth
        # But we can check if session endpoints work
        try:
            response = self.session.get(f"{self.base_url}/api/auth/session", timeout=5)
            # If endpoint exists, Redis may be configured
            if response.status_code != 404:
                return {"status": "WARN", "details": "Session endpoint exists (Redis status unknown)", "gap": "Cannot verify Redis without authentication"}
            else:
                return {"status": "WARN", "details": "Cannot verify Redis configuration", "gap": "Need Redis verification test"}
        except Exception as e:
            return {"status": "WARN", "error": str(e), "gap": "Redis verification not possible"}

    def test_email_service(self):
        """Test if email service is configured"""
        try:
            # Try to trigger password reset email
            response = self.session.post(
                f"{self.base_url}/api/auth/forgot-password",
                json={"email": "test@test.com"},
                timeout=5
            )
            if response.status_code == 200:
                data = response.json()
                if "email not configured" in str(data).lower():
                    return {
                        "status": "FAIL",
                        "error": "Email service not configured",
                        "gap": "CRITICAL: Email service required for verification, password resets"
                    }
                else:
                    return {"status": "PASS", "details": "Email service appears configured"}
            elif response.status_code == 404:
                return {"status": "WARN", "details": "Forgot password endpoint not found", "gap": "Password reset not implemented"}
            else:
                return {"status": "WARN", "details": f"Email endpoint exists (status: {response.status_code})"}
        except Exception as e:
            return {"status": "WARN", "error": str(e)}

    # ========================================================================
    # RUN ALL TESTS
    # ========================================================================

    def run_all_tests(self):
        """Execute all functional tests"""
        print("\n" + "="*80)
        print("BIOMATE FUNCTIONAL GAP ANALYSIS")
        print("="*80)
        print(f"Started: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        print(f"Base URL: {self.base_url}")

        # Category 1: API Health & Connectivity
        self.test_category("api_health", "API Health & Backend Connectivity")
        self.test("API Health Check", self.test_api_health, critical=True)
        self.test("Galaxy Backend Connection", self.test_galaxy_connection, critical=True)

        # Category 2: Registration Flow
        self.test_category("registration", "User Registration & Payment")
        self.test("Registration Page Loads", self.test_registration_page)
        self.test("Registration API Exists", self.test_registration_api_exists, critical=True)
        self.test("Payment Integration", self.test_payment_integration, critical=True)

        # Category 3: Login & Authentication
        self.test_category("authentication", "Login & Authentication")
        self.test("Login Page Loads", self.test_login_page)
        self.test("Login API Exists", self.test_login_api_exists, critical=True)
        self.test("OAuth Configured", self.test_oauth_configured)

        # Category 4: Platform Interface
        self.test_category("platform_interface", "Main Platform Interface")
        self.test("Homepage/Platform Page", self.test_homepage, critical=True)
        self.test("Dashboard Page", self.test_dashboard)
        self.test("Chat Interface API", self.test_chat_interface)

        # Category 5: Workflow Functionality
        self.test_category("workflows", "Workflow Creation & Execution")
        self.test("Workflow List Endpoint", self.test_workflow_list_endpoint)
        self.test("Workflow Invoke Endpoint", self.test_workflow_invoke_endpoint, critical=True)
        self.test("SSE Real-time Updates", self.test_sse_endpoint)
        self.test("Pause/Resume Job Control", self.test_pause_resume_endpoints)

        # Category 6: Dataset Management
        self.test_category("datasets", "Dataset Upload & Management")
        self.test("Dataset List Endpoint", self.test_dataset_list_endpoint)
        self.test("Dataset Upload Endpoint", self.test_dataset_upload_endpoint)
        self.test("S3 Storage Integration", self.test_s3_integration)

        # Category 7: Infrastructure
        self.test_category("infrastructure", "Infrastructure Services")
        self.test("Redis Configuration", self.test_redis_configured)
        self.test("Email Service Configuration", self.test_email_service, critical=True)

        # Print Summary
        self.print_summary()

        # Save results
        self.save_results()

    def print_summary(self):
        """Print test results summary"""
        print("\n" + "="*80)
        print("SUMMARY")
        print("="*80)

        total = self.results["passed"] + self.results["failed"] + self.results["warnings"]
        print(f"\nTotal Tests: {total}")
        print(f"✓ Passed: {self.results['passed']} ({self.results['passed']/total*100:.1f}%)")
        print(f"✗ Failed: {self.results['failed']} ({self.results['failed']/total*100:.1f}%)")
        print(f"⚠ Warnings: {self.results['warnings']} ({self.results['warnings']/total*100:.1f}%)")

        # Category breakdown
        print("\n" + "-"*80)
        print("BY CATEGORY:")
        for category, data in self.results["categories"].items():
            cat_total = data["passed"] + data["failed"] + data["warnings"]
            status = "✓" if data["failed"] == 0 else "✗"
            print(f"{status} {category}: {data['passed']}/{cat_total} passed")

        # Critical issues
        if self.results["critical_issues"]:
            print("\n" + "-"*80)
            print("CRITICAL ISSUES:")
            for i, issue in enumerate(self.results["critical_issues"], 1):
                print(f"\n{i}. [{issue['category']}] {issue['test']}")
                print(f"   Error: {issue['error']}")

        # Functional gaps
        if self.results["gaps"]:
            print("\n" + "-"*80)
            print("FUNCTIONAL GAPS IDENTIFIED:")
            for i, gap in enumerate(self.results["gaps"], 1):
                print(f"\n{i}. [{gap['category']}] {gap['test']}")
                print(f"   Gap: {gap['gap']}")

        print("\n" + "="*80)

    def save_results(self):
        """Save results to JSON file"""
        filename = f"functional_gap_analysis_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
        filepath = f"/home/yzhang/biomate/backend/tests/{filename}"

        with open(filepath, 'w') as f:
            json.dump(self.results, f, indent=2)

        print(f"\nResults saved to: {filepath}")

if __name__ == "__main__":
    analyzer = FunctionalGapAnalyzer()
    analyzer.run_all_tests()
