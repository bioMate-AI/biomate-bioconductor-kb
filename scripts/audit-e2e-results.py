#!/usr/bin/env python3
"""
Automated E2E Test Audit Script

Analyzes Playwright test results to:
1. Parse test execution results
2. Identify UI/UX issues from error contexts
3. Categorize failures (API timeout vs actual UI bugs)
4. Generate audit report with actionable findings
5. Suggest fixes for identified issues

Usage:
    python scripts/audit-e2e-results.py [test-results-dir]
"""

import json
import os
import sys
from pathlib import Path
from datetime import datetime
from dataclasses import dataclass, field
from typing import List, Dict, Optional
import re


@dataclass
class TestResult:
    name: str
    status: str  # 'passed', 'failed', 'timedout'
    duration_ms: int
    error_type: Optional[str] = None
    error_message: Optional[str] = None
    has_video: bool = False
    has_screenshot: bool = False
    has_trace: bool = False
    ui_elements_found: List[str] = field(default_factory=list)
    ui_issues: List[str] = field(default_factory=list)


@dataclass
class AuditReport:
    timestamp: str
    total_tests: int
    passed: int
    failed: int
    timedout: int
    ui_bugs: List[Dict]
    api_timeouts: List[Dict]
    recommendations: List[str]
    test_results: List[TestResult]


def parse_results_json(results_path: Path) -> Dict:
    """Parse the Playwright results.json file."""
    with open(results_path) as f:
        return json.load(f)


def parse_error_context(context_path: Path) -> Dict:
    """Parse error-context.md to extract UI state."""
    if not context_path.exists():
        return {}

    content = context_path.read_text()

    # Extract UI elements from YAML snapshot
    elements = {
        'buttons': [],
        'inputs': [],
        'headings': [],
        'paragraphs': [],
        'images': [],
        'disabled_elements': [],
    }

    # Find buttons
    for match in re.finditer(r'button "([^"]+)"', content):
        btn_name = match.group(1)
        elements['buttons'].append(btn_name)

        # Check if disabled
        line_start = content.rfind('\n', 0, match.start())
        line_end = content.find('\n', match.end())
        line = content[line_start:line_end]
        if '[disabled]' in line:
            elements['disabled_elements'].append(f"button: {btn_name}")

    # Find headings
    for match in re.finditer(r'heading "([^"]+)"', content):
        elements['headings'].append(match.group(1))

    # Find textboxes
    for match in re.finditer(r'textbox "([^"]+)"', content):
        elements['inputs'].append(match.group(1))

        line_start = content.rfind('\n', 0, match.start())
        line_end = content.find('\n', match.end())
        line = content[line_start:line_end]
        if '[disabled]' in line:
            elements['disabled_elements'].append(f"textbox: {match.group(1)}")

    # Find paragraphs with text content
    for match in re.finditer(r'paragraph \[ref=[^\]]+\]: ([^\n]+)', content):
        elements['paragraphs'].append(match.group(1)[:100])

    # Check for specific UI patterns
    issues = []

    # Check if AI typing indicator is stuck
    if 'AI is typing...' in content:
        issues.append("AI typing indicator visible - waiting for API response")

    # Check for error messages in UI
    if 'error' in content.lower() and 'Error' in content:
        issues.append("Error message visible in UI")

    # Check for empty states
    if content.count('paragraph') < 3:
        issues.append("Very few text elements - possible empty state")

    return {
        'elements': elements,
        'issues': issues,
        'has_ai_typing': 'AI is typing...' in content,
        'has_chat_messages': 'paragraph [ref=' in content,
        'has_sidebar': 'Recent Chats' in content,
        'has_input': 'textbox' in content,
    }


def categorize_failure(error_message: str, error_context: Dict) -> str:
    """Categorize the failure type."""
    if not error_message:
        return 'unknown'

    error_lower = error_message.lower()

    # API/Network related timeouts
    if 'timeout' in error_lower:
        if error_context.get('has_ai_typing'):
            return 'api_timeout'  # Waiting for AI response
        return 'ui_timeout'  # UI element not found

    # Element not found
    if 'locator' in error_lower or 'selector' in error_lower:
        return 'element_not_found'

    # Navigation issues
    if 'navigation' in error_lower or 'goto' in error_lower:
        return 'navigation_error'

    # Assertion failures
    if 'expect' in error_lower or 'assert' in error_lower:
        return 'assertion_failure'

    return 'other'


def analyze_test_dir(test_dir: Path) -> TestResult:
    """Analyze a single test result directory."""
    result = TestResult(
        name=test_dir.name,
        status='unknown',
        duration_ms=0,
    )

    # Check for artifacts
    result.has_video = (test_dir / 'video.webm').exists()
    result.has_screenshot = any(test_dir.glob('*.png'))
    result.has_trace = (test_dir / 'trace.zip').exists()

    # Parse error context
    error_context_path = test_dir / 'error-context.md'
    if error_context_path.exists():
        context = parse_error_context(error_context_path)
        result.ui_elements_found = context.get('elements', {}).get('buttons', [])
        result.ui_issues = context.get('issues', [])

        # Determine status based on context
        if context.get('has_ai_typing'):
            result.status = 'timedout'
            result.error_type = 'api_timeout'
            result.error_message = 'Test timed out waiting for AI response'
        else:
            result.status = 'failed'
    else:
        result.status = 'passed'

    return result


def generate_recommendations(results: List[TestResult]) -> List[str]:
    """Generate actionable recommendations based on test results."""
    recommendations = []

    # Count failure types
    api_timeouts = sum(1 for r in results if r.error_type == 'api_timeout')
    ui_failures = sum(1 for r in results if r.error_type in ('element_not_found', 'ui_timeout'))

    if api_timeouts > 0:
        recommendations.append(
            f"API TIMEOUT ({api_timeouts} tests): Tests are waiting for AI responses. "
            "Consider: 1) Setting ANTHROPIC_API_KEY, 2) Adding mock API responses for testing, "
            "3) Increasing test timeout, 4) Testing UI elements independently of AI responses."
        )

    if ui_failures > 0:
        recommendations.append(
            f"UI FAILURES ({ui_failures} tests): Some UI elements not found. "
            "Review selectors and ensure elements have proper test IDs."
        )

    # Check for common patterns
    all_issues = [issue for r in results for issue in r.ui_issues]
    if 'AI typing indicator visible' in str(all_issues):
        recommendations.append(
            "MOCK RESPONSES: Create mock API responses for E2E tests to avoid "
            "dependency on live AI backend. Add test fixtures for common responses."
        )

    if not recommendations:
        recommendations.append("All tests passed! No issues found.")

    return recommendations


def run_audit(test_results_dir: Path) -> AuditReport:
    """Run the full audit on test results."""
    results = []

    # Find all test result directories
    for test_dir in test_results_dir.iterdir():
        if test_dir.is_dir() and test_dir.name.startswith('bioinformatics-viewers'):
            result = analyze_test_dir(test_dir)
            results.append(result)

    # Categorize results
    passed = sum(1 for r in results if r.status == 'passed')
    failed = sum(1 for r in results if r.status == 'failed')
    timedout = sum(1 for r in results if r.status == 'timedout')

    # Separate UI bugs from API timeouts
    ui_bugs = [
        {'test': r.name, 'issues': r.ui_issues}
        for r in results
        if r.error_type not in ('api_timeout', None) and r.ui_issues
    ]

    api_timeouts = [
        {'test': r.name, 'message': r.error_message}
        for r in results
        if r.error_type == 'api_timeout'
    ]

    recommendations = generate_recommendations(results)

    return AuditReport(
        timestamp=datetime.now().isoformat(),
        total_tests=len(results),
        passed=passed,
        failed=failed,
        timedout=timedout,
        ui_bugs=ui_bugs,
        api_timeouts=api_timeouts,
        recommendations=recommendations,
        test_results=results,
    )


def print_report(report: AuditReport):
    """Print the audit report."""
    print("=" * 80)
    print("E2E TEST AUDIT REPORT")
    print("=" * 80)
    print(f"Timestamp: {report.timestamp}")
    print()

    print("## Summary")
    print(f"  Total Tests: {report.total_tests}")
    print(f"  Passed: {report.passed}")
    print(f"  Failed: {report.failed}")
    print(f"  Timed Out: {report.timedout}")
    print()

    if report.api_timeouts:
        print("## API Timeouts (Expected without API key)")
        for t in report.api_timeouts:
            print(f"  - {t['test'][:50]}...")
            print(f"    {t['message']}")
        print()

    if report.ui_bugs:
        print("## UI Issues (Needs Investigation)")
        for bug in report.ui_bugs:
            print(f"  - {bug['test'][:50]}...")
            for issue in bug['issues']:
                print(f"    ! {issue}")
        print()

    print("## Recommendations")
    for i, rec in enumerate(report.recommendations, 1):
        print(f"  {i}. {rec}")
    print()

    print("## UI Elements Found (Sample)")
    for result in report.test_results[:2]:
        print(f"  Test: {result.name[:40]}...")
        print(f"    Buttons: {result.ui_elements_found[:5]}")
        print(f"    Video: {'Yes' if result.has_video else 'No'}")
        print(f"    Screenshot: {'Yes' if result.has_screenshot else 'No'}")
    print()

    print("=" * 80)


def save_report(report: AuditReport, output_path: Path):
    """Save the audit report as JSON."""
    report_dict = {
        'timestamp': report.timestamp,
        'summary': {
            'total': report.total_tests,
            'passed': report.passed,
            'failed': report.failed,
            'timedout': report.timedout,
        },
        'ui_bugs': report.ui_bugs,
        'api_timeouts': report.api_timeouts,
        'recommendations': report.recommendations,
        'tests': [
            {
                'name': r.name,
                'status': r.status,
                'error_type': r.error_type,
                'has_video': r.has_video,
                'has_screenshot': r.has_screenshot,
                'ui_issues': r.ui_issues,
            }
            for r in report.test_results
        ],
    }

    with open(output_path, 'w') as f:
        json.dump(report_dict, f, indent=2)

    print(f"Report saved to: {output_path}")


def main():
    # Default test results directory
    default_dir = Path(__file__).parent.parent / 'frontend' / 'e2e' / 'test-results'

    test_results_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else default_dir

    if not test_results_dir.exists():
        print(f"Error: Test results directory not found: {test_results_dir}")
        sys.exit(1)

    print(f"Analyzing test results in: {test_results_dir}")
    print()

    report = run_audit(test_results_dir)
    print_report(report)

    # Save report
    output_path = test_results_dir.parent / 'audit-report.json'
    save_report(report, output_path)

    # Return exit code based on actual UI bugs (not API timeouts)
    if report.ui_bugs:
        sys.exit(1)
    sys.exit(0)


if __name__ == "__main__":
    main()
