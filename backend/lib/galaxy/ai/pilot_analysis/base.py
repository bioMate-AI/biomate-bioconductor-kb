"""
Base classes for pilot analysis plugins.

Each domain implements a plugin that defines its analyzers for quick data characterization.
"""

from abc import ABC, abstractmethod
from typing import Dict, List, Any, Optional
from dataclasses import dataclass, field


@dataclass
class AnalyzerSpec:
    """Specification for a single pilot analyzer."""

    name: str
    description: str
    input_type: str
    tool: str
    command_template: str
    extract: Any  # str or List[str]
    runtime_estimate: str
    max_runtime_seconds: int
    sample_strategy: str
    fallback: Any
    output_type: str
    category: str = ""
    units: Optional[str] = None
    typical_range: Optional[List] = None
    thresholds: Optional[Dict] = None
    validation: Optional[Dict] = None
    derived_metrics: Optional[Dict] = None
    possible_values: Optional[List] = None
    notes: Optional[str] = None

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary format."""
        result = {
            "category": self.category,
            "description": self.description,
            "input_type": self.input_type,
            "tool": self.tool,
            "command_template": self.command_template,
            "extract": self.extract,
            "runtime_estimate": self.runtime_estimate,
            "max_runtime_seconds": self.max_runtime_seconds,
            "sample_strategy": self.sample_strategy,
            "fallback": self.fallback,
            "output_type": self.output_type,
        }

        # Add optional fields if present
        if self.units:
            result["units"] = self.units
        if self.typical_range:
            result["typical_range"] = self.typical_range
        if self.thresholds:
            result["thresholds"] = self.thresholds
        if self.validation:
            result["validation"] = self.validation
        if self.derived_metrics:
            result["derived_metrics"] = self.derived_metrics
        if self.possible_values:
            result["possible_values"] = self.possible_values
        if self.notes:
            result["notes"] = self.notes

        return result


class PilotAnalysisPlugin(ABC):
    """
    Base class for domain-specific pilot analysis plugins.

    Each domain (genomics, cryo-EM, etc.) implements this to define
    its quick data characterization analyzers.
    """

    @property
    @abstractmethod
    def domain_name(self) -> str:
        """Return the domain name (e.g., 'genomics', 'cryo_em')."""
        pass

    @property
    @abstractmethod
    def analyzers(self) -> Dict[str, AnalyzerSpec]:
        """Return dict of analyzer_name -> AnalyzerSpec."""
        pass

    @property
    def dependencies(self) -> List[str]:
        """
        Return list of required tools/packages for this domain's analyzers.

        Override in subclass to specify domain-specific dependencies.
        Example: ['samtools', 'fastqc', 'phantompeakqualtools']
        """
        return []

    def get_analyzer(self, name: str) -> Optional[AnalyzerSpec]:
        """Get a specific analyzer by name."""
        return self.analyzers.get(name)

    def list_analyzer_names(self) -> List[str]:
        """Get list of all analyzer names in this domain."""
        return list(self.analyzers.keys())

    def get_quick_analyzers(self, max_runtime: int = 30) -> List[str]:
        """Get analyzers that run in under max_runtime seconds."""
        return [
            name
            for name, spec in self.analyzers.items()
            if spec.max_runtime_seconds <= max_runtime
        ]

    def validate_dependencies(self) -> Dict[str, bool]:
        """
        Check if required dependencies are available.

        Returns:
            Dict mapping dependency name to availability status
        """
        import shutil

        results = {}
        for dep in self.dependencies:
            # Check if command exists
            results[dep] = shutil.which(dep) is not None

        return results

    def to_dict(self) -> Dict[str, Any]:
        """Convert plugin to dictionary format for registry."""
        return {
            "domain": self.domain_name,
            "analyzers": {name: spec.to_dict() for name, spec in self.analyzers.items()},
            "dependencies": self.dependencies,
        }
