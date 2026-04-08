#!/usr/bin/env nextflow
/*
 * genomics/annotate_celltype_scRNA
 * Annotate cell types based on gene markers and transferred labels using LLM.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Demo: PBMC 3k single-cell dataset from Galaxy test data
params.adata_filename = "${projectDir}/../../../../lib/galaxy/datatypes/test/pbmc3k_tiny.h5ad"
params.data_dir = null
params.data_info = null
params.data_lake_path = null
params.cluster = 'leiden'
params.llm = 'claude-sonnet-4-5'
params.composition = null

process ANNOTATE_CELLTYPE_SCRNA {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("annotate_celltype_scRNA_results.json"), emit: results
    tuple val(meta), path("annotate_celltype_scRNA_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Disable numba JIT to avoid caching issues in Docker containers
    export NUMBA_DISABLE_JIT=1
    export NUMBA_CACHE_DIR=/tmp/numba_cache
    mkdir -p /tmp/numba_cache

    # Export parameters as environment variables
    export PARAM_ADATA_FILENAME="${params.adata_filename?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_DATA_DIR="${params.data_dir?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_DATA_INFO="${params.data_info?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_DATA_LAKE_PATH="${params.data_lake_path?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_CLUSTER="${params.cluster?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_LLM="${params.llm?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_COMPOSITION="${params.composition?.toString()?.replace('"', '\\"') ?: 'null'}"

    python3 << 'PYEOF'
# Auto-generated from Galaxy wrapper - self-contained implementation

import json
import os

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



def annotate_celltype_scRNA(
    adata_filename,
    data_dir=None,
    data_info=None,
    data_lake_path=None,
    cluster="leiden",
    llm="claude-sonnet-4-5",
    composition=None
):
    '''Annotate cell types in single-cell RNA-seq data using cluster markers.

    This workflow loads an H5AD file, identifies marker genes per cluster,
    and provides information for cell type annotation.

    Parameters
    ----------
    adata_filename : str
        Path to the H5AD file containing single-cell data
    cluster : str
        Key in adata.obs for cluster annotations (default: "leiden")
    llm : str
        LLM model to use for annotation (demo mode: annotation not performed)

    Returns
    -------
    dict
        Cell type annotation results with cluster markers
    '''
    import scanpy as sc
    import pandas as pd
    import numpy as np

    result = {
        "status": "success",
        "adata_filename": adata_filename,
        "cluster_key": cluster,
    }

    # Load the H5AD file
    if not adata_filename or not os.path.exists(adata_filename):
        return {"status": "error", "message": f"H5AD file not found: {adata_filename}"}

    try:
        adata = sc.read_h5ad(adata_filename)
        result["n_cells"] = adata.n_obs
        result["n_genes"] = adata.n_vars
        result["obs_columns"] = list(adata.obs.columns)
        result["var_columns"] = list(adata.var.columns)

        # Check if the cluster key exists
        if cluster not in adata.obs.columns:
            # Try to find a suitable cluster column
            cluster_candidates = [c for c in adata.obs.columns if 'cluster' in c.lower() or 'leiden' in c.lower() or 'louvain' in c.lower()]
            if cluster_candidates:
                cluster = cluster_candidates[0]
                result["cluster_key_used"] = cluster
                result["cluster_key_note"] = f"Original key '{cluster}' not found, using '{cluster}'"
            else:
                result["status"] = "no_clusters"
                result["message"] = f"No cluster column found. Available: {list(adata.obs.columns)}"
                return result

        # Get cluster information
        clusters = adata.obs[cluster].unique()
        result["n_clusters"] = len(clusters)
        result["cluster_sizes"] = dict(adata.obs[cluster].value_counts())

        # Try to find marker genes
        marker_genes = {}
        if 'rank_genes_groups' in adata.uns:
            # Marker genes already computed
            result["markers_precomputed"] = True
            groups = adata.uns['rank_genes_groups']['names'].dtype.names
            for group in groups[:5]:  # Top 5 clusters
                top_genes = list(adata.uns['rank_genes_groups']['names'][group][:10])
                marker_genes[str(group)] = top_genes
        else:
            # Compute marker genes if possible
            result["markers_precomputed"] = False
            try:
                # Need normalized data
                if 'counts' in adata.layers:
                    sc.pp.normalize_total(adata, target_sum=1e4)
                    sc.pp.log1p(adata)
                sc.tl.rank_genes_groups(adata, cluster, method='wilcoxon', n_genes=10)
                groups = adata.uns['rank_genes_groups']['names'].dtype.names
                for group in list(groups)[:5]:
                    top_genes = list(adata.uns['rank_genes_groups']['names'][group][:10])
                    marker_genes[str(group)] = top_genes
                result["markers_computed"] = True
            except Exception as e:
                result["markers_computed"] = False
                result["markers_error"] = str(e)

        result["cluster_markers"] = marker_genes

        # Common marker gene annotations (for demo purposes)
        known_markers = {
            "CD3D": "T cells", "CD3E": "T cells", "CD4": "CD4+ T cells", "CD8A": "CD8+ T cells",
            "MS4A1": "B cells", "CD19": "B cells", "CD79A": "B cells",
            "CD14": "Monocytes", "LYZ": "Monocytes", "FCGR3A": "NK cells/Monocytes",
            "NKG7": "NK cells", "GNLY": "NK cells",
            "PPBP": "Platelets", "PF4": "Platelets",
            "HBA1": "Erythrocytes", "HBB": "Erythrocytes",
            "CD34": "HSCs/Progenitors",
        }

        # Suggest cell types based on marker overlap
        suggested_annotations = {}
        for cluster_id, genes in marker_genes.items():
            matches = []
            for gene in genes:
                gene_upper = gene.upper() if isinstance(gene, str) else str(gene)
                if gene_upper in known_markers:
                    matches.append(f"{gene}: {known_markers[gene_upper]}")
            if matches:
                suggested_annotations[cluster_id] = matches

        result["suggested_annotations"] = suggested_annotations
        result["note"] = (
            "Demo mode: LLM annotation not performed. "
            "Suggestions based on known marker gene database. "
            f"LLM model specified: {llm}"
        )

    except Exception as e:
        result["status"] = "error"
        result["message"] = str(e)

    return result

# Execute the function
try:
    result = annotate_celltype_scRNA(
        adata_filename=auto_convert(os.environ.get("PARAM_ADATA_FILENAME", "")),
        data_dir=auto_convert(os.environ.get("PARAM_DATA_DIR", None)),
        data_info=auto_convert(os.environ.get("PARAM_DATA_INFO", None)),
        data_lake_path=auto_convert(os.environ.get("PARAM_DATA_LAKE_PATH", None)),
        cluster=auto_convert(os.environ.get("PARAM_CLUSTER", "leiden")) or "leiden",
        llm=auto_convert(os.environ.get("PARAM_LLM", "claude-sonnet-4-5")) or "claude-sonnet-4-5",
        composition=auto_convert(os.environ.get("PARAM_COMPOSITION", None)),
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
    "function": "annotate_celltype_scRNA",
    "domain": "genomics",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("annotate_celltype_scRNA_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("annotate_celltype_scRNA_output.txt", "w") as f:
    f.write("Biomni: Annotate Celltype Scrna" + NL)
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
        biomni_function: "annotate_celltype_scRNA"
    END_VERSIONS
    """
}

workflow ANNOTATE_CELLTYPE_SCRNA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    ANNOTATE_CELLTYPE_SCRNA(ch_input)

    emit:
    results = ANNOTATE_CELLTYPE_SCRNA.out.results
    output = ANNOTATE_CELLTYPE_SCRNA.out.output
    versions = ANNOTATE_CELLTYPE_SCRNA.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    ANNOTATE_CELLTYPE_SCRNA_WORKFLOW(ch_input)

    ANNOTATE_CELLTYPE_SCRNA_WORKFLOW.out.output.view { "Output: $it" }
}
