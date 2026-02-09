"""
Biochemistry pilot analysis plugin.

Quick data characterization for enzyme kinetics and protein biochemistry.
"""

from typing import Dict
from ..base import PilotAnalysisPlugin, AnalyzerSpec


class BiochemistryPilotPlugin(PilotAnalysisPlugin):
    """Pilot analyzers for biochemistry domain."""

    @property
    def domain_name(self) -> str:
        return "biochemistry"

    @property
    def dependencies(self) -> list:
        return [
            "brenda-api",  # BRENDA database client
        ]

    @property
    def analyzers(self) -> Dict[str, AnalyzerSpec]:
        return {
            "estimate_enzyme_km_from_literature": AnalyzerSpec(
                name="estimate_enzyme_km_from_literature",
                category="biochemistry",
                description="Query BRENDA database for known Km values",
                input_type="enzyme_name",
                tool="brenda_api",
                command_template="python -m brenda_query --enzyme '{enzyme}' --substrate '{substrate}'",
                extract=["km_values", "organism_specific", "temperature", "ph"],
                runtime_estimate="~5s (API call)",
                max_runtime_seconds=10,
                sample_strategy="api_query",
                fallback=None,
                output_type="dict",
                notes="Requires internet connection and BRENDA API key",
            ),
        }
