"""
Pilot Execution Client for Test Harness

Provides high-level API for test harness to execute pilot runs and retrieve results.
Handles communication with ProgressiveTuningController and pilot API endpoints.
"""

import logging
import time
from pathlib import Path
from typing import Dict, Any, Optional, List
from dataclasses import dataclass

log = logging.getLogger(__name__)


@dataclass
class PilotExecutionConfig:
    """Configuration for pilot execution."""
    pilot_fraction: float = 0.1
    min_pilot_samples: int = 3
    max_pilot_samples: int = 50
    sampling_strategy: str = "stratified"  # or "random", "first_n"
    timeout_seconds: int = 3600  # 1 hour max for pilot


@dataclass
class PilotExecutionResult:
    """Result of pilot execution."""
    success: bool
    pilot_id: Optional[str] = None
    galaxy_invocation_id: Optional[str] = None
    galaxy_history_id: Optional[str] = None
    work_dir: Optional[Path] = None
    trace_file: Optional[Path] = None
    completed_processes: List[Dict[str, str]] = None  # List of {name, hash, status}
    runtime_seconds: Optional[float] = None
    error_message: Optional[str] = None

    def __post_init__(self):
        if self.completed_processes is None:
            self.completed_processes = []


class PilotExecutionClient:
    """
    Client for executing pilot runs from test harness.

    Handles:
    1. Starting pilot run via API
    2. Polling for completion
    3. Extracting work directory and trace file
    4. Parsing completed processes
    """

    def __init__(self, app):
        """
        Initialize pilot execution client.

        Args:
            app: Galaxy app instance
        """
        self.app = app
        self.logger = logging.getLogger(f"{__name__}.PilotExecutionClient")

    def execute_pilot(
        self,
        workflow_path: str,
        parameters: Dict[str, Any],
        config: PilotExecutionConfig,
        trans=None
    ) -> PilotExecutionResult:
        """
        Execute a pilot run and wait for completion.

        Args:
            workflow_path: Path to workflow file (main.nf)
            parameters: Workflow parameters
            config: Pilot execution configuration
            trans: Transaction context (optional, for API calls)

        Returns:
            PilotExecutionResult with execution details
        """
        self.logger.info(f"Starting pilot execution for workflow: {workflow_path}")
        self.logger.info(f"Pilot config: {config.pilot_fraction * 100}% of data")

        try:
            # Step 1: Start pilot run
            pilot_start_result = self._start_pilot_run(
                workflow_path, parameters, config, trans
            )

            if not pilot_start_result["success"]:
                return PilotExecutionResult(
                    success=False,
                    error_message=pilot_start_result["error"]
                )

            pilot_id = pilot_start_result["pilot_id"]
            galaxy_invocation_id = pilot_start_result["galaxy_invocation_id"]
            galaxy_history_id = pilot_start_result["galaxy_history_id"]

            self.logger.info(
                f"Pilot started: pilot_id={pilot_id}, "
                f"invocation_id={galaxy_invocation_id}"
            )

            # Step 2: Wait for pilot completion
            completion_result = self._wait_for_completion(
                pilot_id, galaxy_invocation_id, config.timeout_seconds, trans
            )

            if not completion_result["success"]:
                return PilotExecutionResult(
                    success=False,
                    pilot_id=pilot_id,
                    galaxy_invocation_id=galaxy_invocation_id,
                    galaxy_history_id=galaxy_history_id,
                    error_message=completion_result["error"]
                )

            self.logger.info(
                f"Pilot completed in {completion_result['runtime_seconds']:.1f}s"
            )

            # Step 3: Extract work directory and trace file
            work_dir_result = self._get_work_directory(galaxy_invocation_id, trans)

            if not work_dir_result["success"]:
                self.logger.warning(
                    f"Could not determine work directory: {work_dir_result['error']}"
                )
                work_dir = None
                trace_file = None
            else:
                work_dir = Path(work_dir_result["work_dir"])
                trace_file = work_dir / "trace.txt"

            # Step 4: Parse completed processes from trace file
            completed_processes = []
            if trace_file and trace_file.exists():
                completed_processes = self._parse_trace_file(trace_file)
                self.logger.info(f"Parsed {len(completed_processes)} completed processes")
            else:
                self.logger.warning("Trace file not available, cannot extract process info")

            return PilotExecutionResult(
                success=True,
                pilot_id=pilot_id,
                galaxy_invocation_id=galaxy_invocation_id,
                galaxy_history_id=galaxy_history_id,
                work_dir=work_dir,
                trace_file=trace_file,
                completed_processes=completed_processes,
                runtime_seconds=completion_result["runtime_seconds"]
            )

        except Exception as e:
            self.logger.error(f"Pilot execution failed: {e}", exc_info=True)
            return PilotExecutionResult(
                success=False,
                error_message=str(e)
            )

    def _start_pilot_run(
        self,
        workflow_path: str,
        parameters: Dict[str, Any],
        config: PilotExecutionConfig,
        trans
    ) -> Dict[str, Any]:
        """
        Start pilot run via internal Galaxy API.

        Returns:
            {
                'success': bool,
                'pilot_id': str,
                'galaxy_invocation_id': str,
                'galaxy_history_id': str,
                'error': str (if failed)
            }
        """
        try:
            # Check for transaction context
            if not trans:
                self.logger.error("No transaction context provided - cannot start pilot")
                return {
                    "success": False,
                    "error": "Transaction context required for pilot execution"
                }

            # Import the internal pilot API function and models
            from galaxy.webapps.galaxy.api.ai_assistant import start_pilot_run
            from galaxy.webapps.galaxy.api.ai_assistant import StartPilotRequest, TuningConfigModel

            # For Nextflow workflows, we need a workflow_id or workflow_definition
            # The workflow_path parameter will be used to execute Nextflow via NextflowWorkflowRunner
            # For pilot mode, we use the ProgressiveTuningController which internally
            # handles Nextflow execution with sampled data

            # Estimate total sample count from parameters
            total_samples = self._estimate_sample_count(parameters)

            # Create pilot request
            request = StartPilotRequest(
                workflow_id=None,  # For Nextflow, we don't have a Galaxy workflow ID
                workflow_definition=None,  # Will be handled by NextflowWorkflowRunner
                total_samples=total_samples,
                config=TuningConfigModel(
                    pilot_fraction=config.pilot_fraction,
                    min_pilot_samples=config.min_pilot_samples,
                    max_pilot_samples=config.max_pilot_samples,
                    sampling_strategy=config.sampling_strategy
                ),
                sample_ids=None,  # Will be sampled by ProgressiveTuningController
                inputs=None,  # For Nextflow, inputs are passed as parameters
                history_id=None  # Will create a new sandbox history
            )

            # Store workflow_path in parameters so it can be retrieved later
            if parameters is None:
                parameters = {}
            parameters['_workflow_path'] = workflow_path

            # Call internal API function directly (no HTTP overhead)
            self.logger.info(f"Starting pilot run for {total_samples} total samples")
            result = start_pilot_run(request, trans)

            self.logger.info(
                f"Pilot started successfully: pilot_id={result['pilot_id']}, "
                f"invocation={result['galaxy_invocation_id']}"
            )

            return {
                "success": True,
                "pilot_id": result["pilot_id"],
                "galaxy_invocation_id": result["galaxy_invocation_id"],
                "galaxy_history_id": result["galaxy_history_id"]
            }

        except Exception as e:
            self.logger.error(f"Failed to start pilot: {e}", exc_info=True)
            return {
                "success": False,
                "error": f"Failed to start pilot: {str(e)}"
            }

    def _estimate_sample_count(self, parameters: Dict[str, Any]) -> int:
        """
        Estimate number of samples from workflow parameters.

        Looks for common parameter names that indicate sample count.
        """
        # Check for explicit sample count
        if "num_samples" in parameters:
            return int(parameters["num_samples"])

        # Check for input directories/files
        if "movies_dir" in parameters:
            # Cryo-EM: estimate from directory (assume 100 if unknown)
            return 100
        elif "fastq_dir" in parameters:
            # Genomics: estimate from directory (assume 20 if unknown)
            return 20
        elif "tilt_series_dir" in parameters:
            # Cryo-ET: estimate from directory (assume 10 if unknown)
            return 10

        # Default estimate
        return 50

    def _wait_for_completion(
        self,
        pilot_id: str,
        galaxy_invocation_id: str,
        timeout_seconds: int,
        trans
    ) -> Dict[str, Any]:
        """
        Wait for pilot run to complete by polling Galaxy invocation status.

        Returns:
            {
                'success': bool,
                'runtime_seconds': float,
                'error': str (if failed)
            }
        """
        start_time = time.time()
        poll_interval = 5  # Poll every 5 seconds

        self.logger.info(f"Waiting for pilot completion (timeout: {timeout_seconds}s)...")

        if not trans:
            self.logger.error("No transaction context - cannot poll invocation status")
            return {
                "success": False,
                "error": "Transaction context required for polling"
            }

        try:
            from galaxy.webapps.galaxy.services.invocations import InvocationsService

            invocations_service = trans.app.invocations_service

            while True:
                elapsed = time.time() - start_time

                # Check timeout
                if elapsed > timeout_seconds:
                    return {
                        "success": False,
                        "error": f"Pilot timed out after {timeout_seconds}s"
                    }

                # Get invocation status
                try:
                    invocation = invocations_service.get_invocation(trans, galaxy_invocation_id)
                    state = invocation.state

                    self.logger.debug(
                        f"Invocation {galaxy_invocation_id} state: {state} "
                        f"({elapsed:.1f}s elapsed)"
                    )

                    # Check if completed
                    if state == "ok":
                        self.logger.info(f"Pilot completed successfully in {elapsed:.1f}s")
                        return {
                            "success": True,
                            "runtime_seconds": elapsed
                        }
                    elif state in ("failed", "error"):
                        error_msg = f"Pilot invocation failed with state: {state}"
                        self.logger.error(error_msg)
                        return {
                            "success": False,
                            "error": error_msg
                        }
                    elif state in ("cancelled", "deleted"):
                        error_msg = f"Pilot invocation was {state}"
                        self.logger.error(error_msg)
                        return {
                            "success": False,
                            "error": error_msg
                        }
                    # States: scheduled, new, ready, running - continue polling
                    else:
                        self.logger.debug(f"Pilot still {state}... waiting")

                except Exception as e:
                    self.logger.warning(f"Error checking invocation status: {e}")
                    # Continue polling - temporary error might resolve

                # Wait before next poll
                time.sleep(poll_interval)

        except ImportError as e:
            self.logger.error(f"InvocationsService not available: {e}")
            return {
                "success": False,
                "error": f"Cannot poll invocation status: {e}"
            }
        except Exception as e:
            self.logger.error(f"Error during completion polling: {e}", exc_info=True)
            return {
                "success": False,
                "error": f"Polling failed: {str(e)}"
            }

    def _get_work_directory(
        self,
        galaxy_invocation_id: str,
        trans=None
    ) -> Dict[str, Any]:
        """
        Get work directory for completed invocation.

        For Nextflow workflows, this extracts the working directory
        that contains the work/ subdirectory and trace.txt file.

        Returns:
            {
                'success': bool,
                'work_dir': str,
                'error': str (if failed)
            }
        """
        try:
            if not trans:
                self.logger.error("No transaction context - cannot get work directory")
                return {
                    "success": False,
                    "error": "Transaction context required"
                }

            from galaxy.webapps.galaxy.services.invocations import InvocationsService

            # Get invocation
            invocations_service = trans.app.invocations_service
            invocation = invocations_service.get_invocation(trans, galaxy_invocation_id)

            # Get job IDs from invocation steps
            job_ids = []
            if invocation.steps:
                for step in invocation.steps:
                    if hasattr(step, 'job_id') and step.job_id:
                        job_ids.append(step.job_id)
                    elif hasattr(step, 'jobs') and step.jobs:
                        job_ids.extend([j.id for j in step.jobs])

            if not job_ids:
                self.logger.warning(f"No jobs found in invocation {galaxy_invocation_id}")
                return {
                    "success": False,
                    "error": "No jobs found in invocation"
                }

            # Get first job's working directory (for Nextflow, all jobs share same work_dir)
            from galaxy.model import Job
            from galaxy.managers.jobs import JobManager

            job_manager = trans.app.job_manager
            job = trans.sa_session.query(Job).filter(Job.id == job_ids[0]).first()

            if not job:
                return {
                    "success": False,
                    "error": f"Job {job_ids[0]} not found"
                }

            # Get working directory
            # For Nextflow jobs, the working directory is set by NextflowWorkflowRunner
            work_dir = job.working_directory

            if not work_dir:
                self.logger.warning(f"Job {job.id} has no working directory set")
                # Fallback: try to construct from job output paths
                if job.output_datasets:
                    for dataset_assoc in job.output_datasets:
                        dataset = dataset_assoc.dataset
                        if dataset and dataset.file_name:
                            # Extract directory from dataset file path
                            dataset_dir = Path(dataset.file_name).parent
                            # For Nextflow, work_dir is usually 2-3 levels up
                            potential_work_dir = dataset_dir.parent
                            if (potential_work_dir / "trace.txt").exists():
                                work_dir = str(potential_work_dir)
                                break

            if not work_dir:
                return {
                    "success": False,
                    "error": "Could not determine working directory"
                }

            self.logger.info(f"Extracted work directory: {work_dir}")

            # Verify work directory exists and contains expected Nextflow files
            work_dir_path = Path(work_dir)
            if not work_dir_path.exists():
                self.logger.warning(f"Work directory does not exist: {work_dir}")
                return {
                    "success": False,
                    "error": f"Work directory does not exist: {work_dir}"
                }

            # Check for trace.txt (Nextflow execution report)
            trace_file = work_dir_path / "trace.txt"
            if not trace_file.exists():
                self.logger.warning(f"trace.txt not found in {work_dir}")
                # Still return work_dir, but log warning
                # trace.txt might be in a subdirectory

            return {
                "success": True,
                "work_dir": str(work_dir)
            }

        except ImportError as e:
            self.logger.error(f"Required services not available: {e}")
            return {
                "success": False,
                "error": f"Cannot get work directory: {e}"
            }
        except Exception as e:
            self.logger.error(f"Error getting work directory: {e}", exc_info=True)
            return {
                "success": False,
                "error": f"Failed to get work directory: {str(e)}"
            }

    def _parse_trace_file(self, trace_file: Path) -> List[Dict[str, str]]:
        """
        Parse trace.txt to extract completed processes.

        Returns list of:
        [
            {
                'task_id': '1',
                'process_name': 'PATCH_MOTION_CORRECTION',
                'hash': 'd8/95e1b3...',
                'status': 'COMPLETED'
            },
            ...
        ]
        """
        try:
            if not trace_file.exists():
                self.logger.warning(f"Trace file not found: {trace_file}")
                return []

            processes = []
            with open(trace_file) as f:
                # Skip header line
                header = f.readline().strip().split('\t')

                # Find column indices
                try:
                    task_id_idx = header.index('task_id')
                    name_idx = header.index('name')
                    hash_idx = header.index('hash')
                    status_idx = header.index('status')
                except ValueError as e:
                    self.logger.error(f"Trace file missing expected columns: {e}")
                    return []

                # Parse each line
                for line in f:
                    if not line.strip():
                        continue

                    fields = line.strip().split('\t')

                    if len(fields) <= max(task_id_idx, name_idx, hash_idx, status_idx):
                        continue

                    processes.append({
                        'task_id': fields[task_id_idx],
                        'process_name': fields[name_idx],
                        'hash': fields[hash_idx],
                        'status': fields[status_idx]
                    })

            self.logger.info(f"Parsed {len(processes)} processes from trace file")
            return processes

        except Exception as e:
            self.logger.error(f"Failed to parse trace file: {e}", exc_info=True)
            return []


# Convenience function for test harness
def execute_pilot_from_harness(
    app,
    workflow_path: str,
    parameters: Dict[str, Any],
    pilot_config: Dict[str, Any],
    trans=None
) -> PilotExecutionResult:
    """
    Execute pilot run from test harness.

    Args:
        app: Galaxy app instance
        workflow_path: Path to workflow file
        parameters: Workflow parameters
        pilot_config: Pilot configuration dict
        trans: Transaction context (optional)

    Returns:
        PilotExecutionResult
    """
    config = PilotExecutionConfig(
        pilot_fraction=pilot_config.get("pilot_fraction", 0.1),
        min_pilot_samples=pilot_config.get("min_pilot_samples", 3),
        max_pilot_samples=pilot_config.get("max_pilot_samples", 50),
        sampling_strategy=pilot_config.get("sampling_strategy", "stratified"),
        timeout_seconds=pilot_config.get("timeout_seconds", 3600)
    )

    client = PilotExecutionClient(app)
    return client.execute_pilot(workflow_path, parameters, config, trans)
