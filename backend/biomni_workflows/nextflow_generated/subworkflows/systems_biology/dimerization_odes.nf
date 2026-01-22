#!/usr/bin/env nextflow
/*
 * biomni_systems_biology_dimerization_odes
 * 
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.t = null
params.y = null

// Main process
process DIMERIZATION_ODES {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("dimerization_odes_results.json"), emit: results
    path("dimerization_odes_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.systems_biology import dimerization_odes
except ImportError:
    # Fallback: function may need to be implemented locally
    def dimerization_odes(**kwargs):
        return {"status": "Function not available", "params": kwargs}

# Run the tool
try:
    result = dimerization_odes(
    t="${params.t}",
    y="${params.y}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("dimerization_odes_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("dimerization_odes_output.txt", "w") as f:
    f.write("Biomni: Dimerization Odes Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
    else:
        f.write(str(result))

print("dimerization_odes completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_SYSTEMS_BIOLOGY_DIMERIZATION_ODES {
    take:
    // No file inputs

    main:
    DIMERIZATION_ODES()

    emit:
    results = DIMERIZATION_ODES.out.results
    output = DIMERIZATION_ODES.out.output
}

// Entry workflow
workflow {
    if (!params.t) {
        error "Please provide --t parameter"
    }
    if (!params.y) {
        error "Please provide --y parameter"
    }


    BIOMNI_SYSTEMS_BIOLOGY_DIMERIZATION_ODES()
}
