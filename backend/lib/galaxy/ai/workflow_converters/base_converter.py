"""
Base Converter Interface

Defines abstract interface for workflow format converters.
"""

from abc import ABC, abstractmethod
from typing import Dict, Any
from ..workflow_abstraction import UnifiedWorkflow


class BaseConverter(ABC):
    """
    Abstract base class for workflow converters.

    All converters must implement:
    - convert(): Main conversion method
    - validate(): Validate input before conversion
    """

    @abstractmethod
    def convert(self, source: Any) -> UnifiedWorkflow:
        """
        Convert source format to UnifiedWorkflow.

        Args:
            source: Source workflow (format depends on converter)

        Returns:
            UnifiedWorkflow instance

        Raises:
            ValueError: If source is invalid
            NotImplementedError: If conversion not supported
        """
        pass

    @abstractmethod
    def validate(self, source: Any) -> tuple[bool, list[str]]:
        """
        Validate source workflow before conversion.

        Args:
            source: Source workflow to validate

        Returns:
            (is_valid, error_messages)
        """
        pass

    def _log_conversion_stats(self, workflow: UnifiedWorkflow):
        """Log conversion statistics."""
        num_hl_steps = len(workflow.high_level_steps)
        num_detailed_steps = len(workflow.get_all_detailed_steps())
        print(f"Converted workflow: {workflow.name}")
        print(f"  - {num_hl_steps} high-level steps")
        print(f"  - {num_detailed_steps} detailed steps")
        print(f"  - Source: {workflow.source_format.value}")
        print(f"  - Execution engine: {workflow.execution_engine.value}")
