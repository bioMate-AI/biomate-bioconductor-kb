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

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("conda_env_exists_results.json"), emit: results
    path("conda_env_exists_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.genomics import conda_env_exists

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
NL = chr(10)
with open("conda_env_exists_output.txt", "w") as f:
    f.write("Biomni: Conda Env Exists Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
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
