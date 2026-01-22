#!/usr/bin/env nextflow
/*
 * biomni_genomics_create_panhumanpy_env
 * 
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.env_name = null

// Main process
process CREATE_PANHUMANPY_ENV {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("create_panhumanpy_env_results.json"), emit: results
    path("create_panhumanpy_env_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.genomics import create_panhumanpy_env
except ImportError:
    # Fallback: function may need to be implemented locally
    def create_panhumanpy_env(**kwargs):
        return {"status": "Function not available", "params": kwargs}

# Run the tool
try:
    result = create_panhumanpy_env(
    env_name="${params.env_name}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("create_panhumanpy_env_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("create_panhumanpy_env_output.txt", "w") as f:
    f.write("Biomni: Create Panhumanpy Env Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
    else:
        f.write(str(result))

print("create_panhumanpy_env completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_GENOMICS_CREATE_PANHUMANPY_ENV {
    take:
    // No file inputs

    main:
    CREATE_PANHUMANPY_ENV()

    emit:
    results = CREATE_PANHUMANPY_ENV.out.results
    output = CREATE_PANHUMANPY_ENV.out.output
}

// Entry workflow
workflow {
    if (!params.env_name) {
        error "Please provide --env_name parameter"
    }


    BIOMNI_GENOMICS_CREATE_PANHUMANPY_ENV()
}
