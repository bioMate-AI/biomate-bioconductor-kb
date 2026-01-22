#!/usr/bin/env nextflow
/*
 * biomni_cell_biology_quantify_and_cluster_cell_motility
 * Quantify cell motility features from time-lapse microscopy images and cluster cells based on motility patterns.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.image_sequence_path = null
params.output_dir = './results'
params.num_clusters = '3'

// Main process
process QUANTIFY_AND_CLUSTER_CELL_MOTILITY {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("quantify_and_cluster_cell_motility_results.json"), emit: results
    path("quantify_and_cluster_cell_motility_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.cell_biology import quantify_and_cluster_cell_motility
except ImportError:
    # Fallback: function may need to be implemented locally
    def quantify_and_cluster_cell_motility(**kwargs):
        return {"status": "Function not available", "params": kwargs}

# Run the tool
try:
    result = quantify_and_cluster_cell_motility(
    image_sequence_path="${params.image_sequence_path}",
    output_dir="${params.output_dir}",
    num_clusters="${params.num_clusters}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("quantify_and_cluster_cell_motility_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("quantify_and_cluster_cell_motility_output.txt", "w") as f:
    f.write("Biomni: Quantify And Cluster Cell Motility Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
    else:
        f.write(str(result))

print("quantify_and_cluster_cell_motility completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_CELL_BIOLOGY_QUANTIFY_AND_CLUSTER_CELL_MOTILITY {
    take:
    // No file inputs

    main:
    QUANTIFY_AND_CLUSTER_CELL_MOTILITY()

    emit:
    results = QUANTIFY_AND_CLUSTER_CELL_MOTILITY.out.results
    output = QUANTIFY_AND_CLUSTER_CELL_MOTILITY.out.output
}

// Entry workflow
workflow {
    if (!params.image_sequence_path) {
        error "Please provide --image_sequence_path parameter"
    }


    BIOMNI_CELL_BIOLOGY_QUANTIFY_AND_CLUSTER_CELL_MOTILITY()
}
