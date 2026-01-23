#!/usr/bin/env nextflow
/*
 * biomni_microbiology_segment_and_analyze_microbial_cells
 * Perform automated cell segmentation and quantify morphological metrics from fluorescence microscopy images.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.image_path = null
params.output_dir = './output'
params.min_cell_size = '50'

// Main process
process SEGMENT_AND_ANALYZE_MICROBIAL_CELLS {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("segment_and_analyze_microbial_cells_results.json"), emit: results
    path("segment_and_analyze_microbial_cells_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.microbiology import segment_and_analyze_microbial_cells

# Run the tool
try:
    result = segment_and_analyze_microbial_cells(
    image_path="${params.image_path}",
    output_dir="${params.output_dir}",
    min_cell_size="${params.min_cell_size}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("segment_and_analyze_microbial_cells_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("segment_and_analyze_microbial_cells_output.txt", "w") as f:
    f.write("Biomni: Segment And Analyze Microbial Cells Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("segment_and_analyze_microbial_cells completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_MICROBIOLOGY_SEGMENT_AND_ANALYZE_MICROBIAL_CELLS {
    take:
    // No file inputs

    main:
    SEGMENT_AND_ANALYZE_MICROBIAL_CELLS()

    emit:
    results = SEGMENT_AND_ANALYZE_MICROBIAL_CELLS.out.results
    output = SEGMENT_AND_ANALYZE_MICROBIAL_CELLS.out.output
}

// Entry workflow
workflow {
    if (!params.image_path) {
        error "Please provide --image_path parameter"
    }


    BIOMNI_MICROBIOLOGY_SEGMENT_AND_ANALYZE_MICROBIAL_CELLS()
}
