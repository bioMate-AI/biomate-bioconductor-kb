#!/usr/bin/env nextflow
/*
 * genomics/custom_mode
 * Custom analysis mode selector for genomics workflows
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Demo: Show available analysis modes
params.x = 'demo'
params.mode = 'info'

process CUSTOM_MODE {
    tag { meta.id }
    label 'process_medium'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("custom_mode_results.json"), emit: results
    tuple val(meta), path("custom_mode_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_X="${params.x?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_MODE="${params.mode?.toString()?.replace('"', '\\"') ?: 'null'}"

    python3 << 'PYEOF'
# Auto-generated from Galaxy wrapper - self-contained implementation

import json
import os
import sys
from datetime import datetime

def auto_convert(val):
    # Auto-convert string to appropriate type
    if val is None or val == '' or val == 'null':
        return None
    # Try bool
    if isinstance(val, str) and val.lower() in ('true', 'false'):
        return val.lower() == 'true'
    # Try JSON for lists and dicts
    if isinstance(val, str) and val.strip().startswith(('[', '{')):
        try:
            return json.loads(val)
        except json.JSONDecodeError:
            pass
    # Try int
    try:
        if isinstance(val, str) and '.' not in val:
            return int(val)
    except ValueError:
        pass
    # Try float
    try:
        return float(val)
    except ValueError:
        pass
    # Return as string
    return val


def custom_mode(x=None, mode='info'):
    '''Custom analysis mode selector for genomics workflows.

    This function provides a flexible interface for selecting and configuring
    different analysis modes in genomics workflows. It can be used to:
    - Get information about available analysis modes
    - Validate configuration parameters
    - Generate mode-specific settings

    Parameters
    ----------
    x : str or dict
        Mode-specific input parameter or configuration
    mode : str
        Analysis mode: 'info', 'validate', 'configure', 'list'

    Returns
    -------
    dict
        Mode configuration and status information
    '''
    # Available analysis modes with descriptions
    available_modes = {
        "standard": {
            "description": "Standard single-cell RNA-seq analysis",
            "steps": ["quality_control", "normalization", "clustering", "marker_detection"],
            "tools": ["scanpy", "anndata"],
        },
        "integration": {
            "description": "Multi-dataset integration analysis",
            "steps": ["batch_correction", "harmony", "scvi_integration", "joint_embedding"],
            "tools": ["scanpy", "scvi-tools", "harmonypy"],
        },
        "trajectory": {
            "description": "Cell trajectory and pseudotime analysis",
            "steps": ["pseudotime", "trajectory_inference", "gene_dynamics"],
            "tools": ["scanpy", "scvelo", "cellrank"],
        },
        "spatial": {
            "description": "Spatial transcriptomics analysis",
            "steps": ["spatial_neighbors", "niche_detection", "ligand_receptor"],
            "tools": ["scanpy", "squidpy", "cell2location"],
        },
        "velocity": {
            "description": "RNA velocity analysis",
            "steps": ["splicing_analysis", "velocity_estimation", "dynamics"],
            "tools": ["scvelo", "velocyto"],
        },
        "multiome": {
            "description": "Multi-omics integration (RNA + ATAC)",
            "steps": ["peak_calling", "gene_activity", "wnn_integration"],
            "tools": ["scanpy", "muon", "episcanpy"],
        },
    }

    result = {
        "status": "success",
        "mode": mode,
        "timestamp": datetime.now().isoformat(),
    }

    if mode == 'info' or mode == 'list':
        result["available_modes"] = available_modes
        result["n_modes"] = len(available_modes)
        result["message"] = "Available genomics analysis modes"
        return result

    if mode == 'validate':
        if x is None:
            result["status"] = "error"
            result["message"] = "No configuration provided for validation"
            return result

        # Validate configuration
        config = x if isinstance(x, dict) else {"mode_name": x}
        mode_name = config.get("mode_name", x)

        if mode_name in available_modes:
            result["validated"] = True
            result["mode_config"] = available_modes[mode_name]
            result["message"] = f"Mode '{mode_name}' is valid"
        else:
            result["validated"] = False
            result["message"] = f"Unknown mode: {mode_name}"
            result["available"] = list(available_modes.keys())
        return result

    if mode == 'configure':
        if x is None:
            x = "standard"

        mode_name = x if isinstance(x, str) else x.get("mode_name", "standard")

        if mode_name not in available_modes:
            result["status"] = "error"
            result["message"] = f"Unknown mode: {mode_name}"
            result["available"] = list(available_modes.keys())
            return result

        mode_config = available_modes[mode_name]
        result["configuration"] = {
            "mode_name": mode_name,
            **mode_config,
            "settings": {
                "n_neighbors": 15,
                "n_pcs": 50,
                "resolution": 1.0,
                "min_genes": 200,
                "min_cells": 3,
            },
        }
        result["message"] = f"Configuration generated for mode: {mode_name}"
        return result

    # Default: show demo info
    result["mode"] = "demo"
    result["input_x"] = x
    result["available_modes"] = list(available_modes.keys())
    result["message"] = "Custom mode selector - use mode='info' to see all modes"

    # Check for installed packages
    packages = {}
    try:
        import scanpy
        packages["scanpy"] = scanpy.__version__
    except ImportError:
        packages["scanpy"] = "not installed"

    try:
        import anndata
        packages["anndata"] = anndata.__version__
    except ImportError:
        packages["anndata"] = "not installed"

    result["installed_packages"] = packages

    return result

# Execute the function
try:
    result = custom_mode(
        x=auto_convert(os.environ.get("PARAM_X", "demo")),
        mode=auto_convert(os.environ.get("PARAM_MODE", "info")) or "info",
    )
    success = True
    error_msg = None
except Exception as e:
    result = None
    success = False
    error_msg = str(e)

# Save results
output_data = {
    "success": success,
    "function": "custom_mode",
    "domain": "genomics",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("custom_mode_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("custom_mode_output.txt", "w") as f:
    f.write("Biomni: Custom Mode" + NL)
    f.write("=" * 60 + NL + NL)
    if success:
        if isinstance(result, str):
            f.write(result)
        elif isinstance(result, dict):
            for key, value in result.items():
                f.write(f"{key}: {value}" + NL)
        else:
            f.write(str(result))
    else:
        f.write(f"ERROR: {error_msg}" + NL)

if not success:
    exit(1)
PYEOF

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: \$(python3 --version | cut -d' ' -f2)
        biomni_function: "custom_mode"
    END_VERSIONS
    """
}

workflow CUSTOM_MODE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    CUSTOM_MODE(ch_input)

    emit:
    results = CUSTOM_MODE.out.results
    output = CUSTOM_MODE.out.output
    versions = CUSTOM_MODE.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    CUSTOM_MODE_WORKFLOW(ch_input)

    CUSTOM_MODE_WORKFLOW.out.output.view { "Output: $it" }
}
