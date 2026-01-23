#!/usr/bin/env nextflow
/*
 * biomni_pharmacology_sigmoid
 * 
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.x = null

// Main process
process SIGMOID {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("sigmoid_results.json"), emit: results
    path("sigmoid_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.pharmacology import sigmoid

# Run the tool
try:
    result = sigmoid(
    x="${params.x}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("sigmoid_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("sigmoid_output.txt", "w") as f:
    f.write("Biomni: Sigmoid Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("sigmoid completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_PHARMACOLOGY_SIGMOID {
    take:
    // No file inputs

    main:
    SIGMOID()

    emit:
    results = SIGMOID.out.results
    output = SIGMOID.out.output
}

// Entry workflow
workflow {
    if (!params.x) {
        error "Please provide --x parameter"
    }


    BIOMNI_PHARMACOLOGY_SIGMOID()
}
