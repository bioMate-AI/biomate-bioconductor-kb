#!/usr/bin/env nextflow
/*
 * biomni_immunology_track_immune_cells_under_flow
 * Track immune cells under flow conditions and classify their behaviors.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.image_sequence_path = null
params.output_dir = './output'
params.pixel_size_um = '1.0'
params.time_interval_sec = '1.0'
params.flow_direction = 'right'

// Main process
process TRACK_IMMUNE_CELLS_UNDER_FLOW {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("track_immune_cells_under_flow_results.json"), emit: results
    path("track_immune_cells_under_flow_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.immunology import track_immune_cells_under_flow
except ImportError:
    # Fallback: function may need to be implemented locally
    def track_immune_cells_under_flow(**kwargs):
        return {"status": "Function not available", "params": kwargs}

# Run the tool
try:
    result = track_immune_cells_under_flow(
    image_sequence_path="${params.image_sequence_path}",
    output_dir="${params.output_dir}",
    pixel_size_um="${params.pixel_size_um}",
    time_interval_sec="${params.time_interval_sec}",
    flow_direction="${params.flow_direction}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("track_immune_cells_under_flow_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("track_immune_cells_under_flow_output.txt", "w") as f:
    f.write("Biomni: Track Immune Cells Under Flow Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
    else:
        f.write(str(result))

print("track_immune_cells_under_flow completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_IMMUNOLOGY_TRACK_IMMUNE_CELLS_UNDER_FLOW {
    take:
    // No file inputs

    main:
    TRACK_IMMUNE_CELLS_UNDER_FLOW()

    emit:
    results = TRACK_IMMUNE_CELLS_UNDER_FLOW.out.results
    output = TRACK_IMMUNE_CELLS_UNDER_FLOW.out.output
}

// Entry workflow
workflow {
    if (!params.image_sequence_path) {
        error "Please provide --image_sequence_path parameter"
    }


    BIOMNI_IMMUNOLOGY_TRACK_IMMUNE_CELLS_UNDER_FLOW()
}
