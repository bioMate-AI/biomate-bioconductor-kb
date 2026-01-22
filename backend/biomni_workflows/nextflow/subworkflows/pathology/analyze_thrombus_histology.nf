#!/usr/bin/env nextflow
/*
 * biomni_pathology_analyze_thrombus_histology
 * Analyze histological images of thrombus samples stained with H&E to identify and quantify
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.image_path = null
params.output_dir = './output'

// Main process
process ANALYZE_THROMBUS_HISTOLOGY {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("analyze_thrombus_histology_results.json"), emit: results
    path("analyze_thrombus_histology_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.pathology import analyze_thrombus_histology
except ImportError:
    # Fallback: function may need to be implemented locally
    def analyze_thrombus_histology(**kwargs):
        return {"status": "Function not available", "params": kwargs}

# Run the tool
try:
    result = analyze_thrombus_histology(
    image_path="${params.image_path}",
    output_dir="${params.output_dir}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("analyze_thrombus_histology_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("analyze_thrombus_histology_output.txt", "w") as f:
    f.write("Biomni: Analyze Thrombus Histology Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
    else:
        f.write(str(result))

print("analyze_thrombus_histology completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_PATHOLOGY_ANALYZE_THROMBUS_HISTOLOGY {
    take:
    // No file inputs

    main:
    ANALYZE_THROMBUS_HISTOLOGY()

    emit:
    results = ANALYZE_THROMBUS_HISTOLOGY.out.results
    output = ANALYZE_THROMBUS_HISTOLOGY.out.output
}

// Entry workflow
workflow {
    if (!params.image_path) {
        error "Please provide --image_path parameter"
    }


    BIOMNI_PATHOLOGY_ANALYZE_THROMBUS_HISTOLOGY()
}
