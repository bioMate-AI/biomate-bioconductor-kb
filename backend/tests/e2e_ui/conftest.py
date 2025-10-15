"""
Pytest Configuration for BioMate E2E UI Tests

Provides fixtures for:
- Browser context with Playwright
- Screenshot management
- Video recording
- Test data setup
"""

import os
import pytest
import json
from pathlib import Path
from datetime import datetime
from playwright.sync_api import Browser, BrowserContext, Page, Playwright


# Test configuration
TEST_BASE_URL = os.getenv("BIOMATE_TEST_URL", "http://localhost:5173")
SCREENSHOTS_DIR = Path(__file__).parent / "test_screenshots"
VIDEOS_DIR = Path(__file__).parent / "test_videos"
REPORTS_DIR = Path(__file__).parent / "reports"

# Ensure directories exist
SCREENSHOTS_DIR.mkdir(exist_ok=True)
VIDEOS_DIR.mkdir(exist_ok=True)
REPORTS_DIR.mkdir(exist_ok=True)


@pytest.fixture(scope="session")
def browser_context_args(browser_context_args):
    """
    Configure browser context for visual testing.

    - Visible browser (headless=False)
    - Slow motion for observability (500ms delay)
    - Video recording enabled
    - 1920x1080 viewport
    """
    return {
        **browser_context_args,
        "viewport": {"width": 1920, "height": 1080},
        "record_video_dir": str(VIDEOS_DIR),
        "record_video_size": {"width": 1920, "height": 1080}
    }


@pytest.fixture(scope="session")
def browser(playwright: Playwright) -> Browser:
    """
    Launch browser for testing.

    Uses Chromium with:
    - Visible window (headless=False)
    - Slow motion 500ms for visual observation
    """
    browser = playwright.chromium.launch(
        headless=False,
        slow_mo=500  # 500ms delay between actions for visibility
    )
    yield browser
    browser.close()


@pytest.fixture(scope="function")
def context(browser: Browser, browser_context_args) -> BrowserContext:
    """Create a new browser context for each test."""
    context = browser.new_context(**browser_context_args)
    yield context
    context.close()


@pytest.fixture(scope="function")
def page(context: BrowserContext) -> Page:
    """Create a new page for each test."""
    page = context.new_page()
    page.goto(TEST_BASE_URL)
    yield page
    page.close()


@pytest.fixture(scope="function")
def screenshot_manager(request):
    """
    Provide screenshot management for test cases.

    Usage:
        def test_example(screenshot_manager):
            screenshot_manager.capture(page, "step_1_chat_input")
    """
    from utilities.screenshot_manager import ScreenshotManager

    test_name = request.node.name
    manager = ScreenshotManager(test_name)

    yield manager

    # Generate HTML snippet for this test's screenshots
    manager.generate_html_snippet()


@pytest.fixture(scope="function")
def parameter_validator():
    """
    Provide parameter validation utility.

    Usage:
        def test_example(parameter_validator):
            results = parameter_validator.validate_generated_parameters(
                actual=api_response['generated_parameters'],
                expected=EXPECTED_PARAMS,
                min_confidence=0.7
            )
            assert results['passed'] >= 1
    """
    from utilities.parameter_validator import ParameterValidator

    return ParameterValidator()


@pytest.fixture(scope="function")
def workflow_validator():
    """
    Provide workflow structure validation.

    Usage:
        def test_example(workflow_validator):
            is_valid = workflow_validator.validate_workflow_structure(
                workflow_ga,
                expected_steps=4,
                expected_connections=[(0, 1), (1, 2), (2, 3)]
            )
            assert is_valid
    """
    from utilities.workflow_validator import WorkflowValidator

    return WorkflowValidator()


@pytest.fixture(scope="session")
def expected_parameters():
    """
    Load expected parameters for all test cases.

    Returns:
        Dict mapping test IDs to expected parameter specifications
    """
    params_file = Path(__file__).parent / "test_data" / "expected_parameters.json"

    if params_file.exists():
        with open(params_file, 'r') as f:
            return json.load(f)
    else:
        # Return empty dict if file doesn't exist yet
        return {}


@pytest.fixture(scope="session")
def test_session_id():
    """Generate unique ID for this test session."""
    return datetime.now().strftime("%Y%m%d_%H%M%S")


def pytest_configure(config):
    """Pytest hook to configure test run."""
    # Add custom markers
    config.addinivalue_line(
        "markers", "slow: marks tests as slow (deselect with '-m \"not slow\"')"
    )
    config.addinivalue_line(
        "markers", "visual: marks tests that require visual observation"
    )
    config.addinivalue_line(
        "markers", "parameter_validation: tests that validate parameter generation"
    )
    config.addinivalue_line(
        "markers", "workflow_execution: tests that execute full workflows"
    )


def pytest_collection_modifyitems(config, items):
    """Pytest hook to modify collected tests."""
    # Mark all tests in e2e_ui as slow and visual by default
    for item in items:
        if "e2e_ui" in str(item.fspath):
            item.add_marker(pytest.mark.slow)
            item.add_marker(pytest.mark.visual)


@pytest.hookimpl(tryfirst=True, hookwrapper=True)
def pytest_runtest_makereport(item, call):
    """
    Pytest hook to capture test results.

    Adds test outcome to item for use in fixtures.
    """
    outcome = yield
    rep = outcome.get_result()

    setattr(item, f"rep_{rep.when}", rep)


@pytest.fixture(scope="function", autouse=True)
def log_test_start_end(request):
    """Automatically log test start and end."""
    test_name = request.node.name
    print(f"\n{'='*80}")
    print(f"Starting test: {test_name}")
    print(f"{'='*80}\n")

    yield

    print(f"\n{'='*80}")
    print(f"Finished test: {test_name}")
    if hasattr(request.node, 'rep_call'):
        outcome = request.node.rep_call.outcome
        print(f"Outcome: {outcome.upper()}")
    print(f"{'='*80}\n")


# Helper function for common wait conditions
def wait_for_workflow_generation(page: Page, timeout: int = 15000):
    """
    Wait for workflow generation to complete.

    Args:
        page: Playwright page object
        timeout: Max wait time in milliseconds

    Returns:
        True if workflow generated, False otherwise
    """
    try:
        # Wait for workflow suggestion in chat response
        page.wait_for_selector(
            '[data-testid="workflow-suggestion"], .workflow-generated',
            timeout=timeout
        )
        return True
    except Exception:
        return False


def wait_for_workflow_execution_complete(page: Page, timeout: int = 600000):
    """
    Wait for workflow execution to complete.

    Args:
        page: Playwright page object
        timeout: Max wait time in milliseconds (default 10 minutes)

    Returns:
        True if completed, False otherwise
    """
    try:
        # Wait for completion status
        page.wait_for_selector(
            '[data-testid="workflow-status-completed"], .execution-complete',
            timeout=timeout
        )
        return True
    except Exception:
        return False


# Export helper functions
__all__ = [
    'wait_for_workflow_generation',
    'wait_for_workflow_execution_complete',
    'TEST_BASE_URL',
    'SCREENSHOTS_DIR',
    'VIDEOS_DIR',
    'REPORTS_DIR'
]
