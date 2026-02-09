"""
Pilot Analysis Registry - Quick data characterization for parameter inference.

This module defines all available pilot analyses that can be run on user data
to extract context needed for intelligent parameter inference.

Each analyzer is lightweight (<5 min runtime) and extracts specific characteristics
like GC content, fragment size, particle diameter, image properties, etc.
"""

from typing import Dict, List, Any


# Registry of all available pilot analyses
PILOT_ANALYZERS: Dict[str, Dict[str, Any]] = {
    # ========================================================================
    # GENOMICS ANALYZERS
    # ========================================================================

    "estimate_fragment_size": {
        "category": "genomics",
        "description": "Estimate DNA fragment size from BAM file using insert size distribution",
        "input_type": "bam",
        "tool": "samtools_stats",
        "command_template": "samtools stats {input_file} | grep '^SN' | grep 'insert size average'",
        "extract": "insert_size_average",
        "runtime_estimate": "~30s per 10M reads",
        "max_runtime_seconds": 300,
        "sample_strategy": "first_10M_reads",
        "fallback": 200,
        "output_type": "integer",
        "units": "bp",
        "typical_range": [100, 500]
    },

    "estimate_fragment_shift": {
        "category": "genomics",
        "description": "Estimate fragment shift for ChIP-seq using cross-correlation analysis",
        "input_type": "bam",
        "tool": "phantompeakqualtools",
        "command_template": "Rscript run_spp.R -c={input_file} -savp -out={output_file}",
        "extract": ["strand_shift", "nsc", "rsc"],
        "runtime_estimate": "~2min per 100M reads",
        "max_runtime_seconds": 300,
        "sample_strategy": "subsample_to_10M",
        "fallback": None,
        "output_type": "dict",
        "validation": {
            "nsc": {"min": 1.0, "recommended": 1.05},
            "rsc": {"min": 0.8, "recommended": 1.0}
        }
    },

    "detect_sequencing_protocol": {
        "category": "genomics",
        "description": "Detect if data is single-end or paired-end sequencing",
        "input_type": "bam",
        "tool": "samtools_view",
        "command_template": "samtools view -c -f 1 {input_file} | head -1000",
        "extract": "sequencing_protocol",
        "runtime_estimate": "<5s",
        "max_runtime_seconds": 10,
        "sample_strategy": "first_1000_reads",
        "fallback": "single_end",
        "output_type": "string",
        "possible_values": ["single_end", "paired_end"]
    },

    "estimate_read_quality": {
        "category": "genomics",
        "description": "Quick quality assessment with FastQC (plots disabled for speed)",
        "input_type": "fastq",
        "tool": "fastqc_lite",
        "command_template": "fastqc --extract --nogroup -o /tmp/ {input_file}",
        "extract": ["mean_quality_score", "sequence_duplication_level", "gc_content", "total_sequences"],
        "runtime_estimate": "~1min per 50M reads",
        "max_runtime_seconds": 120,
        "sample_strategy": "subsample_to_1M",
        "fallback": {"mean_quality_score": 30, "gc_content": 50},
        "output_type": "dict"
    },

    "count_reads_and_depth": {
        "category": "genomics",
        "description": "Count total reads and estimate sequencing depth",
        "input_type": "bam",
        "tool": "samtools_flagstat",
        "command_template": "samtools flagstat {input_file}",
        "extract": ["total_reads", "mapped_reads", "properly_paired"],
        "runtime_estimate": "<30s",
        "max_runtime_seconds": 60,
        "sample_strategy": "full_file",
        "fallback": None,
        "output_type": "dict",
        "derived_metrics": {
            "mapping_rate": "mapped_reads / total_reads",
            "estimated_depth": "mapped_reads * read_length / genome_size"
        }
    },

    "analyze_template_gc_content": {
        "category": "genomics",
        "description": "Analyze GC content of template sequence for primer design",
        "input_type": "fasta",
        "tool": "seqkit_fx2tab",
        "command_template": "seqkit fx2tab --gc {input_file}",
        "extract": ["gc_percentage", "sequence_length"],
        "runtime_estimate": "<10s for sequences <10kb",
        "max_runtime_seconds": 30,
        "sample_strategy": "full_sequence",
        "fallback": 50.0,
        "output_type": "float",
        "typical_range": [20, 80],
        "thresholds": {
            "at_rich": 35,
            "balanced": 65,
            "gc_rich": 65
        }
    },

    # ========================================================================
    # SINGLE-CELL RNA-SEQ ANALYZERS
    # ========================================================================

    "estimate_scrnaseq_complexity": {
        "category": "single_cell",
        "description": "Estimate dataset complexity: cell types, batch effects, heterogeneity",
        "input_type": "h5ad",
        "tool": "scanpy_quick_analysis",
        "command_template": "python -m scanpy_pilot --input {input_file} --resolution 0.5",
        "extract": ["num_cells", "num_genes", "num_batches", "estimated_cell_types", "heterogeneity_score"],
        "runtime_estimate": "~30s per 10k cells",
        "max_runtime_seconds": 180,
        "sample_strategy": "subsample_to_10k",
        "fallback": {"num_cells": 1000, "estimated_cell_types": 5},
        "output_type": "dict"
    },

    "count_cells_and_genes": {
        "category": "single_cell",
        "description": "Quick count of cells and genes in single-cell dataset",
        "input_type": "h5ad",
        "tool": "anndata_shape",
        "command_template": "python -c 'import anndata; adata = anndata.read_h5ad(\"{input_file}\"); print(adata.shape)'",
        "extract": ["n_obs", "n_vars"],
        "runtime_estimate": "<5s",
        "max_runtime_seconds": 10,
        "sample_strategy": "metadata_only",
        "fallback": None,
        "output_type": "dict",
        "notes": "Reads only metadata, very fast"
    },

    "detect_batch_effects": {
        "category": "single_cell",
        "description": "Assess strength of batch effects using entropy-based metric",
        "input_type": "h5ad",
        "tool": "scanpy_batch_entropy",
        "command_template": "python -m scanpy_pilot --batch-entropy {input_file}",
        "extract": ["batch_entropy_score", "num_batches", "batch_effect_strength"],
        "runtime_estimate": "~1min per 10k cells",
        "max_runtime_seconds": 120,
        "sample_strategy": "subsample_to_10k",
        "fallback": {"batch_effect_strength": "moderate"},
        "output_type": "dict",
        "thresholds": {
            "minimal": 0.8,  # High entropy = minimal batch effect
            "moderate": 0.5,
            "strong": 0.3
        }
    },

    # ========================================================================
    # BIOIMAGING ANALYZERS
    # ========================================================================

    "analyze_image_dimensions_and_anisotropy": {
        "category": "bioimaging",
        "description": "Extract image dimensions and calculate anisotropy ratio",
        "input_type": "nifti",
        "tool": "nibabel_header",
        "command_template": "python -c 'import nibabel as nib; img=nib.load(\"{input_file}\"); print(img.shape, img.header.get_zooms())'",
        "extract": ["voxel_spacing", "image_dimensions", "anisotropy_ratio"],
        "runtime_estimate": "<5s",
        "max_runtime_seconds": 10,
        "sample_strategy": "header_only",
        "fallback": None,
        "output_type": "dict",
        "derived_metrics": {
            "anisotropy_ratio": "max(voxel_spacing) / min(voxel_spacing)"
        }
    },

    "detect_image_modality": {
        "category": "bioimaging",
        "description": "Detect imaging modality from DICOM/NIfTI metadata",
        "input_type": "nifti",
        "tool": "metadata_parser",
        "command_template": "python -m image_metadata_parser {input_file}",
        "extract": ["modality", "contrast_agent", "sequence_type"],
        "runtime_estimate": "<5s",
        "max_runtime_seconds": 10,
        "sample_strategy": "metadata_only",
        "fallback": "unknown",
        "output_type": "dict"
    },

    # ========================================================================
    # CRYO-EM ANALYZERS
    # ========================================================================

    "estimate_particle_size_from_micrographs": {
        "category": "cryo_em",
        "description": "Quick particle size estimation using crYOLO general model",
        "input_type": "mrc",
        "tool": "cryolo_general",
        "command_template": "cryolo_predict.py --conf cryolo_config.json --weights general_model.h5 --input {input_file}",
        "extract": ["median_particle_diameter", "particle_count", "confidence_distribution"],
        "runtime_estimate": "~2min for 10 micrographs",
        "max_runtime_seconds": 300,
        "sample_strategy": "random_10_micrographs",
        "fallback": 150,  # angstroms
        "output_type": "dict",
        "units": "angstroms",
        "typical_range": [50, 500]
    },

    "analyze_ctf_quality": {
        "category": "cryo_em",
        "description": "Quick CTF estimation to assess defocus range and data quality",
        "input_type": "mrc",
        "tool": "ctffind4",
        "command_template": "ctffind4 --input {input_file} --output /tmp/ctf_output.txt",
        "extract": ["defocus_min", "defocus_max", "astigmatism", "resolution_estimate", "fit_quality"],
        "runtime_estimate": "~30s per micrograph",
        "max_runtime_seconds": 60,
        "sample_strategy": "random_5_micrographs",
        "fallback": {"defocus_range": [1.0, 2.5]},
        "output_type": "dict",
        "units": "micrometers",
        "quality_threshold": {
            "fit_quality_min": 0.5,
            "resolution_max": 5.0
        }
    },

    "estimate_molecular_weight_from_sequence": {
        "category": "cryo_em",
        "description": "Calculate molecular weight and estimate particle diameter from protein sequence",
        "input_type": "fasta",
        "tool": "biopython_mass",
        "command_template": "python -c 'from Bio.SeqUtils import molecular_weight; from Bio import SeqIO; ...'",
        "extract": ["molecular_weight_kda", "estimated_particle_diameter_angstrom"],
        "runtime_estimate": "<1s",
        "max_runtime_seconds": 5,
        "sample_strategy": "full_sequence",
        "fallback": None,
        "output_type": "dict",
        "derived_metrics": {
            "estimated_diameter": "1.33 * (MW_kDa ** 0.33)"  # Empirical formula
        }
    },

    # ========================================================================
    # MOLECULAR BIOLOGY ANALYZERS
    # ========================================================================

    "detect_repeat_regions": {
        "category": "molecular_biology",
        "description": "Identify low-complexity and repeat regions in sequence",
        "input_type": "fasta",
        "tool": "dustmasker",
        "command_template": "dustmasker -in {input_file} -outfmt fasta",
        "extract": ["low_complexity_fraction", "repeat_fraction"],
        "runtime_estimate": "<5s for sequences <10kb",
        "max_runtime_seconds": 30,
        "sample_strategy": "full_sequence",
        "fallback": 0.1,
        "output_type": "float",
        "thresholds": {
            "low": 0.1,
            "moderate": 0.3,
            "high": 0.5
        }
    },

    "find_restriction_sites": {
        "category": "molecular_biology",
        "description": "Identify common restriction enzyme sites in sequence",
        "input_type": "fasta",
        "tool": "biopython_restriction",
        "command_template": "python -m bio_restriction_analysis {input_file}",
        "extract": ["common_enzyme_sites", "unique_cutters", "site_count"],
        "runtime_estimate": "<5s",
        "max_runtime_seconds": 10,
        "sample_strategy": "full_sequence",
        "fallback": None,
        "output_type": "dict"
    },

    "predict_primer_secondary_structure": {
        "category": "molecular_biology",
        "description": "Predict primer secondary structures (hairpins, dimers)",
        "input_type": "sequence_string",
        "tool": "primer3_thermodynamics",
        "command_template": "python -m primer3_thermo {sequence}",
        "extract": ["hairpin_deltaG", "self_dimer_deltaG", "hetero_dimer_deltaG"],
        "runtime_estimate": "<1s",
        "max_runtime_seconds": 5,
        "sample_strategy": "full_sequence",
        "fallback": None,
        "output_type": "dict",
        "thresholds": {
            "hairpin_max": -3.0,
            "self_dimer_max": -5.0,
            "hetero_dimer_max": -6.0
        }
    },

    # ========================================================================
    # PHARMACOLOGY ANALYZERS
    # ========================================================================

    "calculate_ligand_properties": {
        "category": "pharmacology",
        "description": "Calculate molecular descriptors from SMILES string",
        "input_type": "smiles",
        "tool": "rdkit_descriptors",
        "command_template": "python -c 'from rdkit import Chem; from rdkit.Chem import Descriptors; ...'",
        "extract": ["molecular_weight", "logp", "num_rotatable_bonds", "tpsa", "num_h_donors", "num_h_acceptors"],
        "runtime_estimate": "<1s per molecule",
        "max_runtime_seconds": 5,
        "sample_strategy": "single_molecule",
        "fallback": None,
        "output_type": "dict",
        "derived_metrics": {
            "lipinski_violations": "count(MW>500, LogP>5, HBD>5, HBA>10)"
        }
    },

    "detect_protein_binding_site": {
        "category": "pharmacology",
        "description": "Identify potential binding pockets in protein structure",
        "input_type": "pdb",
        "tool": "fpocket",
        "command_template": "fpocket -f {input_file}",
        "extract": ["pocket_centers", "pocket_volumes", "druggability_scores"],
        "runtime_estimate": "~10s per structure",
        "max_runtime_seconds": 30,
        "sample_strategy": "full_structure",
        "fallback": None,
        "output_type": "dict",
        "notes": "Returns top 5 pockets ranked by druggability"
    },

    # ========================================================================
    # BIOCHEMISTRY ANALYZERS
    # ========================================================================

    "estimate_enzyme_km_from_literature": {
        "category": "biochemistry",
        "description": "Query BRENDA database for known Km values",
        "input_type": "enzyme_name",
        "tool": "brenda_api",
        "command_template": "python -m brenda_query --enzyme '{enzyme}' --substrate '{substrate}'",
        "extract": ["km_values", "organism_specific", "temperature", "ph"],
        "runtime_estimate": "~5s (API call)",
        "max_runtime_seconds": 10,
        "sample_strategy": "api_query",
        "fallback": None,
        "output_type": "dict",
        "notes": "Requires internet connection and BRENDA API key"
    }
}


# Category groupings
ANALYZER_CATEGORIES = {
    "genomics": [
        "estimate_fragment_size",
        "estimate_fragment_shift",
        "detect_sequencing_protocol",
        "estimate_read_quality",
        "count_reads_and_depth",
        "analyze_template_gc_content"
    ],
    "single_cell": [
        "estimate_scrnaseq_complexity",
        "count_cells_and_genes",
        "detect_batch_effects"
    ],
    "bioimaging": [
        "analyze_image_dimensions_and_anisotropy",
        "detect_image_modality"
    ],
    "cryo_em": [
        "estimate_particle_size_from_micrographs",
        "analyze_ctf_quality",
        "estimate_molecular_weight_from_sequence"
    ],
    "molecular_biology": [
        "detect_repeat_regions",
        "find_restriction_sites",
        "predict_primer_secondary_structure"
    ],
    "pharmacology": [
        "calculate_ligand_properties",
        "detect_protein_binding_site"
    ],
    "biochemistry": [
        "estimate_enzyme_km_from_literature"
    ]
}


def get_analyzer(name: str) -> Dict[str, Any]:
    """Get analyzer definition by name."""
    return PILOT_ANALYZERS.get(name)


def get_analyzers_by_category(category: str) -> List[Dict[str, Any]]:
    """Get all analyzers in a category."""
    analyzer_names = ANALYZER_CATEGORIES.get(category, [])
    return [PILOT_ANALYZERS[name] for name in analyzer_names if name in PILOT_ANALYZERS]


def get_quick_analyzers(max_runtime: int = 30) -> List[str]:
    """Get list of analyzers that run in under max_runtime seconds."""
    quick = []
    for name, analyzer in PILOT_ANALYZERS.items():
        if analyzer.get('max_runtime_seconds', float('inf')) <= max_runtime:
            quick.append(name)
    return quick


def validate_input_type(file_path: str, required_type: str) -> bool:
    """Check if file matches required input type."""
    import os

    ext = os.path.splitext(file_path)[1].lower()

    type_extensions = {
        'bam': ['.bam'],
        'fastq': ['.fastq', '.fq', '.fastq.gz', '.fq.gz'],
        'fasta': ['.fasta', '.fa', '.fna', '.faa'],
        'h5ad': ['.h5ad'],
        'mtx': ['.mtx', '.mtx.gz'],
        'nifti': ['.nii', '.nii.gz'],
        'mrc': ['.mrc', '.mrcs'],
        'pdb': ['.pdb'],
        'smiles': ['*'],  # String, not a file
        'sequence_string': ['*'],  # String, not a file
        'enzyme_name': ['*']  # String, not a file
    }

    allowed = type_extensions.get(required_type, [])
    return ext in allowed or '*' in allowed
