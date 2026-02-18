"""
Base Test Harness for Workflow Validation

Provides infrastructure for:
1. Pre-execution validation (parameters, inputs, structure)
2. Pilot execution on subset of data
3. QC validation of pilot results
4. Automatic parameter tuning based on QC failures
5. Retry with optimized parameters

This is the foundation that connects:
- ProgressiveTuningController (pilot execution)
- NextflowQCCalculator (quality validation)
- NextflowParameterSuggester (parameter optimization)
"""

import logging
import json
from pathlib import Path
from typing import Dict, Any, List, Optional
from enum import Enum
from dataclasses import dataclass, field

log = logging.getLogger(__name__)


class TestStatus(str, Enum):
    """Status of a test harness check."""
    PASSED = "passed"
    FAILED = "failed"
    WARNING = "warning"
    SKIPPED = "skipped"


@dataclass
class TestResult:
    """Result of a single test check."""
    check_name: str
    status: TestStatus
    message: str
    file_path: Optional[str] = None
    expected: Optional[str] = None
    actual: Optional[str] = None


@dataclass
class PilotValidationResult:
    """Result of pilot execution and QC validation."""
    pilot_completed: bool
    qc_passed: bool
    pilot_invocation_id: Optional[str] = None
    qc_metrics: Dict[str, Any] = field(default_factory=dict)
    failed_processes: List[str] = field(default_factory=list)
    parameter_suggestions: Dict[str, Any] = field(default_factory=dict)
    retry_count: int = 0
    error_message: Optional[str] = None
    # Internal fields for QC validation (prefixed with _)
    _pilot_work_dir: Optional[Path] = None
    _pilot_trace_file: Optional[Path] = None
    _completed_processes: List[Dict[str, str]] = field(default_factory=list)


@dataclass
class HarnessReport:
    """Complete test harness validation report."""
    validation_passed: bool
    pre_execution_checks: List[TestResult]
    pilot_result: Optional[PilotValidationResult] = None
    final_parameters: Optional[Dict[str, Any]] = None
    recommendations: List[str] = field(default_factory=list)


class BaseWorkflowTestHarness:
    """
    Base class for all workflow test harnesses.

    Subclasses should override:
    - test_parameters() - Domain-specific parameter validation
    - test_inputs() - Domain-specific input validation
    - test_workflow_structure() - Domain-specific workflow checks
    - get_pilot_config() - Domain-specific pilot configuration
    """

    def __init__(
        self,
        workflow_path: str,
        parameters: Dict[str, Any],
        app,
        enable_pilot: bool = True,
        max_pilot_retries: int = 2
    ):
        """
        Initialize test harness.

        Args:
            workflow_path: Path to workflow file (main.nf)
            parameters: Workflow parameters to validate
            app: Galaxy app instance
            enable_pilot: Whether to run pilot execution (default True)
            max_pilot_retries: Max retries for pilot with parameter tuning
        """
        self.workflow_path = Path(workflow_path)
        self.parameters = parameters
        self.app = app
        self.enable_pilot = enable_pilot
        self.max_pilot_retries = max_pilot_retries

        self.logger = logging.getLogger(f"{__name__}.{self.__class__.__name__}")
        self.results: List[TestResult] = []

    # ========================================================================
    # PUBLIC API - Main entry point
    # ========================================================================

    def run_full_validation(self) -> HarnessReport:
        """
        Run complete test harness validation flow.

        Flow:
        1. Pre-execution validation (parameters, inputs, structure)
        2. Pilot execution (if enabled)
        3. QC validation of pilot results
        4. Parameter tuning if QC fails
        5. Retry pilot with optimized parameters
        6. Return validation report

        Returns:
            HarnessReport with validation results and optimized parameters
        """
        self.logger.info("=" * 80)
        self.logger.info(f"Starting test harness validation: {self.__class__.__name__}")
        self.logger.info(f"Workflow: {self.workflow_path}")
        self.logger.info(f"Pilot execution: {'enabled' if self.enable_pilot else 'disabled'}")
        self.logger.info("=" * 80)

        # Phase 1: Pre-execution validation
        self.logger.info("\n[PHASE 1] Pre-execution validation...")
        self.test_parameters()
        self.test_inputs()
        self.test_workflow_structure()

        pre_execution_passed = all(
            r.status in [TestStatus.PASSED, TestStatus.SKIPPED, TestStatus.WARNING]
            for r in self.results
        )

        if not pre_execution_passed:
            self.logger.error("Pre-execution validation FAILED")
            return HarnessReport(
                validation_passed=False,
                pre_execution_checks=self.results,
                recommendations=["Fix validation errors before proceeding"]
            )

        self.logger.info(f"Pre-execution validation PASSED ({len(self.results)} checks)")

        # Phase 2-5: Pilot execution with QC validation and tuning
        pilot_result = None
        final_parameters = self.parameters.copy()

        if self.enable_pilot:
            self.logger.info("\n[PHASE 2-5] Pilot execution with QC validation...")
            pilot_result = self._run_pilot_with_tuning()

            if pilot_result.qc_passed:
                self.logger.info("✓ Pilot validation PASSED with optimized parameters")
                final_parameters = pilot_result.parameter_suggestions or self.parameters
            else:
                self.logger.warning(
                    f"⚠ Pilot validation did not pass after {pilot_result.retry_count} retries"
                )
        else:
            self.logger.info("\n[PHASE 2-5] Pilot execution SKIPPED (disabled)")

        # Generate recommendations
        recommendations = self._generate_recommendations(pilot_result)

        # Generate final report
        validation_passed = pre_execution_passed and (
            not self.enable_pilot or (pilot_result and pilot_result.qc_passed)
        )

        report = HarnessReport(
            validation_passed=validation_passed,
            pre_execution_checks=self.results,
            pilot_result=pilot_result,
            final_parameters=final_parameters,
            recommendations=recommendations
        )

        self.logger.info("\n" + "=" * 80)
        self.logger.info(f"Test harness validation: {'PASSED ✓' if validation_passed else 'FAILED ✗'}")
        self.logger.info("=" * 80)

        return report

    # ========================================================================
    # PILOT EXECUTION - Integrates with ProgressiveTuningController
    # ========================================================================

    def _run_pilot_with_tuning(self) -> PilotValidationResult:
        """
        Run pilot execution with automatic QC validation and parameter tuning.

        Flow:
        1. Run pilot with current parameters
        2. Validate QC metrics
        3. If QC fails and retries remaining:
           a. Generate parameter suggestions
           b. Retry pilot with optimized parameters
        4. Repeat until QC passes or max retries reached

        Returns:
            PilotValidationResult with QC status and optimized parameters
        """
        current_params = self.parameters.copy()
        retry_count = 0

        while retry_count <= self.max_pilot_retries:
            attempt_label = f"attempt {retry_count + 1}/{self.max_pilot_retries + 1}"
            self.logger.info(f"\nPilot execution ({attempt_label})...")

            # Run pilot execution
            pilot_result = self._execute_pilot(current_params)

            if not pilot_result.pilot_completed:
                self.logger.error(f"Pilot execution failed: {pilot_result.error_message}")
                return pilot_result

            # Validate QC metrics
            self.logger.info("Validating QC metrics from pilot run...")
            qc_validation = self._validate_pilot_qc(pilot_result)

            pilot_result.qc_passed = qc_validation["all_passed"]
            pilot_result.qc_metrics = qc_validation["metrics"]
            pilot_result.failed_processes = qc_validation["failed_processes"]
            pilot_result.retry_count = retry_count

            if qc_validation["all_passed"]:
                self.logger.info(f"✓ QC validation PASSED on {attempt_label}")
                pilot_result.parameter_suggestions = current_params
                return pilot_result

            # QC failed - try parameter tuning
            self.logger.warning(
                f"✗ QC validation FAILED: {len(qc_validation['failed_processes'])} "
                f"processes failed thresholds"
            )

            if retry_count < self.max_pilot_retries:
                # Generate parameter suggestions
                self.logger.info("Generating parameter optimization suggestions...")
                suggestions = self._tune_parameters(qc_validation)

                if suggestions:
                    self.logger.info(
                        f"Applying {len(suggestions)} parameter adjustments for retry..."
                    )
                    current_params.update(suggestions)
                    pilot_result.parameter_suggestions = suggestions
                    retry_count += 1
                else:
                    self.logger.warning("No parameter suggestions available, cannot retry")
                    return pilot_result
            else:
                self.logger.warning(
                    f"Max retries ({self.max_pilot_retries}) reached, QC still failing"
                )
                return pilot_result

        return pilot_result

    def _execute_pilot(self, parameters: Dict[str, Any]) -> PilotValidationResult:
        """
        Execute pilot run using PilotExecutionClient.

        Args:
            parameters: Workflow parameters to use

        Returns:
            PilotValidationResult with execution status
        """
        try:
            # Import pilot execution client
            from galaxy.jobs.pilot_execution_client import execute_pilot_from_harness

            # Get pilot configuration from subclass
            pilot_config = self.get_pilot_config()

            self.logger.info(
                f"Starting pilot execution: {pilot_config['min_pilot_samples']}-"
                f"{pilot_config['max_pilot_samples']} samples "
                f"({pilot_config.get('pilot_fraction', 0.1) * 100}%)"
            )

            # Execute pilot via client
            pilot_result = execute_pilot_from_harness(
                app=self.app,
                workflow_path=str(self.workflow_path),
                parameters=parameters,
                pilot_config=pilot_config,
                trans=None  # TODO: Pass transaction context if available
            )

            if not pilot_result.success:
                self.logger.error(f"Pilot execution failed: {pilot_result.error_message}")
                return PilotValidationResult(
                    pilot_completed=False,
                    qc_passed=False,
                    error_message=pilot_result.error_message
                )

            self.logger.info(
                f"Pilot completed successfully in {pilot_result.runtime_seconds:.1f}s"
            )

            # Store pilot execution details for QC validation
            return PilotValidationResult(
                pilot_completed=True,
                qc_passed=False,  # Will be filled by QC validation
                pilot_invocation_id=pilot_result.galaxy_invocation_id,
                error_message=None,
                # Store additional data for QC validation
                _pilot_work_dir=pilot_result.work_dir,
                _pilot_trace_file=pilot_result.trace_file,
                _completed_processes=pilot_result.completed_processes
            )

        except ImportError as e:
            self.logger.error(f"Pilot execution client not available: {e}")
            return PilotValidationResult(
                pilot_completed=False,
                qc_passed=False,
                error_message=f"Pilot execution client not available: {e}"
            )
        except Exception as e:
            self.logger.error(f"Pilot execution failed: {e}", exc_info=True)
            return PilotValidationResult(
                pilot_completed=False,
                qc_passed=False,
                error_message=str(e)
            )

    # ========================================================================
    # QC VALIDATION - Integrates with NextflowQCCalculator
    # ========================================================================

    def _validate_pilot_qc(self, pilot_result: PilotValidationResult) -> Dict[str, Any]:
        """
        Validate QC metrics from pilot execution.

        Uses NextflowQCCalculator to extract and validate metrics.

        Args:
            pilot_result: Result of pilot execution (includes work_dir and process list)

        Returns:
            {
                'all_passed': bool,
                'metrics': {process_name: {metric_name: QCMetric}},
                'failed_processes': [process_name, ...]
            }
        """
        try:
            from galaxy.jobs.qc_trace_monitor import (
                NextflowQCCalculator,
                QCStatus
            )

            qc_calculator = NextflowQCCalculator()

            # Get pilot execution details
            work_dir = pilot_result._pilot_work_dir
            completed_processes = pilot_result._completed_processes

            if not work_dir:
                self.logger.warning("Work directory not available, skipping QC validation")
                return {
                    "all_passed": True,
                    "metrics": {},
                    "failed_processes": []
                }

            if not completed_processes:
                self.logger.warning("No completed processes found, skipping QC validation")
                return {
                    "all_passed": True,
                    "metrics": {},
                    "failed_processes": []
                }

            self.logger.info(f"Validating QC for {len(completed_processes)} processes")

            all_metrics = {}
            failed_processes = []

            # Validate each completed process
            for process_info in completed_processes:
                process_name = process_info.get("process_name")
                process_hash = process_info.get("hash")
                process_status = process_info.get("status")

                # Only validate successfully completed processes
                if process_status != "COMPLETED":
                    self.logger.debug(
                        f"Skipping QC for {process_name} (status: {process_status})"
                    )
                    continue

                # Calculate QC metrics
                try:
                    metrics = qc_calculator.calculate_metrics(
                        process_name=process_name,
                        process_hash=process_hash,
                        work_dir=work_dir
                    )

                    if not metrics:
                        # No QC calculator for this process type
                        self.logger.debug(f"No QC calculator for {process_name}")
                        continue

                    all_metrics[process_name] = metrics

                    # Check for failures
                    failed_metrics = [
                        m for m in metrics.values()
                        if m.status == QCStatus.FAIL
                    ]

                    if failed_metrics:
                        failed_processes.append(process_name)
                        self.logger.warning(
                            f"  ✗ {process_name}: {len(failed_metrics)}/{len(metrics)} "
                            f"metrics failed"
                        )
                    else:
                        self.logger.info(
                            f"  ✓ {process_name}: All {len(metrics)} metrics passed"
                        )

                except Exception as e:
                    self.logger.error(
                        f"Failed to calculate QC for {process_name}: {e}",
                        exc_info=True
                    )

            # Summary
            total_processes = len(completed_processes)
            validated_processes = len(all_metrics)
            failed_count = len(failed_processes)

            self.logger.info(
                f"QC validation complete: {validated_processes}/{total_processes} "
                f"processes validated, {failed_count} failed"
            )

            return {
                "all_passed": len(failed_processes) == 0,
                "metrics": all_metrics,
                "failed_processes": failed_processes
            }

        except ImportError as e:
            self.logger.error(f"QC calculator not available: {e}")
            return {
                "all_passed": True,  # Skip QC if not available
                "metrics": {},
                "failed_processes": []
            }

    # ========================================================================
    # PARAMETER TUNING - Integrates with NextflowParameterSuggester
    # ========================================================================

    def _tune_parameters(self, qc_validation: Dict[str, Any]) -> Dict[str, Any]:
        """
        Generate parameter optimization suggestions based on QC failures.

        Uses NextflowParameterSuggester to generate adjustments.

        Args:
            qc_validation: QC validation results with failed processes

        Returns:
            Dictionary of parameter adjustments
        """
        try:
            from galaxy.jobs.qc_trace_monitor import NextflowParameterSuggester

            suggester = NextflowParameterSuggester()
            all_suggestions = {}

            for process_name in qc_validation["failed_processes"]:
                metrics = qc_validation["metrics"].get(process_name, {})

                if metrics:
                    suggestions = suggester.generate_suggestions(process_name, metrics)

                    if suggestions.get("suggested_parameters"):
                        self.logger.info(
                            f"  {process_name}: {suggestions['explanation']} "
                            f"(confidence: {suggestions['confidence']:.2f})"
                        )
                        all_suggestions.update(suggestions["suggested_parameters"])

            return all_suggestions

        except ImportError as e:
            self.logger.error(f"Parameter suggester not available: {e}")
            return {}

    # ========================================================================
    # HELPER METHODS
    # ========================================================================

    def _generate_recommendations(
        self,
        pilot_result: Optional[PilotValidationResult]
    ) -> List[str]:
        """Generate user-facing recommendations based on validation results."""
        recommendations = []

        # Check pre-execution warnings
        warnings = [r for r in self.results if r.status == TestStatus.WARNING]
        if warnings:
            recommendations.append(
                f"Review {len(warnings)} warning(s) from pre-execution validation"
            )

        # Check pilot results
        if pilot_result:
            if pilot_result.qc_passed:
                if pilot_result.parameter_suggestions:
                    recommendations.append(
                        "Pilot validation passed with optimized parameters - "
                        "recommend using these for full run"
                    )
                else:
                    recommendations.append(
                        "Pilot validation passed with default parameters - "
                        "proceed with full run"
                    )
            else:
                recommendations.append(
                    "Pilot validation did not pass QC thresholds - "
                    "review failed processes and consider manual parameter adjustment"
                )
                if pilot_result.failed_processes:
                    recommendations.append(
                        f"Failed processes: {', '.join(pilot_result.failed_processes)}"
                    )

        return recommendations

    def add_result(
        self,
        check_name: str,
        status: TestStatus,
        message: str,
        file_path: Optional[str] = None,
        expected: Optional[str] = None,
        actual: Optional[str] = None
    ):
        """
        Add a test result.

        Args:
            check_name: Unique identifier for this check
            status: PASSED, FAILED, WARNING, or SKIPPED
            message: Human-readable description
            file_path: Optional file path being checked
            expected: Optional expected value
            actual: Optional actual value
        """
        result = TestResult(
            check_name=check_name,
            status=status,
            message=message,
            file_path=file_path,
            expected=expected,
            actual=actual
        )
        self.results.append(result)

        # Log based on status
        if status == TestStatus.PASSED:
            self.logger.debug(f"  ✓ {message}")
        elif status == TestStatus.FAILED:
            self.logger.error(f"  ✗ {message}")
        elif status == TestStatus.WARNING:
            self.logger.warning(f"  ⚠ {message}")
        else:  # SKIPPED
            self.logger.info(f"  - {message}")

    # ========================================================================
    # METHODS TO OVERRIDE IN SUBCLASSES
    # ========================================================================

    def test_parameters(self):
        """
        Override: Validate domain-specific parameters.

        Example for Cryo-EM:
            if "voltage" in self.parameters:
                voltage = self.parameters["voltage"]
                if voltage in [200, 300]:
                    self.add_result("voltage_valid", TestStatus.PASSED, ...)
        """
        self.logger.info("No parameter validation implemented (override test_parameters)")

    def test_inputs(self):
        """
        Override: Validate input files.

        Example:
            if "movies_dir" in self.parameters:
                if Path(self.parameters["movies_dir"]).exists():
                    self.add_result("movies_exist", TestStatus.PASSED, ...)
        """
        self.logger.info("No input validation implemented (override test_inputs)")

    def test_workflow_structure(self):
        """
        Override: Validate workflow structure.

        Example:
            content = self.workflow_path.read_text()
            if "MOTION_CORRECTION" in content:
                self.add_result("has_motion", TestStatus.PASSED, ...)
        """
        if self.workflow_path.exists():
            self.add_result(
                "workflow_exists",
                TestStatus.PASSED,
                f"Workflow file exists: {self.workflow_path}"
            )
        else:
            self.add_result(
                "workflow_exists",
                TestStatus.FAILED,
                f"Workflow file not found: {self.workflow_path}",
                expected="File exists",
                actual="File not found"
            )

    def get_pilot_config(self) -> Dict[str, Any]:
        """
        Override: Return pilot configuration for this workflow type.

        Returns:
            {
                'pilot_fraction': 0.1,        # 10% of data
                'min_pilot_samples': 3,
                'max_pilot_samples': 50,
                'sampling_strategy': 'stratified'  # or 'random', 'first_n'
            }
        """
        return {
            "pilot_fraction": 0.1,
            "min_pilot_samples": 3,
            "max_pilot_samples": 50,
            "sampling_strategy": "stratified"
        }

    def get_expected_processes(self) -> List[str]:
        """
        Override: Return list of expected process names for QC validation.

        Example for Cryo-EM SPA:
            return [
                "PATCH_MOTION_CORRECTION",
                "PATCH_CTF_ESTIMATION",
                "BLOB_PARTICLE_PICKING",
                ...
            ]
        """
        return []

    def _is_mock_mode(self) -> bool:
        """Check if running in mock mode (no real execution)."""
        return self.parameters.get("mock_mode", True)

    def _is_remote_file(self, file_path: str) -> bool:
        """Check if file path is remote (S3, HTTP, etc.)."""
        return any(
            file_path.startswith(prefix)
            for prefix in ["s3://", "http://", "https://", "ftp://"]
        )

    def _file_exists(self, file_path: str) -> bool:
        """Check if file exists (handles remote files and mock mode)."""
        if self._is_remote_file(file_path) or self._is_mock_mode():
            return True
        return Path(file_path).exists()
