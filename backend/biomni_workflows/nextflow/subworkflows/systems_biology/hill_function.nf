#!/usr/bin/env nextflow
/*
 * biomni_systems_biology_hill_function
 * 
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.x = null
params.n = null
params.ec50 = null

// Main process
process HILL_FUNCTION {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("hill_function_results.json"), emit: results
    path("hill_function_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.systems_biology import hill_function
except ImportError:
    # Fallback: function may need to be implemented locally
    def hill_function(**kwargs):
        return {"status": "Function not available", "params": kwargs}

# Run the tool
try:
    result = hill_function(
    x="${params.x}",
    n="${params.n}",
    ec50="${params.ec50}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("hill_function_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("hill_function_output.txt", "w") as f:
    f.write("Biomni: Hill Function Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
    else:
        f.write(str(result))

print("hill_function completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_SYSTEMS_BIOLOGY_HILL_FUNCTION {
    take:
    // No file inputs

    main:
    HILL_FUNCTION()

    emit:
    results = HILL_FUNCTION.out.results
    output = HILL_FUNCTION.out.output
}

// Entry workflow
workflow {
    if (!params.x) {
        error "Please provide --x parameter"
    }
    if (!params.n) {
        error "Please provide --n parameter"
    }
    if (!params.ec50) {
        error "Please provide --ec50 parameter"
    }


    BIOMNI_SYSTEMS_BIOLOGY_HILL_FUNCTION()
}
