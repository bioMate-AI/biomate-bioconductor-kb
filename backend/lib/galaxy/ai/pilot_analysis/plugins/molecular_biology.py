"""
Molecular biology pilot analysis plugin.

Quick data characterization for cloning, primer design, and sequence analysis.
"""

from typing import Dict
from ..base import PilotAnalysisPlugin, AnalyzerSpec


class MolecularBiologyPilotPlugin(PilotAnalysisPlugin):
    """Pilot analyzers for molecular biology domain."""

    @property
    def domain_name(self) -> str:
        return "molecular_biology"

    @property
    def dependencies(self) -> list:
        return [
            "dustmasker",
            "biopython",
            "primer3",
        ]

    @property
    def analyzers(self) -> Dict[str, AnalyzerSpec]:
        return {
            "detect_repeat_regions": AnalyzerSpec(
                name="detect_repeat_regions",
                category="molecular_biology",
                description="Identify low-complexity and repeat regions in sequence",
                input_type="fasta",
                tool="dustmasker",
                command_template="dustmasker -in {input_file} -outfmt fasta",
                extract=["low_complexity_fraction", "repeat_fraction"],
                runtime_estimate="<5s for sequences <10kb",
                max_runtime_seconds=30,
                sample_strategy="full_sequence",
                fallback=0.1,
                output_type="float",
                thresholds={"low": 0.1, "moderate": 0.3, "high": 0.5},
            ),
            "find_restriction_sites": AnalyzerSpec(
                name="find_restriction_sites",
                category="molecular_biology",
                description="Identify common restriction enzyme sites in sequence",
                input_type="fasta",
                tool="biopython_restriction",
                command_template="python -m bio_restriction_analysis {input_file}",
                extract=["common_enzyme_sites", "unique_cutters", "site_count"],
                runtime_estimate="<5s",
                max_runtime_seconds=10,
                sample_strategy="full_sequence",
                fallback=None,
                output_type="dict",
            ),
            "predict_primer_secondary_structure": AnalyzerSpec(
                name="predict_primer_secondary_structure",
                category="molecular_biology",
                description="Predict primer secondary structures (hairpins, dimers)",
                input_type="sequence_string",
                tool="primer3_thermodynamics",
                command_template="python -m primer3_thermo {sequence}",
                extract=["hairpin_deltaG", "self_dimer_deltaG", "hetero_dimer_deltaG"],
                runtime_estimate="<1s",
                max_runtime_seconds=5,
                sample_strategy="full_sequence",
                fallback=None,
                output_type="dict",
                thresholds={
                    "hairpin_max": -3.0,
                    "self_dimer_max": -5.0,
                    "hetero_dimer_max": -6.0,
                },
            ),
        }
