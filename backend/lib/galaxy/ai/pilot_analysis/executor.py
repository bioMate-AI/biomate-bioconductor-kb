"""
Pilot Analysis Executor - Runs pilot analyzers on user data.

This module executes the quick data characterization analyzers defined in domain plugins,
extracting context information needed for intelligent parameter inference.
"""

import subprocess
import logging
import json
import time
import tempfile
from pathlib import Path
from typing import Dict, Any, Optional, List, Union
from dataclasses import dataclass, field
from datetime import datetime

from .base import AnalyzerSpec
from . import parsers

logger = logging.getLogger(__name__)


@dataclass
class AnalysisResult:
    """Result from running a pilot analyzer."""

    analyzer_name: str
    status: str  # "success", "failed", "timeout", "fallback"
    extracted_data: Dict[str, Any]
    execution_time_seconds: float
    error_message: Optional[str] = None
    used_fallback: bool = False
    metadata: Dict[str, Any] = field(default_factory=dict)

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary format."""
        return {
            "analyzer_name": self.analyzer_name,
            "status": self.status,
            "extracted_data": self.extracted_data,
            "execution_time_seconds": self.execution_time_seconds,
            "error_message": self.error_message,
            "used_fallback": self.used_fallback,
            "metadata": self.metadata,
        }


class PilotAnalysisExecutor:
    """
    Executes pilot analyzers on user data.

    Handles command execution, output parsing, error handling, and fallback values.
    """

    def __init__(self, timeout_multiplier: float = 1.0, use_fallback_on_error: bool = True):
        """
        Initialize executor.

        Args:
            timeout_multiplier: Multiply analyzer timeout by this factor (for slow systems)
            use_fallback_on_error: Use fallback values when execution fails
        """
        self.timeout_multiplier = timeout_multiplier
        self.use_fallback_on_error = use_fallback_on_error
        self._manager = None

    @property
    def manager(self):
        """Lazy-load plugin manager to avoid circular import."""
        if self._manager is None:
            from . import get_pilot_manager
            self._manager = get_pilot_manager()
        return self._manager

    def run_analyzer(
        self,
        analyzer_name: str,
        input_file: Union[str, Path],
        params: Optional[Dict[str, Any]] = None,
    ) -> AnalysisResult:
        """
        Run a specific analyzer on input data.

        Args:
            analyzer_name: Name of analyzer to run
            input_file: Path to input file
            params: Optional additional parameters for analyzer

        Returns:
            AnalysisResult with extracted data
        """
        # Get analyzer spec
        analyzer = self.manager.get_analyzer(analyzer_name)
        if not analyzer:
            return AnalysisResult(
                analyzer_name=analyzer_name,
                status="failed",
                extracted_data={},
                execution_time_seconds=0.0,
                error_message=f"Analyzer '{analyzer_name}' not found",
            )

        # Validate input file
        input_path = Path(input_file)
        if not input_path.exists():
            return AnalysisResult(
                analyzer_name=analyzer_name,
                status="failed",
                extracted_data={},
                execution_time_seconds=0.0,
                error_message=f"Input file not found: {input_file}",
            )

        logger.info(f"Running analyzer '{analyzer_name}' on {input_file}")

        try:
            # Execute analyzer
            start_time = time.time()
            result = self._execute_analyzer(analyzer, input_path, params or {})
            execution_time = time.time() - start_time

            result.execution_time_seconds = execution_time
            logger.info(
                f"Analyzer '{analyzer_name}' completed in {execution_time:.2f}s with status: {result.status}"
            )

            return result

        except Exception as e:
            logger.error(f"Unexpected error running analyzer '{analyzer_name}': {e}", exc_info=True)
            return self._create_fallback_result(analyzer, str(e))

    def _execute_analyzer(
        self, analyzer: AnalyzerSpec, input_path: Path, params: Dict[str, Any]
    ) -> AnalysisResult:
        """
        Execute analyzer command and parse output.

        Args:
            analyzer: Analyzer specification
            input_path: Path to input file
            params: Additional parameters

        Returns:
            AnalysisResult
        """
        # Build command from template
        command = self._build_command(analyzer, input_path, params)

        # Calculate timeout
        timeout = int(analyzer.max_runtime_seconds * self.timeout_multiplier)

        try:
            # Execute command
            logger.debug(f"Executing command: {command}")
            result = subprocess.run(
                command,
                shell=True,
                capture_output=True,
                text=True,
                timeout=timeout,
                cwd=tempfile.gettempdir(),
            )

            # Check exit code
            if result.returncode != 0:
                error_msg = f"Command failed with exit code {result.returncode}: {result.stderr}"
                logger.warning(error_msg)
                if self.use_fallback_on_error:
                    return self._create_fallback_result(analyzer, error_msg)
                else:
                    return AnalysisResult(
                        analyzer_name=analyzer.name,
                        status="failed",
                        extracted_data={},
                        execution_time_seconds=0.0,
                        error_message=error_msg,
                    )

            # Parse output
            extracted = self._parse_output(analyzer, result.stdout, result.stderr)

            return AnalysisResult(
                analyzer_name=analyzer.name,
                status="success",
                extracted_data=extracted,
                execution_time_seconds=0.0,  # Set by caller
                metadata={
                    "command": command,
                    "stdout_lines": len(result.stdout.splitlines()),
                    "stderr_lines": len(result.stderr.splitlines()),
                },
            )

        except subprocess.TimeoutExpired:
            error_msg = f"Command timed out after {timeout}s"
            logger.warning(f"Analyzer '{analyzer.name}' {error_msg}")
            if self.use_fallback_on_error:
                return self._create_fallback_result(analyzer, error_msg, status="timeout")
            else:
                return AnalysisResult(
                    analyzer_name=analyzer.name,
                    status="timeout",
                    extracted_data={},
                    execution_time_seconds=float(timeout),
                    error_message=error_msg,
                )

        except Exception as e:
            error_msg = f"Execution error: {str(e)}"
            logger.error(f"Analyzer '{analyzer.name}' {error_msg}", exc_info=True)
            if self.use_fallback_on_error:
                return self._create_fallback_result(analyzer, error_msg)
            else:
                return AnalysisResult(
                    analyzer_name=analyzer.name,
                    status="failed",
                    extracted_data={},
                    execution_time_seconds=0.0,
                    error_message=error_msg,
                )

    def _build_command(
        self, analyzer: AnalyzerSpec, input_path: Path, params: Dict[str, Any]
    ) -> str:
        """
        Build command from template and parameters.

        Args:
            analyzer: Analyzer specification
            input_path: Path to input file
            params: Additional parameters

        Returns:
            Command string ready to execute
        """
        # Start with template
        command = analyzer.command_template

        # Replace standard placeholders
        replacements = {
            "{input_file}": str(input_path),
            "{output_file}": str(Path(tempfile.gettempdir()) / f"{analyzer.name}_output.txt"),
            **{f"{{{k}}}": str(v) for k, v in params.items()},
        }

        for placeholder, value in replacements.items():
            command = command.replace(placeholder, value)

        return command

    def _parse_output(self, analyzer: AnalyzerSpec, stdout: str, stderr: str) -> Dict[str, Any]:
        """
        Parse analyzer output to extract data.

        Uses domain-specific parser if available, otherwise falls back to generic parsing.

        Args:
            analyzer: Analyzer specification
            stdout: Standard output from command
            stderr: Standard error from command

        Returns:
            Dict of extracted values
        """
        # Try domain-specific parser first
        tool_parser = parsers.get_parser(analyzer.tool)
        if tool_parser:
            try:
                extracted = tool_parser.parse(stdout, stderr, {})
                if extracted:
                    logger.debug(f"Used domain-specific parser for {analyzer.tool}")
                    return extracted
            except Exception as e:
                logger.warning(f"Domain-specific parser failed for {analyzer.tool}: {e}")

        # Fall back to generic parsing
        extracted = {}

        # Determine what to extract
        extract_fields = analyzer.extract if isinstance(analyzer.extract, list) else [analyzer.extract]

        # Simple parsing strategies
        output = stdout + "\n" + stderr

        for field in extract_fields:
            # Strategy 1: JSON output
            if analyzer.output_type == "dict":
                try:
                    parsed = json.loads(stdout)
                    if isinstance(parsed, dict):
                        extracted = parsed
                        break
                except json.JSONDecodeError:
                    pass

            # Strategy 2: Key-value pairs (field: value or field=value)
            for line in output.splitlines():
                if field in line:
                    # Try colon separator
                    if ":" in line:
                        parts = line.split(":", 1)
                        if parts[0].strip().lower() == field.lower():
                            extracted[field] = self._parse_value(parts[1].strip(), analyzer.output_type)
                            break
                    # Try equals separator
                    elif "=" in line:
                        parts = line.split("=", 1)
                        if parts[0].strip().lower() == field.lower():
                            extracted[field] = self._parse_value(parts[1].strip(), analyzer.output_type)
                            break

            # Strategy 3: Just a number (for simple outputs)
            if field not in extracted and analyzer.output_type in ["integer", "float"]:
                # Try to find first number in output
                import re

                numbers = re.findall(r"[-+]?\d*\.?\d+", output)
                if numbers:
                    extracted[field] = self._parse_value(numbers[0], analyzer.output_type)

        return extracted

    def _parse_value(self, value_str: str, output_type: str) -> Any:
        """Parse string value to appropriate type."""
        value_str = value_str.strip()

        if output_type == "integer":
            return int(float(value_str))  # Handle "150.0" -> 150
        elif output_type == "float":
            return float(value_str)
        elif output_type == "string":
            return value_str
        elif output_type == "dict":
            try:
                return json.loads(value_str)
            except json.JSONDecodeError:
                return {"value": value_str}
        else:
            return value_str

    def _create_fallback_result(
        self, analyzer: AnalyzerSpec, error_message: str, status: str = "fallback"
    ) -> AnalysisResult:
        """
        Create result using fallback value.

        Args:
            analyzer: Analyzer specification
            error_message: Error that triggered fallback
            status: Result status

        Returns:
            AnalysisResult with fallback values
        """
        if analyzer.fallback is None:
            return AnalysisResult(
                analyzer_name=analyzer.name,
                status="failed",
                extracted_data={},
                execution_time_seconds=0.0,
                error_message=f"{error_message} (no fallback available)",
            )

        # Build extracted data from fallback
        extract_fields = analyzer.extract if isinstance(analyzer.extract, list) else [analyzer.extract]

        if isinstance(analyzer.fallback, dict):
            extracted_data = analyzer.fallback.copy()
        else:
            # Single field fallback
            extracted_data = {extract_fields[0]: analyzer.fallback}

        return AnalysisResult(
            analyzer_name=analyzer.name,
            status=status,
            extracted_data=extracted_data,
            execution_time_seconds=0.0,
            error_message=error_message,
            used_fallback=True,
            metadata={"fallback_reason": error_message},
        )

    def run_batch(
        self, analyzers: List[str], input_file: Union[str, Path], params: Optional[Dict[str, Any]] = None
    ) -> Dict[str, AnalysisResult]:
        """
        Run multiple analyzers on the same input file.

        Args:
            analyzers: List of analyzer names
            input_file: Path to input file
            params: Optional parameters

        Returns:
            Dict mapping analyzer name to result
        """
        results = {}
        for analyzer_name in analyzers:
            results[analyzer_name] = self.run_analyzer(analyzer_name, input_file, params)
        return results

    def run_by_input_type(
        self, input_file: Union[str, Path], max_runtime: Optional[int] = None
    ) -> Dict[str, AnalysisResult]:
        """
        Run all applicable analyzers for an input file type.

        Args:
            input_file: Path to input file
            max_runtime: Optional max runtime filter (seconds)

        Returns:
            Dict mapping analyzer name to result
        """
        input_path = Path(input_file)

        # Determine input type from extension
        ext = input_path.suffix.lower()
        type_map = {
            ".bam": "bam",
            ".fastq": "fastq",
            ".fq": "fastq",
            ".fasta": "fasta",
            ".fa": "fasta",
            ".h5ad": "h5ad",
            ".nii": "nifti",
            ".mrc": "mrc",
            ".pdb": "pdb",
        }

        input_type = type_map.get(ext)
        if not input_type:
            logger.warning(f"Unknown file type: {ext}")
            return {}

        # Get applicable analyzers
        applicable = self.manager.get_analyzers_by_input_type(input_type)

        # Filter by runtime if specified
        if max_runtime:
            applicable = [a for a in applicable if a["spec"].max_runtime_seconds <= max_runtime]

        # Run all applicable analyzers
        results = {}
        for item in applicable:
            analyzer_name = item["name"]
            results[analyzer_name] = self.run_analyzer(analyzer_name, input_file)

        return results


# Convenience function
def run_pilot_analysis(analyzer_name: str, input_file: Union[str, Path]) -> AnalysisResult:
    """
    Convenience function to run a single pilot analyzer.

    Args:
        analyzer_name: Name of analyzer
        input_file: Path to input file

    Returns:
        AnalysisResult
    """
    executor = PilotAnalysisExecutor()
    return executor.run_analyzer(analyzer_name, input_file)
