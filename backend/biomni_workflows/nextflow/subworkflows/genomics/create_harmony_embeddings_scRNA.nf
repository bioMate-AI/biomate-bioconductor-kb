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

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("create_harmony_embeddings_scRNA_results.json"), emit: results
    path("create_harmony_embeddings_scRNA_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.genomics import create_harmony_embeddings_scRNA

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
NL = chr(10)
with open("create_harmony_embeddings_scRNA_output.txt", "w") as f:
    f.write("Biomni: Create Harmony Embeddings Scrna Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
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
