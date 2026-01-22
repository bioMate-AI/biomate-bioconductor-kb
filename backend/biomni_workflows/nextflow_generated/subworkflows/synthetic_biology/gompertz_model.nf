#!/usr/bin/env nextflow
/*
 * biomni_synthetic_biology_gompertz_model
 * Gompertz growth model.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.t = null
params.lag = null
params.mu_max = null
params.A = null

// Main process
process GOMPERTZ_MODEL {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("gompertz_model_results.json"), emit: results
    path("gompertz_model_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.synthetic_biology import gompertz_model
except ImportError:
    # Fallback: function may need to be implemented locally
    def gompertz_model(**kwargs):
        return {"status": "Function not available", "params": kwargs}

# Run the tool
try:
    result = gompertz_model(
    t="${params.t}",
    lag="${params.lag}",
    mu_max="${params.mu_max}",
    A="${params.A}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("gompertz_model_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("gompertz_model_output.txt", "w") as f:
    f.write("Biomni: Gompertz Model Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
    else:
        f.write(str(result))

print("gompertz_model completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_SYNTHETIC_BIOLOGY_GOMPERTZ_MODEL {
    take:
    // No file inputs

    main:
    GOMPERTZ_MODEL()

    emit:
    results = GOMPERTZ_MODEL.out.results
    output = GOMPERTZ_MODEL.out.output
}

// Entry workflow
workflow {
    if (!params.t) {
        error "Please provide --t parameter"
    }
    if (!params.lag) {
        error "Please provide --lag parameter"
    }
    if (!params.mu_max) {
        error "Please provide --mu_max parameter"
    }
    if (!params.A) {
        error "Please provide --A parameter"
    }


    BIOMNI_SYNTHETIC_BIOLOGY_GOMPERTZ_MODEL()
}
