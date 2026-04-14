#!/usr/bin/env nextflow
/*
 * biomni_pathology_analyze_bone_microct_morphometry
 * Analyze bone microarchitecture parameters from 3D micro-CT images.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.input_file_path = null
params.output_dir = './results'
params.threshold_value = null

// Main process
process ANALYZE_BONE_MICROCT_MORPHOMETRY {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("analyze_bone_microct_morphometry_results.json"), emit: results
    path("analyze_bone_microct_morphometry_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.pathology import analyze_bone_microct_morphometry

# Run the tool
try:
    result = analyze_bone_microct_morphometry(
    input_file_path="${params.input_file_path}",
    output_dir="${params.output_dir}",
    threshold_value="${params.threshold_value}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("analyze_bone_microct_morphometry_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("analyze_bone_microct_morphometry_output.txt", "w") as f:
    f.write("Biomni: Analyze Bone Microct Morphometry Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("analyze_bone_microct_morphometry completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_PATHOLOGY_ANALYZE_BONE_MICROCT_MORPHOMETRY {
    take:
    // No file inputs

    main:
    ANALYZE_BONE_MICROCT_MORPHOMETRY()

    emit:
    results = ANALYZE_BONE_MICROCT_MORPHOMETRY.out.results
    output = ANALYZE_BONE_MICROCT_MORPHOMETRY.out.output
}

// Entry workflow
workflow {
    if (!params.input_file_path) {
        error "Please provide --input_file_path parameter"
    }


    BIOMNI_PATHOLOGY_ANALYZE_BONE_MICROCT_MORPHOMETRY()
}
