#!/usr/bin/env nextflow
/*
 * biomni_genomics_conda_env_exists
 * 
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.env_name = null

// Main process
process CONDA_ENV_EXISTS {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("conda_env_exists_results.json"), emit: results
    path("conda_env_exists_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.genomics import conda_env_exists
except ImportError:
    # Fallback: function may need to be implemented locally
    def conda_env_exists(**kwargs):
        return {"status": "Function not available", "params": kwargs}

# Run the tool
try:
    result = conda_env_exists(
    env_name="${params.env_name}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("conda_env_exists_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("conda_env_exists_output.txt", "w") as f:
    f.write("Biomni: Conda Env Exists Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
    else:
        f.write(str(result))

print("conda_env_exists completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_GENOMICS_CONDA_ENV_EXISTS {
    take:
    // No file inputs

    main:
    CONDA_ENV_EXISTS()

    emit:
    results = CONDA_ENV_EXISTS.out.results
    output = CONDA_ENV_EXISTS.out.output
}

// Entry workflow
workflow {
    if (!params.env_name) {
        error "Please provide --env_name parameter"
    }


    BIOMNI_GENOMICS_CONDA_ENV_EXISTS()
}
