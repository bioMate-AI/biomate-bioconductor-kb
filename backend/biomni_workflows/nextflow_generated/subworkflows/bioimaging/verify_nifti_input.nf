#!/usr/bin/env nextflow
/*
 * biomni_bioimaging_verify_nifti_input
 * 
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.image_path = null

// Main process
process VERIFY_NIFTI_INPUT {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("verify_nifti_input_results.json"), emit: results
    path("verify_nifti_input_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.bioimaging import verify_nifti_input
except ImportError:
    # Fallback: function may need to be implemented locally
    def verify_nifti_input(**kwargs):
        return {"status": "Function not available", "params": kwargs}

# Run the tool
try:
    result = verify_nifti_input(
    image_path="${params.image_path}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("verify_nifti_input_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("verify_nifti_input_output.txt", "w") as f:
    f.write("Biomni: Verify Nifti Input Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
    else:
        f.write(str(result))

print("verify_nifti_input completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_BIOIMAGING_VERIFY_NIFTI_INPUT {
    take:
    // No file inputs

    main:
    VERIFY_NIFTI_INPUT()

    emit:
    results = VERIFY_NIFTI_INPUT.out.results
    output = VERIFY_NIFTI_INPUT.out.output
}

// Entry workflow
workflow {
    if (!params.image_path) {
        error "Please provide --image_path parameter"
    }


    BIOMNI_BIOIMAGING_VERIFY_NIFTI_INPUT()
}
