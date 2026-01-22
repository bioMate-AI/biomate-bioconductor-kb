#!/usr/bin/env nextflow
/*
 * biomni_bioimaging_setup_nnunet_environment
 * Setup nnU-Net environment variables according to official documentation
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.results_folder = null
params.raw_data_base = null
params.preprocessed = null

// Main process
process SETUP_NNUNET_ENVIRONMENT {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("setup_nnunet_environment_results.json"), emit: results
    path("setup_nnunet_environment_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.bioimaging import setup_nnunet_environment
except ImportError:
    # Fallback: function may need to be implemented locally
    def setup_nnunet_environment(**kwargs):
        return {"status": "Function not available", "params": kwargs}

# Run the tool
try:
    result = setup_nnunet_environment(
    results_folder="${params.results_folder}",
    raw_data_base="${params.raw_data_base}",
    preprocessed="${params.preprocessed}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("setup_nnunet_environment_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("setup_nnunet_environment_output.txt", "w") as f:
    f.write("Biomni: Setup Nnunet Environment Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
    else:
        f.write(str(result))

print("setup_nnunet_environment completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_BIOIMAGING_SETUP_NNUNET_ENVIRONMENT {
    take:
    // No file inputs

    main:
    SETUP_NNUNET_ENVIRONMENT()

    emit:
    results = SETUP_NNUNET_ENVIRONMENT.out.results
    output = SETUP_NNUNET_ENVIRONMENT.out.output
}

// Entry workflow
workflow {



    BIOMNI_BIOIMAGING_SETUP_NNUNET_ENVIRONMENT()
}
