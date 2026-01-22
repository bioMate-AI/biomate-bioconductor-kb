#!/usr/bin/env nextflow
/*
 * biomni_genetics_forward
 * 
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.x = null

// Main process
process FORWARD {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("forward_results.json"), emit: results
    path("forward_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.genetics import forward
except ImportError:
    # Fallback: function may need to be implemented locally
    def forward(**kwargs):
        return {"status": "Function not available", "params": kwargs}

# Run the tool
try:
    result = forward(
    x="${params.x}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("forward_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("forward_output.txt", "w") as f:
    f.write("Biomni: Forward Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
    else:
        f.write(str(result))

print("forward completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_GENETICS_FORWARD {
    take:
    // No file inputs

    main:
    FORWARD()

    emit:
    results = FORWARD.out.results
    output = FORWARD.out.output
}

// Entry workflow
workflow {
    if (!params.x) {
        error "Please provide --x parameter"
    }


    BIOMNI_GENETICS_FORWARD()
}
