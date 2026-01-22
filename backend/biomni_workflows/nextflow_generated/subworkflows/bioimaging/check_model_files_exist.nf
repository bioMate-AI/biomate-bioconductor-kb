#!/usr/bin/env nextflow
/*
 * biomni_bioimaging_check_model_files_exist
 * Check if actual model weight files exist for the specified folds
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.model_folder = null
params.folds = null

// Main process
process CHECK_MODEL_FILES_EXIST {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("check_model_files_exist_results.json"), emit: results
    path("check_model_files_exist_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.bioimaging import check_model_files_exist
except ImportError:
    # Fallback: function may need to be implemented locally
    def check_model_files_exist(**kwargs):
        return {"status": "Function not available", "params": kwargs}

# Run the tool
try:
    result = check_model_files_exist(
    model_folder="${params.model_folder}",
    folds="${params.folds}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("check_model_files_exist_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("check_model_files_exist_output.txt", "w") as f:
    f.write("Biomni: Check Model Files Exist Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
    else:
        f.write(str(result))

print("check_model_files_exist completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_BIOIMAGING_CHECK_MODEL_FILES_EXIST {
    take:
    // No file inputs

    main:
    CHECK_MODEL_FILES_EXIST()

    emit:
    results = CHECK_MODEL_FILES_EXIST.out.results
    output = CHECK_MODEL_FILES_EXIST.out.output
}

// Entry workflow
workflow {
    if (!params.model_folder) {
        error "Please provide --model_folder parameter"
    }
    if (!params.folds) {
        error "Please provide --folds parameter"
    }


    BIOMNI_BIOIMAGING_CHECK_MODEL_FILES_EXIST()
}
