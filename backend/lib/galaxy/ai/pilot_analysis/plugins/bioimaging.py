"""
Bioimaging pilot analysis plugin.

Quick data characterization for medical/biological imaging workflows.
"""

from typing import Dict
from ..base import PilotAnalysisPlugin, AnalyzerSpec


class BioimagingPilotPlugin(PilotAnalysisPlugin):
    """Pilot analyzers for bioimaging domain."""

    @property
    def domain_name(self) -> str:
        return "bioimaging"

    @property
    def dependencies(self) -> list:
        return [
            "nibabel",
            "pydicom",
        ]

    @property
    def analyzers(self) -> Dict[str, AnalyzerSpec]:
        return {
            "analyze_image_dimensions_and_anisotropy": AnalyzerSpec(
                name="analyze_image_dimensions_and_anisotropy",
                category="bioimaging",
                description="Extract image dimensions and calculate anisotropy ratio",
                input_type="nifti",
                tool="nibabel_header",
                command_template="python -c 'import nibabel as nib; img=nib.load(\"{input_file}\"); print(img.shape, img.header.get_zooms())'",
                extract=["voxel_spacing", "image_dimensions", "anisotropy_ratio"],
                runtime_estimate="<5s",
                max_runtime_seconds=10,
                sample_strategy="header_only",
                fallback=None,
                output_type="dict",
                derived_metrics={"anisotropy_ratio": "max(voxel_spacing) / min(voxel_spacing)"},
            ),
            "detect_image_modality": AnalyzerSpec(
                name="detect_image_modality",
                category="bioimaging",
                description="Detect imaging modality from DICOM/NIfTI metadata",
                input_type="nifti",
                tool="metadata_parser",
                command_template="python -m image_metadata_parser {input_file}",
                extract=["modality", "contrast_agent", "sequence_type"],
                runtime_estimate="<5s",
                max_runtime_seconds=10,
                sample_strategy="metadata_only",
                fallback="unknown",
                output_type="dict",
            ),
        }
