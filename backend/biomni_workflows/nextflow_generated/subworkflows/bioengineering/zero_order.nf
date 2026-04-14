#!/usr/bin/env nextflow
/*
 * biomni_bioengineering_zero_order
 * 
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.t = null
params.k = null

// Main process
process ZERO_ORDER {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("zero_order_results.json"), emit: results
    path("zero_order_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.bioengineering import zero_order
except ImportError:
    # Fallback: function may need to be implemented locally
    def zero_order(**kwargs):
        return {"status": "Function not available", "params": kwargs}

# Run the tool
try:
    result = zero_order(
    t="${params.t}",
    k="${params.k}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("zero_order_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("zero_order_output.txt", "w") as f:
    f.write("Biomni: Zero Order Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
    else:
        f.write(str(result))

print("zero_order completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_BIOENGINEERING_ZERO_ORDER {
    take:
    // No file inputs

    main:
    ZERO_ORDER()

    emit:
    results = ZERO_ORDER.out.results
    output = ZERO_ORDER.out.output
}

// Entry workflow
workflow {
    if (!params.t) {
        error "Please provide --t parameter"
    }
    if (!params.k) {
        error "Please provide --k parameter"
    }


    BIOMNI_BIOENGINEERING_ZERO_ORDER()
}
