#!/usr/bin/env nextflow
/*
 * biomni_bioimaging_calculate_similarity_metrics
 * Calculate similarity metrics between two images.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.image1 = null
params.image2 = null

// Main process
process CALCULATE_SIMILARITY_METRICS {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("calculate_similarity_metrics_results.json"), emit: results
    path("calculate_similarity_metrics_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.bioimaging import calculate_similarity_metrics

# Run the tool
try:
    result = calculate_similarity_metrics(
    image1="${params.image1}",
    image2="${params.image2}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("calculate_similarity_metrics_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("calculate_similarity_metrics_output.txt", "w") as f:
    f.write("Biomni: Calculate Similarity Metrics Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("calculate_similarity_metrics completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_BIOIMAGING_CALCULATE_SIMILARITY_METRICS {
    take:
    // No file inputs

    main:
    CALCULATE_SIMILARITY_METRICS()

    emit:
    results = CALCULATE_SIMILARITY_METRICS.out.results
    output = CALCULATE_SIMILARITY_METRICS.out.output
}

// Entry workflow
workflow {
    if (!params.image1) {
        error "Please provide --image1 parameter"
    }
    if (!params.image2) {
        error "Please provide --image2 parameter"
    }


    BIOMNI_BIOIMAGING_CALCULATE_SIMILARITY_METRICS()
}
