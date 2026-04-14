#!/usr/bin/env nextflow
/*
 * biomni_pathology_quantify_corneal_nerve_fibers
 * Quantify the volume/density of immunofluorescence-labeled corneal nerve fibers.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.image_path = null
params.marker_type = null
params.output_dir = './output'
params.threshold_method = 'otsu'

// Main process
process QUANTIFY_CORNEAL_NERVE_FIBERS {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("quantify_corneal_nerve_fibers_results.json"), emit: results
    path("quantify_corneal_nerve_fibers_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.pathology import quantify_corneal_nerve_fibers

# Run the tool
try:
    result = quantify_corneal_nerve_fibers(
    image_path="${params.image_path}",
    marker_type="${params.marker_type}",
    output_dir="${params.output_dir}",
    threshold_method="${params.threshold_method}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("quantify_corneal_nerve_fibers_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("quantify_corneal_nerve_fibers_output.txt", "w") as f:
    f.write("Biomni: Quantify Corneal Nerve Fibers Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("quantify_corneal_nerve_fibers completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_PATHOLOGY_QUANTIFY_CORNEAL_NERVE_FIBERS {
    take:
    // No file inputs

    main:
    QUANTIFY_CORNEAL_NERVE_FIBERS()

    emit:
    results = QUANTIFY_CORNEAL_NERVE_FIBERS.out.results
    output = QUANTIFY_CORNEAL_NERVE_FIBERS.out.output
}

// Entry workflow
workflow {
    if (!params.image_path) {
        error "Please provide --image_path parameter"
    }
    if (!params.marker_type) {
        error "Please provide --marker_type parameter"
    }


    BIOMNI_PATHOLOGY_QUANTIFY_CORNEAL_NERVE_FIBERS()
}
