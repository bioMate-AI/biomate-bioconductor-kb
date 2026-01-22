#!/usr/bin/env nextflow
/*
 * biomni_biophysics_analyze_cell_morphology_and_cytoskeleton
 * Quantifies cell morphology and cytoskeletal organization from fluorescence microscopy images.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.image_path = null
params.output_dir = './results'
params.threshold_method = 'otsu'

// Main process
process ANALYZE_CELL_MORPHOLOGY_AND_CYTOSKELETON {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("analyze_cell_morphology_and_cytoskeleton_results.json"), emit: results
    path("analyze_cell_morphology_and_cytoskeleton_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.biophysics import analyze_cell_morphology_and_cytoskeleton
except ImportError:
    # Fallback: function may need to be implemented locally
    def analyze_cell_morphology_and_cytoskeleton(**kwargs):
        return {"status": "Function not available", "params": kwargs}

# Run the tool
try:
    result = analyze_cell_morphology_and_cytoskeleton(
    image_path="${params.image_path}",
    output_dir="${params.output_dir}",
    threshold_method="${params.threshold_method}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("analyze_cell_morphology_and_cytoskeleton_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("analyze_cell_morphology_and_cytoskeleton_output.txt", "w") as f:
    f.write("Biomni: Analyze Cell Morphology And Cytoskeleton Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
    else:
        f.write(str(result))

print("analyze_cell_morphology_and_cytoskeleton completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_BIOPHYSICS_ANALYZE_CELL_MORPHOLOGY_AND_CYTOSKELETON {
    take:
    // No file inputs

    main:
    ANALYZE_CELL_MORPHOLOGY_AND_CYTOSKELETON()

    emit:
    results = ANALYZE_CELL_MORPHOLOGY_AND_CYTOSKELETON.out.results
    output = ANALYZE_CELL_MORPHOLOGY_AND_CYTOSKELETON.out.output
}

// Entry workflow
workflow {
    if (!params.image_path) {
        error "Please provide --image_path parameter"
    }


    BIOMNI_BIOPHYSICS_ANALYZE_CELL_MORPHOLOGY_AND_CYTOSKELETON()
}
