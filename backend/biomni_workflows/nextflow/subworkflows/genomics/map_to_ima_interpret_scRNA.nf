#!/usr/bin/env nextflow
/*
 * biomni_genomics_map_to_ima_interpret_scRNA
 * Map cell embeddings from the input dataset to the Integrated Megascale Atlas reference dataset using UCE embeddings.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.adata_filename = null
params.data_dir = null
params.custom_args = null

// Main process
process MAP_TO_IMA_INTERPRET_SCRNA {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("map_to_ima_interpret_scRNA_results.json"), emit: results
    path("map_to_ima_interpret_scRNA_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.genomics import map_to_ima_interpret_scRNA

# Run the tool
try:
    result = map_to_ima_interpret_scRNA(
    adata_filename="${params.adata_filename}",
    data_dir="${params.data_dir}",
    custom_args="${params.custom_args}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("map_to_ima_interpret_scRNA_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("map_to_ima_interpret_scRNA_output.txt", "w") as f:
    f.write("Biomni: Map To Ima Interpret Scrna Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("map_to_ima_interpret_scRNA completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_GENOMICS_MAP_TO_IMA_INTERPRET_SCRNA {
    take:
    // No file inputs

    main:
    MAP_TO_IMA_INTERPRET_SCRNA()

    emit:
    results = MAP_TO_IMA_INTERPRET_SCRNA.out.results
    output = MAP_TO_IMA_INTERPRET_SCRNA.out.output
}

// Entry workflow
workflow {
    if (!params.adata_filename) {
        error "Please provide --adata_filename parameter"
    }
    if (!params.data_dir) {
        error "Please provide --data_dir parameter"
    }


    BIOMNI_GENOMICS_MAP_TO_IMA_INTERPRET_SCRNA()
}
