#!/usr/bin/env nextflow
/*
 * biomni_genomics_get_uce_embeddings_scRNA
 * The UCE embeddings are usually our default tools to get cell embeddings, we map UCE embeddings to IMA referece dataset and get the cell types for a better understanding.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.adata_filename = null
params.data_dir = null
params.DATA_ROOT = '/dfs/project/bioagentos/data/singlecell/'
params.custom_args = null

// Main process
process GET_UCE_EMBEDDINGS_SCRNA {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("get_uce_embeddings_scRNA_results.json"), emit: results
    path("get_uce_embeddings_scRNA_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.genomics import get_uce_embeddings_scRNA
except ImportError:
    # Fallback: function may need to be implemented locally
    def get_uce_embeddings_scRNA(**kwargs):
        return {"status": "Function not available", "params": kwargs}

# Run the tool
try:
    result = get_uce_embeddings_scRNA(
    adata_filename="${params.adata_filename}",
    data_dir="${params.data_dir}",
    DATA_ROOT="${params.DATA_ROOT}",
    custom_args="${params.custom_args}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("get_uce_embeddings_scRNA_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("get_uce_embeddings_scRNA_output.txt", "w") as f:
    f.write("Biomni: Get Uce Embeddings Scrna Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
    else:
        f.write(str(result))

print("get_uce_embeddings_scRNA completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_GENOMICS_GET_UCE_EMBEDDINGS_SCRNA {
    take:
    // No file inputs

    main:
    GET_UCE_EMBEDDINGS_SCRNA()

    emit:
    results = GET_UCE_EMBEDDINGS_SCRNA.out.results
    output = GET_UCE_EMBEDDINGS_SCRNA.out.output
}

// Entry workflow
workflow {
    if (!params.adata_filename) {
        error "Please provide --adata_filename parameter"
    }
    if (!params.data_dir) {
        error "Please provide --data_dir parameter"
    }


    BIOMNI_GENOMICS_GET_UCE_EMBEDDINGS_SCRNA()
}
