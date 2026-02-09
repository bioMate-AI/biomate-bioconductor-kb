"""
Cryo-EM pilot analysis plugin.

Quick data characterization for cryo-EM workflows: particle size estimation,
CTF analysis, ice quality assessment.
"""

from typing import Dict
from ..base import PilotAnalysisPlugin, AnalyzerSpec


class CryoEMPilotPlugin(PilotAnalysisPlugin):
    """Pilot analyzers for cryo-EM domain."""

    @property
    def domain_name(self) -> str:
        return "cryo_em"

    @property
    def dependencies(self) -> list:
        return [
            "cryolo",
            "ctffind4",
            "biopython",
        ]

    @property
    def analyzers(self) -> Dict[str, AnalyzerSpec]:
        return {
            "estimate_particle_size_from_micrographs": AnalyzerSpec(
                name="estimate_particle_size_from_micrographs",
                category="cryo_em",
                description="Quick particle size estimation using crYOLO general model",
                input_type="mrc",
                tool="cryolo_general",
                command_template="cryolo_predict.py --conf cryolo_config.json --weights general_model.h5 --input {input_file}",
                extract=["median_particle_diameter", "particle_count", "confidence_distribution"],
                runtime_estimate="~2min for 10 micrographs",
                max_runtime_seconds=300,
                sample_strategy="random_10_micrographs",
                fallback=150,  # angstroms
                output_type="dict",
                units="angstroms",
                typical_range=[50, 500],
            ),
            "analyze_ctf_quality": AnalyzerSpec(
                name="analyze_ctf_quality",
                category="cryo_em",
                description="Quick CTF estimation to assess defocus range and data quality",
                input_type="mrc",
                tool="ctffind4",
                command_template="ctffind4 --input {input_file} --output /tmp/ctf_output.txt",
                extract=["defocus_min", "defocus_max", "astigmatism", "resolution_estimate", "fit_quality"],
                runtime_estimate="~30s per micrograph",
                max_runtime_seconds=60,
                sample_strategy="random_5_micrographs",
                fallback={"defocus_range": [1.0, 2.5]},
                output_type="dict",
                units="micrometers",
                thresholds={"fit_quality_min": 0.5, "resolution_max": 5.0},
            ),
            "estimate_molecular_weight_from_sequence": AnalyzerSpec(
                name="estimate_molecular_weight_from_sequence",
                category="cryo_em",
                description="Calculate molecular weight and estimate particle diameter from protein sequence",
                input_type="fasta",
                tool="biopython_mass",
                command_template="python -c 'from Bio.SeqUtils import molecular_weight; from Bio import SeqIO; ...'",
                extract=["molecular_weight_kda", "estimated_particle_diameter_angstrom"],
                runtime_estimate="<1s",
                max_runtime_seconds=5,
                sample_strategy="full_sequence",
                fallback=None,
                output_type="dict",
                derived_metrics={"estimated_diameter": "1.33 * (MW_kDa ** 0.33)"},  # Empirical formula
            ),
        }
