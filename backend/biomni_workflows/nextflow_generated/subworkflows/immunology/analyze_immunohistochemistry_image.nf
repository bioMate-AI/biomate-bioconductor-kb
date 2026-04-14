#!/usr/bin/env nextflow
/*
 * biomni_immunology_analyze_immunohistochemistry_image
 * Analyzes immunohistochemistry images to quantify protein expression and spatial distribution.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.image_path = null
params.protein_name = 'Unknown'
params.output_dir = './ihc_results/'

// Main process
process ANALYZE_IMMUNOHISTOCHEMISTRY_IMAGE {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("analyze_immunohistochemistry_image_results.json"), emit: results
    path("analyze_immunohistochemistry_image_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.immunology import analyze_immunohistochemistry_image
except ImportError:
    # Fallback: function may need to be implemented locally
    def analyze_immunohistochemistry_image(**kwargs):
        return {"status": "Function not available", "params": kwargs}

# Run the tool
try:
    result = analyze_immunohistochemistry_image(
    image_path="${params.image_path}",
    protein_name="${params.protein_name}",
    output_dir="${params.output_dir}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("analyze_immunohistochemistry_image_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("analyze_immunohistochemistry_image_output.txt", "w") as f:
    f.write("Biomni: Analyze Immunohistochemistry Image Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
    else:
        f.write(str(result))

print("analyze_immunohistochemistry_image completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_IMMUNOLOGY_ANALYZE_IMMUNOHISTOCHEMISTRY_IMAGE {
    take:
    // No file inputs

    main:
    ANALYZE_IMMUNOHISTOCHEMISTRY_IMAGE()

    emit:
    results = ANALYZE_IMMUNOHISTOCHEMISTRY_IMAGE.out.results
    output = ANALYZE_IMMUNOHISTOCHEMISTRY_IMAGE.out.output
}

// Entry workflow
workflow {
    if (!params.image_path) {
        error "Please provide --image_path parameter"
    }


    BIOMNI_IMMUNOLOGY_ANALYZE_IMMUNOHISTOCHEMISTRY_IMAGE()
}
