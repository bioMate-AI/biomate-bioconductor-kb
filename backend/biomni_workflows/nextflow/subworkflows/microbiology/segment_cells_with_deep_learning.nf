#!/usr/bin/env nextflow
/*
 * biomni_microbiology_segment_cells_with_deep_learning
 * Perform cell segmentation on fluorescence microscopy images using deep learning.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.image_path = null
params.model_type = 'bact_fluor_omni'
params.diameter = null
params.save_dir = 'segmentation_results'

// Main process
process SEGMENT_CELLS_WITH_DEEP_LEARNING {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("segment_cells_with_deep_learning_results.json"), emit: results
    path("segment_cells_with_deep_learning_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.microbiology import segment_cells_with_deep_learning

# Run the tool
try:
    result = segment_cells_with_deep_learning(
    image_path="${params.image_path}",
    model_type="${params.model_type}",
    diameter="${params.diameter}",
    save_dir="${params.save_dir}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("segment_cells_with_deep_learning_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("segment_cells_with_deep_learning_output.txt", "w") as f:
    f.write("Biomni: Segment Cells With Deep Learning Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("segment_cells_with_deep_learning completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_MICROBIOLOGY_SEGMENT_CELLS_WITH_DEEP_LEARNING {
    take:
    // No file inputs

    main:
    SEGMENT_CELLS_WITH_DEEP_LEARNING()

    emit:
    results = SEGMENT_CELLS_WITH_DEEP_LEARNING.out.results
    output = SEGMENT_CELLS_WITH_DEEP_LEARNING.out.output
}

// Entry workflow
workflow {
    if (!params.image_path) {
        error "Please provide --image_path parameter"
    }


    BIOMNI_MICROBIOLOGY_SEGMENT_CELLS_WITH_DEEP_LEARNING()
}
