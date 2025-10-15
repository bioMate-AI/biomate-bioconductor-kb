"""
Execution Page Object

Encapsulates interactions with parameter editing, execution timeline, and job logs.
Provides methods for monitoring workflow execution progress and validating outputs.
"""

from typing import List, Dict, Any, Optional
from playwright.sync_api import Page, Locator


class ParameterDialog:
    """Handles parameter editing dialog interactions"""

    def __init__(self, page: Page):
        self.page = page
        self.dialog = page.locator('[data-testid="parameter-dialog"]')
        self.save_button = page.locator('[data-testid="button-save-parameters"]')
        self.cancel_button = page.locator('[data-testid="button-cancel-parameters"]')

    def is_open(self) -> bool:
        """Check if parameter dialog is open"""
        return self.dialog.is_visible()

    def wait_for_open(self, timeout: int = 5000):
        """Wait for parameter dialog to open"""
        self.dialog.wait_for(state="visible", timeout=timeout)

    def get_parameter_input(self, param_name: str) -> Locator:
        """
        Get input element for a specific parameter

        Args:
            param_name: Parameter name (will be converted to test ID format)

        Returns:
            Locator for the parameter input
        """
        test_id = param_name.lower().replace(' ', '-')
        return self.page.locator(f'[data-testid="parameter-input-{test_id}"]')

    def set_parameter_value(self, param_name: str, value: Any):
        """
        Set a parameter value

        Args:
            param_name: Parameter name
            value: Value to set (string, number, or boolean)
        """
        input_element = self.get_parameter_input(param_name)

        # Handle different input types
        if isinstance(value, bool):
            # For switch/checkbox inputs
            if value:
                input_element.check()
            else:
                input_element.uncheck()
        else:
            # For text/number inputs
            input_element.fill(str(value))

    def get_parameter_value(self, param_name: str) -> str:
        """Get current value of a parameter"""
        return self.get_parameter_input(param_name).input_value()

    def save(self):
        """Save parameter changes"""
        self.save_button.click()
        self.dialog.wait_for(state="hidden")

    def cancel(self):
        """Cancel parameter changes"""
        self.cancel_button.click()
        self.dialog.wait_for(state="hidden")


class ExecutionTimeline:
    """Handles execution timeline interactions"""

    def __init__(self, page: Page):
        self.page = page
        self.timeline = page.locator('[data-testid="execution-timeline"]')

    def is_visible(self) -> bool:
        """Check if execution timeline is visible"""
        return self.timeline.is_visible()

    def wait_for_visible(self, timeout: int = 10000):
        """Wait for timeline to become visible"""
        self.timeline.wait_for(state="visible", timeout=timeout)

    def get_timeline_event(self, step_id: str) -> Locator:
        """
        Get timeline event for a specific step

        Args:
            step_id: Step identifier

        Returns:
            Locator for the timeline event
        """
        return self.page.locator(f'[data-testid="timeline-event-{step_id}"]')

    def get_event_status(self, step_id: str, status: str) -> Locator:
        """
        Get status badge for a timeline event

        Args:
            step_id: Step identifier
            status: Status to find (e.g., 'queued', 'running', 'completed', 'failed')

        Returns:
            Locator for the status badge
        """
        return self.page.locator(f'[data-testid="timeline-event-status-{status}"]')

    def get_elapsed_time(self, step_id: str) -> Locator:
        """Get elapsed time display for a step"""
        return self.page.locator(f'[data-testid="timeline-elapsed-{step_id}"]')

    def get_job_id(self, step_id: str) -> Locator:
        """Get job ID display for a step"""
        return self.page.locator(f'[data-testid="timeline-job-{step_id}"]')

    def wait_for_step_status(self, step_id: str, status: str, timeout: int = 60000):
        """
        Wait for a step to reach a specific status

        Args:
            step_id: Step identifier
            status: Target status
            timeout: Maximum wait time in milliseconds
        """
        # Wait for the timeline event to appear
        self.get_timeline_event(step_id).wait_for(state="visible", timeout=timeout)
        # Wait for the specific status badge
        self.get_event_status(step_id, status).wait_for(state="visible", timeout=timeout)

    def is_step_completed(self, step_id: str) -> bool:
        """Check if a step has completed"""
        return self.get_event_status(step_id, "completed").is_visible()

    def is_step_failed(self, step_id: str) -> bool:
        """Check if a step has failed"""
        return self.get_event_status(step_id, "failed").is_visible()

    def is_step_running(self, step_id: str) -> bool:
        """Check if a step is currently running"""
        return self.get_event_status(step_id, "running").is_visible()


class JobLogViewer:
    """Handles job log viewer interactions"""

    def __init__(self, page: Page):
        self.page = page

    def get_log_viewer(self, step_id: str) -> Locator:
        """Get log viewer component for a specific step"""
        return self.page.locator(f'[data-testid="job-log-viewer-{step_id}"]')

    def get_log_content(self, step_id: str) -> Locator:
        """Get log content container for a step"""
        return self.page.locator(f'[data-testid="log-content-{step_id}"]')

    def get_log_entry(self, step_id: str, index: int) -> Locator:
        """
        Get a specific log entry

        Args:
            step_id: Step identifier
            index: Log entry index

        Returns:
            Locator for the log entry
        """
        return self.page.locator(f'[data-testid="log-entry-{step_id}-{index}"]')

    def get_log_search_input(self, step_id: str) -> Locator:
        """Get log search input field"""
        return self.page.locator(f'[data-testid="log-search-{step_id}"]')

    def get_auto_scroll_button(self, step_id: str) -> Locator:
        """Get auto-scroll toggle button"""
        return self.page.locator(f'[data-testid="log-auto-scroll-{step_id}"]')

    def get_download_logs_button(self, step_id: str) -> Locator:
        """Get download logs button"""
        return self.page.locator(f'[data-testid="button-download-logs-{step_id}"]')

    def get_clear_logs_button(self, step_id: str) -> Locator:
        """Get clear logs button"""
        return self.page.locator(f'[data-testid="button-clear-logs-{step_id}"]')

    def wait_for_logs(self, step_id: str, timeout: int = 30000):
        """Wait for logs to appear for a step"""
        self.get_log_viewer(step_id).wait_for(state="visible", timeout=timeout)
        # Wait for at least one log entry
        self.get_log_entry(step_id, 0).wait_for(state="visible", timeout=timeout)

    def search_logs(self, step_id: str, query: str):
        """
        Search logs for a specific query

        Args:
            step_id: Step identifier
            query: Search query string
        """
        self.get_log_search_input(step_id).fill(query)

    def toggle_auto_scroll(self, step_id: str):
        """Toggle auto-scroll for logs"""
        self.get_auto_scroll_button(step_id).click()

    def download_logs(self, step_id: str):
        """Download logs for a step"""
        self.get_download_logs_button(step_id).click()

    def clear_logs(self, step_id: str):
        """Clear logs for a step"""
        self.get_clear_logs_button(step_id).click()

    def get_log_text(self, step_id: str) -> str:
        """Get all log text content"""
        return self.get_log_content(step_id).inner_text()

    def has_error_in_logs(self, step_id: str) -> bool:
        """Check if logs contain any error messages"""
        log_text = self.get_log_text(step_id).lower()
        return 'error' in log_text or 'fail' in log_text


class ExecutionPage:
    """
    Main execution page object combining all execution-related components
    """

    def __init__(self, page: Page):
        self.page = page
        self.parameter_dialog = ParameterDialog(page)
        self.timeline = ExecutionTimeline(page)
        self.logs = JobLogViewer(page)

    def edit_parameters(self, step_id: str, parameters: Dict[str, Any]):
        """
        Edit parameters for a step

        Args:
            step_id: Step identifier
            parameters: Dictionary of parameter name -> value mappings
        """
        # Open parameter dialog (assumes workflow page has already clicked edit button)
        self.parameter_dialog.wait_for_open()

        # Set each parameter
        for param_name, value in parameters.items():
            self.parameter_dialog.set_parameter_value(param_name, value)

        # Save changes
        self.parameter_dialog.save()

    def monitor_step_execution(self, step_id: str, timeout: int = 120000) -> bool:
        """
        Monitor a step execution until completion or failure

        Args:
            step_id: Step identifier
            timeout: Maximum wait time in milliseconds

        Returns:
            True if step completed successfully, False if failed
        """
        # Wait for step to appear in timeline
        self.timeline.wait_for_visible()
        self.timeline.get_timeline_event(step_id).wait_for(state="visible")

        # Wait for terminal status (completed or failed)
        try:
            self.timeline.wait_for_step_status(step_id, "completed", timeout)
            return True
        except:
            # Check if failed
            if self.timeline.is_step_failed(step_id):
                return False
            raise

    def validate_step_completion(self, step_id: str) -> Dict[str, Any]:
        """
        Validate step completion and gather execution details

        Args:
            step_id: Step identifier

        Returns:
            Dictionary containing execution validation results
        """
        return {
            'completed': self.timeline.is_step_completed(step_id),
            'failed': self.timeline.is_step_failed(step_id),
            'has_logs': self.logs.get_log_viewer(step_id).is_visible(),
            'has_errors': self.logs.has_error_in_logs(step_id) if self.logs.get_log_viewer(step_id).is_visible() else False,
        }
