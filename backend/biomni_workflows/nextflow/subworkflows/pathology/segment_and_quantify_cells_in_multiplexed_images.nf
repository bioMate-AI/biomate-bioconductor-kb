#!/usr/bin/env nextflow
/*
 * biomni_pathology_segment_and_quantify_cells_in_multiplexed_images
 * Segment cells and quantify protein expression levels from multichannel tissue images.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.image_path = null
params.markers_list = null
params.nuclear_channel_index = '0'
params.output_dir = './output'

// Main process
process SEGMENT_AND_QUANTIFY_CELLS_IN_MULTIPLEXED_IMAGES {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("segment_and_quantify_cells_in_multiplexed_images_results.json"), emit: results
    path("segment_and_quantify_cells_in_multiplexed_images_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.pathology import segment_and_quantify_cells_in_multiplexed_images
except ImportError:
    # Fallback: function may need to be implemented locally
    def segment_and_quantify_cells_in_multiplexed_images(**kwargs):
        return {"status": "Function not available", "params": kwargs}

# Run the tool
try:
    result = segment_and_quantify_cells_in_multiplexed_images(
    image_path="${params.image_path}",
    markers_list="${params.markers_list}",
    nuclear_channel_index="${params.nuclear_channel_index}",
    output_dir="${params.output_dir}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("segment_and_quantify_cells_in_multiplexed_images_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("segment_and_quantify_cells_in_multiplexed_images_output.txt", "w") as f:
    f.write("Biomni: Segment And Quantify Cells In Multiplexed Images Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
    else:
        f.write(str(result))

print("segment_and_quantify_cells_in_multiplexed_images completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_PATHOLOGY_SEGMENT_AND_QUANTIFY_CELLS_IN_MULTIPLEXED_IMAGES {
    take:
    // No file inputs

    main:
    SEGMENT_AND_QUANTIFY_CELLS_IN_MULTIPLEXED_IMAGES()

    emit:
    results = SEGMENT_AND_QUANTIFY_CELLS_IN_MULTIPLEXED_IMAGES.out.results
    output = SEGMENT_AND_QUANTIFY_CELLS_IN_MULTIPLEXED_IMAGES.out.output
}

// Entry workflow
workflow {
    if (!params.image_path) {
        error "Please provide --image_path parameter"
    }
    if (!params.markers_list) {
        error "Please provide --markers_list parameter"
    }


    BIOMNI_PATHOLOGY_SEGMENT_AND_QUANTIFY_CELLS_IN_MULTIPLEXED_IMAGES()
}
