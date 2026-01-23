#!/usr/bin/env nextflow
/*
 * biomni_pharmacology_analyze_western_blot
 * Performs densitometric analysis of Western blot images to quantify relative protein expression.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.blot_image_path = null
params.target_bands = null
params.loading_control_band = null
params.antibody_info = null
params.output_dir = './results'

// Main process
process ANALYZE_WESTERN_BLOT {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("analyze_western_blot_results.json"), emit: results
    path("analyze_western_blot_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.pharmacology import analyze_western_blot

# Run the tool
try:
    result = analyze_western_blot(
    blot_image_path="${params.blot_image_path}",
    target_bands="${params.target_bands}",
    loading_control_band="${params.loading_control_band}",
    antibody_info="${params.antibody_info}",
    output_dir="${params.output_dir}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("analyze_western_blot_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("analyze_western_blot_output.txt", "w") as f:
    f.write("Biomni: Analyze Western Blot Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("analyze_western_blot completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_PHARMACOLOGY_ANALYZE_WESTERN_BLOT {
    take:
    // No file inputs

    main:
    ANALYZE_WESTERN_BLOT()

    emit:
    results = ANALYZE_WESTERN_BLOT.out.results
    output = ANALYZE_WESTERN_BLOT.out.output
}

// Entry workflow
workflow {
    if (!params.blot_image_path) {
        error "Please provide --blot_image_path parameter"
    }
    if (!params.target_bands) {
        error "Please provide --target_bands parameter"
    }
    if (!params.loading_control_band) {
        error "Please provide --loading_control_band parameter"
    }
    if (!params.antibody_info) {
        error "Please provide --antibody_info parameter"
    }


    BIOMNI_PHARMACOLOGY_ANALYZE_WESTERN_BLOT()
}
