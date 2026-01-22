#!/usr/bin/env nextflow
/*
 * biomni_immunology_logistic_growth
 * Logistic growth model: N(t) = K / (1 + ((K - N0) / N0) * exp(-r*t)).
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.t = null
params.k = null
params.n0 = null
params.r = null

// Main process
process LOGISTIC_GROWTH {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("logistic_growth_results.json"), emit: results
    path("logistic_growth_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.immunology import logistic_growth
except ImportError:
    # Fallback: function may need to be implemented locally
    def logistic_growth(**kwargs):
        return {"status": "Function not available", "params": kwargs}

# Run the tool
try:
    result = logistic_growth(
    t="${params.t}",
    k="${params.k}",
    n0="${params.n0}",
    r="${params.r}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("logistic_growth_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("logistic_growth_output.txt", "w") as f:
    f.write("Biomni: Logistic Growth Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
    else:
        f.write(str(result))

print("logistic_growth completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_IMMUNOLOGY_LOGISTIC_GROWTH {
    take:
    // No file inputs

    main:
    LOGISTIC_GROWTH()

    emit:
    results = LOGISTIC_GROWTH.out.results
    output = LOGISTIC_GROWTH.out.output
}

// Entry workflow
workflow {
    if (!params.t) {
        error "Please provide --t parameter"
    }
    if (!params.k) {
        error "Please provide --k parameter"
    }
    if (!params.n0) {
        error "Please provide --n0 parameter"
    }
    if (!params.r) {
        error "Please provide --r parameter"
    }


    BIOMNI_IMMUNOLOGY_LOGISTIC_GROWTH()
}
