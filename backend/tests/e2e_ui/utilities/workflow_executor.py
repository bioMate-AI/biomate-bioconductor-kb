"""
Workflow Execution Test Utilities

Helpers for submitting, monitoring, and validating Galaxy workflows in e2e tests.
"""

import time
import requests
from typing import Dict, List, Optional, Any


class WorkflowExecutor:
    """Helper class for workflow execution testing"""

    def __init__(self, base_url: str = "http://localhost:5000"):
        self.base_url = base_url
        self.session = requests.Session()

    def invoke_workflow(
        self,
        workflow_id: str,
        inputs: Dict[str, Any],
        parameters: Optional[Dict[str, Any]] = None,
        priority: Optional[str] = None
    ) -> Dict[str, Any]:
        """
        Invoke a workflow with optional priority

        Args:
            workflow_id: Galaxy workflow ID
            inputs: Input dataset mappings
            parameters: Workflow parameters
            priority: Job priority (low/normal/high/critical)

        Returns:
            Invocation response from API
        """
        payload = {
            "workflow_id": workflow_id,
            "inputs": inputs,
            "parameters": parameters or {}
        }

        if priority:
            payload["parameters"]["__priority"] = priority

        response = self.session.post(
            f"{self.base_url}/api/galaxy/workflows/invoke",
            json=payload
        )
        response.raise_for_status()
        return response.json()

    def get_invocation_status(
        self,
        workflow_id: str,
        invocation_id: str
    ) -> Dict[str, Any]:
        """
        Get current invocation status

        Args:
            workflow_id: Galaxy workflow ID
            invocation_id: Invocation ID

        Returns:
            Invocation status from API
        """
        response = self.session.get(
            f"{self.base_url}/api/galaxy/workflows/{workflow_id}/invocations/{invocation_id}"
        )
        response.raise_for_status()
        return response.json()

    def wait_for_state(
        self,
        workflow_id: str,
        invocation_id: str,
        target_state: str,
        timeout: int = 300,
        poll_interval: int = 2
    ) -> Dict[str, Any]:
        """
        Poll invocation until it reaches target state

        Args:
            workflow_id: Galaxy workflow ID
            invocation_id: Invocation ID
            target_state: State to wait for (e.g., 'ok', 'scheduled')
            timeout: Maximum wait time in seconds
            poll_interval: Seconds between polls

        Returns:
            Final invocation status

        Raises:
            TimeoutError: If target state not reached within timeout
        """
        start_time = time.time()

        while time.time() - start_time < timeout:
            status = self.get_invocation_status(workflow_id, invocation_id)
            current_state = status.get('state', 'unknown')

            if current_state == target_state:
                return status

            # Check for error states
            if current_state in ['failed', 'cancelled']:
                raise Exception(f"Workflow entered terminal state: {current_state}")

            time.sleep(poll_interval)

        raise TimeoutError(
            f"Workflow did not reach state '{target_state}' within {timeout}s"
        )

    def wait_for_completion(
        self,
        workflow_id: str,
        invocation_id: str,
        timeout: int = 600
    ) -> Dict[str, Any]:
        """
        Wait for workflow to complete (all steps ok or error)

        Args:
            workflow_id: Galaxy workflow ID
            invocation_id: Invocation ID
            timeout: Maximum wait time in seconds

        Returns:
            Final invocation status
        """
        start_time = time.time()

        while time.time() - start_time < timeout:
            status = self.get_invocation_status(workflow_id, invocation_id)
            steps = status.get('steps', [])

            if not steps:
                time.sleep(2)
                continue

            # Check if all steps are in terminal state
            all_complete = all(
                step.get('state') in ['ok', 'error']
                for step in steps
            )

            if all_complete:
                return status

            time.sleep(2)

        raise TimeoutError(f"Workflow did not complete within {timeout}s")

    def get_step_states(
        self,
        workflow_id: str,
        invocation_id: str
    ) -> List[Dict[str, Any]]:
        """
        Get states of all workflow steps

        Returns:
            List of {step_id, state, job_id} dicts
        """
        status = self.get_invocation_status(workflow_id, invocation_id)
        steps = status.get('steps', [])

        return [
            {
                'step_id': step.get('id'),
                'state': step.get('state'),
                'job_id': step.get('job_id')
            }
            for step in steps
        ]

    def pause_job(self, job_id: str) -> Dict[str, Any]:
        """Pause a running job"""
        response = self.session.put(
            f"{self.base_url}/api/galaxy/jobs/{job_id}/pause"
        )
        response.raise_for_status()
        return response.json()

    def resume_job(self, job_id: str) -> Dict[str, Any]:
        """Resume a paused job"""
        response = self.session.put(
            f"{self.base_url}/api/galaxy/jobs/{job_id}/resume"
        )
        response.raise_for_status()
        return response.json()

    def get_job_status(self, job_id: str) -> Dict[str, Any]:
        """Get current job status"""
        response = self.session.get(
            f"{self.base_url}/api/galaxy/jobs/{job_id}"
        )
        response.raise_for_status()
        return response.json()

    def cancel_invocation(
        self,
        workflow_id: str,
        invocation_id: str
    ) -> None:
        """Cancel a running workflow invocation"""
        response = self.session.delete(
            f"{self.base_url}/api/galaxy/workflows/{workflow_id}/invocations/{invocation_id}"
        )
        response.raise_for_status()

    def calculate_progress(
        self,
        workflow_id: str,
        invocation_id: str
    ) -> Dict[str, Any]:
        """
        Calculate current workflow progress

        Returns:
            {
                'total_steps': int,
                'completed_steps': int,
                'progress_percent': float,
                'current_milestone': int (25/50/75/100 or None)
            }
        """
        status = self.get_invocation_status(workflow_id, invocation_id)
        steps = status.get('steps', [])

        total_steps = len(steps)
        completed_steps = sum(
            1 for step in steps
            if step.get('state') in ['ok', 'error']
        )

        progress_percent = (completed_steps / total_steps * 100) if total_steps > 0 else 0

        # Determine current milestone
        milestone = None
        if progress_percent >= 100:
            milestone = 100
        elif progress_percent >= 75:
            milestone = 75
        elif progress_percent >= 50:
            milestone = 50
        elif progress_percent >= 25:
            milestone = 25

        return {
            'total_steps': total_steps,
            'completed_steps': completed_steps,
            'progress_percent': progress_percent,
            'current_milestone': milestone
        }
