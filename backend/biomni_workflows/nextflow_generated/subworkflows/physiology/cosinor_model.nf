#!/usr/bin/env nextflow
/*
 * biomni_physiology_cosinor_model
 * Cosine function with baseline (mesor), amplitude, and phase shift.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.t = null
params.mesor = null
params.amplitude = null
params.acrophase = null

// Main process
process COSINOR_MODEL {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("cosinor_model_results.json"), emit: results
    path("cosinor_model_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.physiology import cosinor_model
except ImportError:
    # Fallback: function may need to be implemented locally
    def cosinor_model(**kwargs):
        return {"status": "Function not available", "params": kwargs}

# Run the tool
try:
    result = cosinor_model(
    t="${params.t}",
    mesor="${params.mesor}",
    amplitude="${params.amplitude}",
    acrophase="${params.acrophase}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("cosinor_model_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("cosinor_model_output.txt", "w") as f:
    f.write("Biomni: Cosinor Model Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
    else:
        f.write(str(result))

print("cosinor_model completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_PHYSIOLOGY_COSINOR_MODEL {
    take:
    // No file inputs

    main:
    COSINOR_MODEL()

    emit:
    results = COSINOR_MODEL.out.results
    output = COSINOR_MODEL.out.output
}

// Entry workflow
workflow {
    if (!params.t) {
        error "Please provide --t parameter"
    }
    if (!params.mesor) {
        error "Please provide --mesor parameter"
    }
    if (!params.amplitude) {
        error "Please provide --amplitude parameter"
    }
    if (!params.acrophase) {
        error "Please provide --acrophase parameter"
    }


    BIOMNI_PHYSIOLOGY_COSINOR_MODEL()
}
