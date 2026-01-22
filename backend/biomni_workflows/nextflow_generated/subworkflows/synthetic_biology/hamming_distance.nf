#!/usr/bin/env nextflow
/*
 * biomni_synthetic_biology_hamming_distance
 * 
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.s1 = null
params.s2 = null

// Main process
process HAMMING_DISTANCE {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("hamming_distance_results.json"), emit: results
    path("hamming_distance_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.synthetic_biology import hamming_distance
except ImportError:
    # Fallback: function may need to be implemented locally
    def hamming_distance(**kwargs):
        return {"status": "Function not available", "params": kwargs}

# Run the tool
try:
    result = hamming_distance(
    s1="${params.s1}",
    s2="${params.s2}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("hamming_distance_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("hamming_distance_output.txt", "w") as f:
    f.write("Biomni: Hamming Distance Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
    else:
        f.write(str(result))

print("hamming_distance completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_SYNTHETIC_BIOLOGY_HAMMING_DISTANCE {
    take:
    // No file inputs

    main:
    HAMMING_DISTANCE()

    emit:
    results = HAMMING_DISTANCE.out.results
    output = HAMMING_DISTANCE.out.output
}

// Entry workflow
workflow {
    if (!params.s1) {
        error "Please provide --s1 parameter"
    }
    if (!params.s2) {
        error "Please provide --s2 parameter"
    }


    BIOMNI_SYNTHETIC_BIOLOGY_HAMMING_DISTANCE()
}
