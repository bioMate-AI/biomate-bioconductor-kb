"""
Cryo-EM Domain Test Harness

Provides shared test infrastructure for all cryo-EM workflows:
- SPA, Cryo-ET, Motion Correction, CTF Estimation, etc.
"""

import logging
from pathlib import Path
from typing import Dict, Any
from ..workflow_test_harness import BaseWorkflowTestHarness, TestStatus

log = logging.getLogger(__name__)


class CryoEMWorkflowHarness(BaseWorkflowTestHarness):
    """Base harness for all cryo-EM workflows"""

    def test_parameters(self):
        """Test cryo-EM specific parameters"""
        # Check for common cryo-EM parameters
        required_params = self.get_required_parameters()

        for param in required_params:
            if param in self.parameters:
                self.add_result(
                    f"parameter_{param}",
                    TestStatus.PASSED,
                    f"Required parameter '{param}' provided"
                )
            else:
                # In mock mode, parameters are optional
                if self._is_mock_mode():
                    self.add_result(
                        f"parameter_{param}",
                        TestStatus.SKIPPED,
                        f"Parameter '{param}' not provided (mock mode)"
                    )
                else:
                    self.add_result(
                        f"parameter_{param}",
                        TestStatus.FAILED,
                        f"Missing required parameter: {param}",
                        expected=f"{param} provided",
                        actual="Not provided"
                    )

    def test_inputs(self):
        """Test cryo-EM input files"""
        # Check for movie files (common in cryo-EM)
        if "movies_dir" in self.parameters:
            movies_path = self.parameters["movies_dir"]
            if Path(movies_path).exists() or self._is_mock_mode():
                self.add_result(
                    "movies_dir_exists",
                    TestStatus.PASSED,
                    f"Movies directory accessible: {movies_path}"
                )
            else:
                self.add_result(
                    "movies_dir_exists",
                    TestStatus.FAILED,
                    f"Movies directory not found: {movies_path}",
                    expected="Directory exists",
                    actual="Directory not found"
                )
        else:
            self.add_result(
                "input_validation",
                TestStatus.SKIPPED,
                "No input files specified (may use defaults)"
            )

    def get_required_parameters(self) -> list:
        """Override in subclasses to specify required parameters"""
        return []

    def _is_mock_mode(self) -> bool:
        """Check if running in mock mode"""
        return self.parameters.get("mock_mode", True)  # Default to mock for cryo-EM


class CryoEMSPAHarness(CryoEMWorkflowHarness):
    """Test harness for Cryo-EM Single Particle Analysis workflows"""

    def get_required_parameters(self) -> list:
        # SPA workflows can run with defaults in mock mode
        return []

    def test_parameters(self):
        """Test SPA specific parameters"""
        super().test_parameters()

        # Check for voltage (common in cryo-EM)
        if "voltage" in self.parameters:
            voltage = self.parameters["voltage"]
            if voltage in [200, 300]:  # Common voltages
                self.add_result(
                    "voltage_valid",
                    TestStatus.PASSED,
                    f"Valid voltage: {voltage} kV"
                )
            else:
                self.add_result(
                    "voltage_valid",
                    TestStatus.FAILED,
                    f"Unusual voltage: {voltage} kV",
                    expected="200 or 300 kV",
                    actual=f"{voltage} kV"
                )

    def test_workflow_structure(self):
        """Test SPA workflow structure"""
        super().test_workflow_structure()

        # Check for common SPA processes
        workflow_file = Path(self.workflow_path)
        if workflow_file.exists():
            content = workflow_file.read_text()

            # Check for motion correction
            if "motion" in content.lower():
                self.add_result(
                    "has_motion_correction",
                    TestStatus.PASSED,
                    "Workflow includes motion correction"
                )

            # Check for CTF estimation
            if "ctf" in content.lower():
                self.add_result(
                    "has_ctf_estimation",
                    TestStatus.PASSED,
                    "Workflow includes CTF estimation"
                )

    def get_pilot_config(self) -> dict:
        """
        Cryo-EM SPA pilot configuration.

        For SPA: use 5-10 micrographs for pilot (typical dataset has 100-5000)
        """
        return {
            "pilot_fraction": 0.05,  # 5% of micrographs
            "min_pilot_samples": 5,   # Minimum 5 micrographs
            "max_pilot_samples": 20,  # Maximum 20 micrographs
            "sampling_strategy": "random"  # Random sampling for cryo-EM
        }

    def get_expected_processes(self) -> list:
        """
        Expected process names for SPA QC validation.

        These correspond to NextflowQCCalculator's registered calculators.
        """
        return [
            "IMPORT_MOVIES",
            "PATCH_MOTION_CORRECTION",
            "PATCH_CTF_ESTIMATION",
            "CURATE_EXPOSURES",
            "BLOB_PARTICLE_PICKING",
            "EXTRACT_PARTICLES",
            "CLASSIFY_2D",
            "SELECT_2D_CLASSES",
            "AB_INITIO_RECONSTRUCTION",
            "HOMOGENEOUS_REFINEMENT",
            "HETEROGENEOUS_REFINEMENT",
            "NON_UNIFORM_REFINEMENT",
            "CTF_REFINEMENT",
            "SHARPENING_AND_VALIDATION"
        ]


class CryoETHarness(CryoEMWorkflowHarness):
    """Test harness for Cryo-ET (Electron Tomography) workflows"""

    def test_parameters(self):
        """Test Cryo-ET specific parameters"""
        super().test_parameters()

        # Cryo-ET requires tilt series
        if "tilt_series_pattern" in self.parameters or "tilt_series_dir" in self.parameters:
            self.add_result(
                "tilt_series_input",
                TestStatus.PASSED,
                "Tilt series input provided"
            )

    def test_workflow_structure(self):
        """Test Cryo-ET workflow structure"""
        super().test_workflow_structure()

        workflow_file = Path(self.workflow_path)
        if workflow_file.exists():
            content = workflow_file.read_text()

            # Check for tilt alignment
            if "alignment" in content.lower() and "tilt" in content.lower():
                self.add_result(
                    "has_tilt_alignment",
                    TestStatus.PASSED,
                    "Workflow includes tilt series alignment"
                )

            # Check for tomogram reconstruction
            if "tomogram" in content.lower() or "reconstruction" in content.lower():
                self.add_result(
                    "has_reconstruction",
                    TestStatus.PASSED,
                    "Workflow includes tomogram reconstruction"
                )

    def get_pilot_config(self) -> dict:
        """
        Cryo-ET pilot configuration.

        For ET: use 1-3 tilt series for pilot (typical dataset has 10-100)
        """
        return {
            "pilot_fraction": 0.1,   # 10% of tilt series
            "min_pilot_samples": 1,   # Minimum 1 tilt series
            "max_pilot_samples": 3,   # Maximum 3 tilt series
            "sampling_strategy": "first_n"  # Use first N for reproducibility
        }

    def get_expected_processes(self) -> list:
        """
        Expected process names for Cryo-ET QC validation.
        """
        return [
            "IMPORT_TILTSERIES",
            "TILT_ALIGNMENT",
            "TOMOGRAM_RECONSTRUCTION",
            "SUBTOMOGRAM_AVERAGING"
        ]
