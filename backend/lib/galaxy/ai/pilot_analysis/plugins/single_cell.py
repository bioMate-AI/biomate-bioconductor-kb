"""
Single-cell analysis pilot plugin.

Quick data characterization for single-cell RNA-seq workflows.
"""

from typing import Dict
from ..base import PilotAnalysisPlugin, AnalyzerSpec


class SingleCellPilotPlugin(PilotAnalysisPlugin):
    """Pilot analyzers for single-cell RNA-seq domain."""

    @property
    def domain_name(self) -> str:
        return "single_cell"

    @property
    def dependencies(self) -> list:
        return [
            "scanpy",
            "anndata",
        ]

    @property
    def analyzers(self) -> Dict[str, AnalyzerSpec]:
        return {
            "estimate_scrnaseq_complexity": AnalyzerSpec(
                name="estimate_scrnaseq_complexity",
                category="single_cell",
                description="Estimate dataset complexity: cell types, batch effects, heterogeneity",
                input_type="h5ad",
                tool="scanpy_quick_analysis",
                command_template="python -m scanpy_pilot --input {input_file} --resolution 0.5",
                extract=["num_cells", "num_genes", "num_batches", "estimated_cell_types", "heterogeneity_score"],
                runtime_estimate="~30s per 10k cells",
                max_runtime_seconds=180,
                sample_strategy="subsample_to_10k",
                fallback={"num_cells": 1000, "estimated_cell_types": 5},
                output_type="dict",
            ),
            "count_cells_and_genes": AnalyzerSpec(
                name="count_cells_and_genes",
                category="single_cell",
                description="Quick count of cells and genes in single-cell dataset",
                input_type="h5ad",
                tool="anndata_shape",
                command_template="python -c 'import anndata; adata = anndata.read_h5ad(\"{input_file}\"); print(adata.shape)'",
                extract=["n_obs", "n_vars"],
                runtime_estimate="<5s",
                max_runtime_seconds=10,
                sample_strategy="metadata_only",
                fallback=None,
                output_type="dict",
                notes="Reads only metadata, very fast",
            ),
            "detect_batch_effects": AnalyzerSpec(
                name="detect_batch_effects",
                category="single_cell",
                description="Assess strength of batch effects using entropy-based metric",
                input_type="h5ad",
                tool="scanpy_batch_entropy",
                command_template="python -m scanpy_pilot --batch-entropy {input_file}",
                extract=["batch_entropy_score", "num_batches", "batch_effect_strength"],
                runtime_estimate="~1min per 10k cells",
                max_runtime_seconds=120,
                sample_strategy="subsample_to_10k",
                fallback={"batch_effect_strength": "moderate"},
                output_type="dict",
                thresholds={
                    "minimal": 0.8,  # High entropy = minimal batch effect
                    "moderate": 0.5,
                    "strong": 0.3,
                },
            ),
        }
