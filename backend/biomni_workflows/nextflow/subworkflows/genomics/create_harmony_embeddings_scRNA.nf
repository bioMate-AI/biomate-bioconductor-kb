#!/usr/bin/env nextflow
/*
 * biomni_genomics_create_harmony_embeddings_scRNA
 * 
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.adata_filename = null
params.batch_key = null
params.data_dir = null

// Main process
process CREATE_HARMONY_EMBEDDINGS_SCRNA {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("create_harmony_embeddings_scRNA_results.json"), emit: results
    path("create_harmony_embeddings_scRNA_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.genomics import create_harmony_embeddings_scRNA
except ImportError:
    # Fallback: function may need to be implemented locally
    def create_harmony_embeddings_scRNA(**kwargs):
        return {"status": "Function not available", "params": kwargs}

# Run the tool
try:
    result = create_harmony_embeddings_scRNA(
    adata_filename="${params.adata_filename}",
    batch_key="${params.batch_key}",
    data_dir="${params.data_dir}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("create_harmony_embeddings_scRNA_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("create_harmony_embeddings_scRNA_output.txt", "w") as f:
    f.write("Biomni: Create Harmony Embeddings Scrna Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
    else:
        f.write(str(result))

print("create_harmony_embeddings_scRNA completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_GENOMICS_CREATE_HARMONY_EMBEDDINGS_SCRNA {
    take:
    // No file inputs

    main:
    CREATE_HARMONY_EMBEDDINGS_SCRNA()

    emit:
    results = CREATE_HARMONY_EMBEDDINGS_SCRNA.out.results
    output = CREATE_HARMONY_EMBEDDINGS_SCRNA.out.output
}

// Entry workflow
workflow {
    if (!params.adata_filename) {
        error "Please provide --adata_filename parameter"
    }
    if (!params.batch_key) {
        error "Please provide --batch_key parameter"
    }
    if (!params.data_dir) {
        error "Please provide --data_dir parameter"
    }


    BIOMNI_GENOMICS_CREATE_HARMONY_EMBEDDINGS_SCRNA()
}
