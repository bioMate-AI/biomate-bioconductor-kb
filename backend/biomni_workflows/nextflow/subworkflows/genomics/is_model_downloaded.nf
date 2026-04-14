#!/usr/bin/env nextflow
/*
 * biomni_genomics_is_model_downloaded
 * Check if model is already downloaded by looking for key files
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.checkpoint_path = null
params.model_type = null

// Main process
process IS_MODEL_DOWNLOADED {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("is_model_downloaded_results.json"), emit: results
    path("is_model_downloaded_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.genomics import is_model_downloaded

# Run the tool
try:
    result = is_model_downloaded(
    checkpoint_path="${params.checkpoint_path}",
    model_type="${params.model_type}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("is_model_downloaded_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("is_model_downloaded_output.txt", "w") as f:
    f.write("Biomni: Is Model Downloaded Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("is_model_downloaded completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_GENOMICS_IS_MODEL_DOWNLOADED {
    take:
    // No file inputs

    main:
    IS_MODEL_DOWNLOADED()

    emit:
    results = IS_MODEL_DOWNLOADED.out.results
    output = IS_MODEL_DOWNLOADED.out.output
}

// Entry workflow
workflow {
    if (!params.checkpoint_path) {
        error "Please provide --checkpoint_path parameter"
    }
    if (!params.model_type) {
        error "Please provide --model_type parameter"
    }


    BIOMNI_GENOMICS_IS_MODEL_DOWNLOADED()
}
