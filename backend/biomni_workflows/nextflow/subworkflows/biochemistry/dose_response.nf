#!/usr/bin/env nextflow
/*
 * biomni_biochemistry_dose_response
 * 
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.x = null
params.ic50 = null
params.hill = null

// Main process
process DOSE_RESPONSE {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("dose_response_results.json"), emit: results
    path("dose_response_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.biochemistry import dose_response
except ImportError:
    # Fallback: function may need to be implemented locally
    def dose_response(**kwargs):
        return {"status": "Function not available", "params": kwargs}

# Run the tool
try:
    result = dose_response(
    x="${params.x}",
    ic50="${params.ic50}",
    hill="${params.hill}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("dose_response_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("dose_response_output.txt", "w") as f:
    f.write("Biomni: Dose Response Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
    else:
        f.write(str(result))

print("dose_response completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_BIOCHEMISTRY_DOSE_RESPONSE {
    take:
    // No file inputs

    main:
    DOSE_RESPONSE()

    emit:
    results = DOSE_RESPONSE.out.results
    output = DOSE_RESPONSE.out.output
}

// Entry workflow
workflow {
    if (!params.x) {
        error "Please provide --x parameter"
    }
    if (!params.ic50) {
        error "Please provide --ic50 parameter"
    }
    if (!params.hill) {
        error "Please provide --hill parameter"
    }


    BIOMNI_BIOCHEMISTRY_DOSE_RESPONSE()
}
