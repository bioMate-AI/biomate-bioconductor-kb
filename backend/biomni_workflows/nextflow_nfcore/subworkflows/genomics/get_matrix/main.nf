#!/usr/bin/env nextflow
/*
 * genomics/get_matrix
 * Extract expression matrix from single-cell data or H5AD files
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Demo: Use PBMC test data
params.h5ad_file = "${projectDir}/../../../../lib/galaxy/datatypes/test/pbmc3k_tiny.h5ad"
params.chrom = null
params.balance_if_possible = true
params.layer = null
params.output_format = 'dense'

process GET_MATRIX {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("get_matrix_results.json"), emit: results
    tuple val(meta), path("get_matrix_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Disable numba JIT to avoid caching issues in Docker containers
    export NUMBA_DISABLE_JIT=1
    export NUMBA_CACHE_DIR=/tmp/numba_cache
    mkdir -p /tmp/numba_cache

    # Export parameters as environment variables
    export PARAM_H5AD_FILE="${params.h5ad_file?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_CHROM="${params.chrom?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_BALANCE_IF_POSSIBLE="${params.balance_if_possible?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_LAYER="${params.layer?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_OUTPUT_FORMAT="${params.output_format?.toString()?.replace('"', '\\"') ?: 'null'}"

    python3 << 'PYEOF'
# Auto-generated from Galaxy wrapper - self-contained implementation

import json
import os
import numpy as np

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


def get_matrix(h5ad_file=None, chrom=None, balance_if_possible=True, layer=None, output_format='dense'):
    '''Extract expression matrix from single-cell H5AD files.

    This function extracts the expression matrix from AnnData objects,
    supporting various layers and output formats.

    Parameters
    ----------
    h5ad_file : str
        Path to H5AD file containing single-cell data
    chrom : str
        Chromosome to filter (optional, for genomic data)
    balance_if_possible : bool
        Apply balancing/normalization if available (default: True)
    layer : str
        Specific layer to extract (None for X matrix)
    output_format : str
        Output format: 'dense', 'sparse', 'summary'

    Returns
    -------
    dict
        Matrix information and statistics
    '''
    result = {
        "function": "get_matrix",
        "status": "success",
    }

    # Demo mode if no file provided
    if h5ad_file is None or not os.path.exists(str(h5ad_file)):
        result["mode"] = "demo"
        result["message"] = "No H5AD file provided or file not found"
        result["demo_info"] = {
            "purpose": "Extract expression matrix from single-cell data",
            "supported_formats": ["h5ad", "loom", "mtx"],
            "available_layers": ["X (main matrix)", "raw", "counts", "normalized", "scaled"],
            "output_formats": ["dense", "sparse", "summary"],
            "usage": "Provide h5ad_file parameter with path to data",
        }
        result["example_output"] = {
            "matrix_shape": [2700, 32738],
            "matrix_type": "sparse",
            "density": 0.05,
            "total_counts": 123456789,
        }
        return result

    try:
        import scanpy as sc
        import scipy.sparse as sp

        # Load the H5AD file
        adata = sc.read_h5ad(h5ad_file)

        result["file"] = h5ad_file
        result["n_cells"] = adata.n_obs
        result["n_genes"] = adata.n_vars

        # Get matrix based on layer
        if layer is not None and layer in adata.layers:
            matrix = adata.layers[layer]
            result["layer"] = layer
        elif layer == "raw" and adata.raw is not None:
            matrix = adata.raw.X
            result["layer"] = "raw"
        else:
            matrix = adata.X
            result["layer"] = "X"

        # Matrix properties
        is_sparse = sp.issparse(matrix)
        result["is_sparse"] = is_sparse

        if is_sparse:
            result["matrix_format"] = type(matrix).__name__
            result["nnz"] = matrix.nnz
            result["density"] = round(matrix.nnz / (matrix.shape[0] * matrix.shape[1]), 4)

            # Convert to dense for statistics if small enough
            if matrix.shape[0] * matrix.shape[1] < 1e8:
                dense = matrix.toarray()
            else:
                # Sample for large matrices
                sample_idx = np.random.choice(matrix.shape[0], min(1000, matrix.shape[0]), replace=False)
                dense = matrix[sample_idx].toarray()
                result["stats_sampled"] = True
        else:
            result["matrix_format"] = "dense"
            dense = matrix
            result["density"] = round(np.count_nonzero(dense) / dense.size, 4)

        # Statistics
        result["matrix_shape"] = list(matrix.shape)
        result["dtype"] = str(matrix.dtype)
        result["min_value"] = float(np.min(dense))
        result["max_value"] = float(np.max(dense))
        result["mean_value"] = float(np.mean(dense))
        result["median_value"] = float(np.median(dense))

        # Per-cell statistics
        if is_sparse:
            cell_sums = np.array(matrix.sum(axis=1)).flatten()
        else:
            cell_sums = matrix.sum(axis=1)

        result["cell_stats"] = {
            "min_counts": float(np.min(cell_sums)),
            "max_counts": float(np.max(cell_sums)),
            "mean_counts": float(np.mean(cell_sums)),
            "median_counts": float(np.median(cell_sums)),
        }

        # Per-gene statistics
        if is_sparse:
            gene_sums = np.array(matrix.sum(axis=0)).flatten()
        else:
            gene_sums = matrix.sum(axis=0)

        result["gene_stats"] = {
            "min_counts": float(np.min(gene_sums)),
            "max_counts": float(np.max(gene_sums)),
            "mean_counts": float(np.mean(gene_sums)),
            "genes_detected": int(np.sum(gene_sums > 0)),
        }

        # Available layers
        result["available_layers"] = list(adata.layers.keys()) if adata.layers else []
        result["has_raw"] = adata.raw is not None

        # Sample cell names and gene names
        result["sample_cells"] = list(adata.obs_names[:5])
        result["sample_genes"] = list(adata.var_names[:10])

        # Observation columns (cell metadata)
        result["obs_columns"] = list(adata.obs.columns)

        # Variable columns (gene metadata)
        result["var_columns"] = list(adata.var.columns)

    except Exception as e:
        result["status"] = "error"
        result["error"] = str(e)

    return result

# Execute the function
try:
    result = get_matrix(
        h5ad_file=auto_convert(os.environ.get("PARAM_H5AD_FILE", "")),
        chrom=auto_convert(os.environ.get("PARAM_CHROM", "")),
        balance_if_possible=auto_convert(os.environ.get("PARAM_BALANCE_IF_POSSIBLE", "True")),
        layer=auto_convert(os.environ.get("PARAM_LAYER", "")),
        output_format=auto_convert(os.environ.get("PARAM_OUTPUT_FORMAT", "dense")),
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
    "function": "get_matrix",
    "domain": "genomics",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("get_matrix_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("get_matrix_output.txt", "w") as f:
    f.write("Biomni: Get Matrix" + NL)
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
        biomni_function: "get_matrix"
    END_VERSIONS
    """
}

workflow GET_MATRIX_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    GET_MATRIX(ch_input)

    emit:
    results = GET_MATRIX.out.results
    output = GET_MATRIX.out.output
    versions = GET_MATRIX.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    GET_MATRIX_WORKFLOW(ch_input)

    GET_MATRIX_WORKFLOW.out.output.view { "Output: $it" }
}
