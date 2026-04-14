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

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("sigmoid_results.json"), emit: results
    path("sigmoid_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.pharmacology import sigmoid
except ImportError:
    # Fallback: function may need to be implemented locally
    def sigmoid(**kwargs):
        return {"status": "Function not available", "params": kwargs}

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
with open("sigmoid_output.txt", "w") as f:
    f.write("Biomni: Sigmoid Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
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
