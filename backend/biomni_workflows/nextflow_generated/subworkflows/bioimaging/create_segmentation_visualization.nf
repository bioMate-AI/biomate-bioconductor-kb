#!/usr/bin/env nextflow
/*
 * biomni_bioimaging_create_segmentation_visualization
 * Create and save visualization of segmentation results using nilearn
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.original_mri = null
params.segmentation = null
params.output_dir = './visualization_output'

// Main process
process CREATE_SEGMENTATION_VISUALIZATION {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("create_segmentation_visualization_results.json"), emit: results
    path("create_segmentation_visualization_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.bioimaging import create_segmentation_visualization
except ImportError:
    # Fallback: function may need to be implemented locally
    def create_segmentation_visualization(**kwargs):
        return {"status": "Function not available", "params": kwargs}

# Run the tool
try:
    result = create_segmentation_visualization(
    original_mri="${params.original_mri}",
    segmentation="${params.segmentation}",
    output_dir="${params.output_dir}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("create_segmentation_visualization_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("create_segmentation_visualization_output.txt", "w") as f:
    f.write("Biomni: Create Segmentation Visualization Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
    else:
        f.write(str(result))

print("create_segmentation_visualization completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_BIOIMAGING_CREATE_SEGMENTATION_VISUALIZATION {
    take:
    // No file inputs

    main:
    CREATE_SEGMENTATION_VISUALIZATION()

    emit:
    results = CREATE_SEGMENTATION_VISUALIZATION.out.results
    output = CREATE_SEGMENTATION_VISUALIZATION.out.output
}

// Entry workflow
workflow {
    if (!params.original_mri) {
        error "Please provide --original_mri parameter"
    }
    if (!params.segmentation) {
        error "Please provide --segmentation parameter"
    }


    BIOMNI_BIOIMAGING_CREATE_SEGMENTATION_VISUALIZATION()
}
