"""
Workflow Page Object

Encapsulates all interactions with the workflow builder and graph interface.
Provides methods for workflow manipulation, step execution, and parameter editing.
"""

from typing import Optional
from playwright.sync_api import Page, expect, Locator


class WorkflowPage:
    """Page object for BioMate workflow builder and graph"""

    def __init__(self, page: Page):
        self.page = page

        # Workflow-level locators
        self.workflow_graph = page.locator('[data-testid="workflow-graph"]')
        self.execute_workflow_button = page.locator('[data-testid="button-execute-workflow"]')

    def get_workflow_status(self, status: str) -> Locator:
        """
        Get workflow status badge element

        Args:
            status: Status to find (e.g., 'idle', 'running', 'completed', 'failed')

        Returns:
            Locator for the status badge
        """
        return self.page.locator(f'[data-testid="workflow-status-{status}"]')

    def get_step_node(self, step_id: str) -> Locator:
        """
        Get a specific workflow step node

        Args:
            step_id: The step identifier

        Returns:
            Locator for the step node
        """
        return self.page.locator(f'[data-testid="graph-node-{step_id}"]')

    def get_step_run_button(self, step_id: str) -> Locator:
        """Get the run button for a specific step"""
        return self.page.locator(f'[data-testid="button-graph-run-{step_id}"]')

    def get_step_pause_button(self, step_id: str) -> Locator:
        """Get the pause button for a specific step"""
        return self.page.locator(f'[data-testid="button-graph-pause-{step_id}"]')

    def get_step_restart_button(self, step_id: str) -> Locator:
        """Get the restart button for a specific step"""
        return self.page.locator(f'[data-testid="button-graph-restart-{step_id}"]')

    def get_step_edit_button(self, step_id: str) -> Locator:
        """Get the edit button for a specific step"""
        return self.page.locator(f'[data-testid="button-graph-edit-{step_id}"]')

    def get_step_delete_button(self, step_id: str) -> Locator:
        """Get the delete button for a specific step"""
        return self.page.locator(f'[data-testid="button-graph-delete-{step_id}"]')

    def wait_for_workflow_loaded(self, timeout: int = 10000):
        """Wait for workflow graph to be loaded and visible"""
        self.workflow_graph.wait_for(state="visible", timeout=timeout)

    def execute_workflow(self):
        """Execute the entire workflow"""
        self.execute_workflow_button.click()

    def execute_step(self, step_id: str):
        """
        Execute a specific workflow step

        Args:
            step_id: The step identifier to execute
        """
        self.get_step_run_button(step_id).click()

    def pause_step(self, step_id: str):
        """
        Pause a running step

        Args:
            step_id: The step identifier to pause
        """
        self.get_step_pause_button(step_id).click()

    def restart_step(self, step_id: str):
        """
        Restart a failed or paused step

        Args:
            step_id: The step identifier to restart
        """
        self.get_step_restart_button(step_id).click()

    def edit_step_parameters(self, step_id: str):
        """
        Open parameter editing dialog for a step

        Args:
            step_id: The step identifier to edit
        """
        self.get_step_edit_button(step_id).click()
        # Wait for parameter dialog to open
        self.page.locator('[data-testid="parameter-dialog"]').wait_for(state="visible")

    def delete_step(self, step_id: str):
        """
        Delete a workflow step

        Args:
            step_id: The step identifier to delete
        """
        self.get_step_delete_button(step_id).click()

    def is_step_visible(self, step_id: str) -> bool:
        """Check if a step is visible in the workflow graph"""
        return self.get_step_node(step_id).is_visible()

    def get_all_step_nodes(self):
        """Get all workflow step nodes"""
        return self.page.locator('[data-testid^="graph-node-"]').all()

    def get_step_count(self) -> int:
        """Get the number of steps in the workflow"""
        return self.page.locator('[data-testid^="graph-node-"]').count()

    def wait_for_status(self, status: str, timeout: int = 60000):
        """
        Wait for workflow to reach a specific status

        Args:
            status: Target status to wait for
            timeout: Maximum wait time in milliseconds
        """
        self.get_workflow_status(status).wait_for(state="visible", timeout=timeout)

    def is_workflow_running(self) -> bool:
        """Check if workflow is currently running"""
        return self.get_workflow_status("running").is_visible()

    def is_workflow_completed(self) -> bool:
        """Check if workflow has completed"""
        return self.get_workflow_status("completed").is_visible()

    def is_workflow_failed(self) -> bool:
        """Check if workflow has failed"""
        return self.get_workflow_status("failed").is_visible()
