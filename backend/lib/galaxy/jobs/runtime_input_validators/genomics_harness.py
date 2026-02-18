"""
Genomics Domain Test Harness

Provides shared test infrastructure for all genomics workflows:
- RNA-Seq, ChIP-Seq, ATAC-Seq, DNA-Seq, etc.
"""

import logging
from pathlib import Path
from typing import Dict, Any
from ..workflow_test_harness import BaseWorkflowTestHarness, TestStatus

log = logging.getLogger(__name__)


class GenomicsWorkflowHarness(BaseWorkflowTestHarness):
    """Base harness for all genomics workflows"""

    def test_parameters(self):
        """Test genomics-specific parameters"""
        # Check for common genomics parameters
        required_params = self.get_required_parameters()

        for param in required_params:
            if param in self.parameters:
                self.add_result(
                    f"parameter_{param}",
                    TestStatus.PASSED,
                    f"Required parameter '{param}' provided"
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
        """Test genomics input files"""
        # Check for FASTQ files (common in genomics)
        if "input_fastq" in self.parameters:
            fastq_path = self.parameters["input_fastq"]
            if Path(fastq_path).exists() or self._is_mock_mode():
                self.add_result(
                    "input_fastq_exists",
                    TestStatus.PASSED,
                    f"FASTQ input file accessible: {fastq_path}"
                )
            else:
                self.add_result(
                    "input_fastq_exists",
                    TestStatus.FAILED,
                    f"FASTQ file not found: {fastq_path}",
                    expected="File exists",
                    actual="File not found"
                )
        else:
            self.add_result(
                "input_validation",
                TestStatus.SKIPPED,
                "No input files specified in parameters"
            )

    def get_required_parameters(self) -> list:
        """Override in subclasses to specify required parameters"""
        return []

    def _is_mock_mode(self) -> bool:
        """Check if running in mock mode"""
        return self.parameters.get("mock_mode", False)


class RNASeqWorkflowHarness(GenomicsWorkflowHarness):
    """Test harness for RNA-Seq workflows"""

    def get_required_parameters(self) -> list:
        return ["genome_reference"]  # RNA-Seq typically needs reference genome

    def test_parameters(self):
        """Test RNA-Seq specific parameters"""
        super().test_parameters()

        # Check for RNA-Seq specific params
        if "star_index" in self.parameters or "genome_reference" in self.parameters:
            self.add_result(
                "alignment_reference",
                TestStatus.PASSED,
                "Alignment reference provided (STAR index or genome)"
            )

    def test_workflow_structure(self):
        """Test RNA-Seq workflow structure"""
        super().test_workflow_structure()

        # Check for common RNA-Seq tools
        workflow_file = Path(self.workflow_path)
        if workflow_file.exists():
            content = workflow_file.read_text()

            # Check for FASTQC (quality control)
            if "FASTQC" in content or "fastqc" in content.lower():
                self.add_result(
                    "has_fastqc",
                    TestStatus.PASSED,
                    "Workflow includes FASTQC for quality control"
                )
            else:
                self.add_result(
                    "has_fastqc",
                    TestStatus.SKIPPED,
                    "FASTQC not found in workflow (optional)"
                )

    def get_pilot_config(self) -> dict:
        """RNA-Seq pilot configuration: 2-5 samples"""
        return {
            "pilot_fraction": 0.1,
            "min_pilot_samples": 2,
            "max_pilot_samples": 5,
            "sampling_strategy": "stratified"  # Stratify by condition if metadata available
        }

    def get_expected_processes(self) -> list:
        """Expected processes for RNA-Seq QC validation"""
        return [
            "FASTQC",
            "STAR_ALIGN",
            "FEATURECOUNTS",
            "SALMON_QUANT"
        ]


class ChIPSeqWorkflowHarness(GenomicsWorkflowHarness):
    """Test harness for ChIP-Seq workflows"""

    def get_required_parameters(self) -> list:
        return ["genome_reference", "control_sample"]

    def test_parameters(self):
        """Test ChIP-Seq specific parameters"""
        super().test_parameters()

        # ChIP-Seq requires control sample
        if "control_sample" in self.parameters:
            self.add_result(
                "control_sample",
                TestStatus.PASSED,
                "Control sample provided for peak calling"
            )
        else:
            self.add_result(
                "control_sample",
                TestStatus.FAILED,
                "ChIP-Seq requires control sample",
                expected="Control sample path",
                actual="Not provided"
            )

    def get_pilot_config(self) -> dict:
        """ChIP-Seq pilot configuration: 1-3 sample pairs"""
        return {
            "pilot_fraction": 0.15,
            "min_pilot_samples": 1,  # At least 1 ChIP + control pair
            "max_pilot_samples": 3,   # Up to 3 pairs
            "sampling_strategy": "stratified"
        }

    def get_expected_processes(self) -> list:
        """Expected processes for ChIP-Seq QC validation"""
        return [
            "FASTQC",
            "BWA_MEM",
            "MACS2_CALLPEAK",
            "HOMER_FINDPEAKS"
        ]
