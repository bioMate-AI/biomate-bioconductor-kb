#!/usr/bin/env nextflow
/*
 * biomni_physiology_reconstruct_3d_face_from_mri
 * Generate a 3D model of facial anatomy from MRI scans of the head and neck.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.mri_file_path = null
params.output_dir = './output'
params.subject_id = 'subject'
params.threshold_value = '300'

// Main process
process RECONSTRUCT_3D_FACE_FROM_MRI {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("reconstruct_3d_face_from_mri_results.json"), emit: results
    path("reconstruct_3d_face_from_mri_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.physiology import reconstruct_3d_face_from_mri

# Run the tool
try:
    result = reconstruct_3d_face_from_mri(
    mri_file_path="${params.mri_file_path}",
    output_dir="${params.output_dir}",
    subject_id="${params.subject_id}",
    threshold_value="${params.threshold_value}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("reconstruct_3d_face_from_mri_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("reconstruct_3d_face_from_mri_output.txt", "w") as f:
    f.write("Biomni: Reconstruct 3D Face From Mri Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("reconstruct_3d_face_from_mri completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_PHYSIOLOGY_RECONSTRUCT_3D_FACE_FROM_MRI {
    take:
    // No file inputs

    main:
    RECONSTRUCT_3D_FACE_FROM_MRI()

    emit:
    results = RECONSTRUCT_3D_FACE_FROM_MRI.out.results
    output = RECONSTRUCT_3D_FACE_FROM_MRI.out.output
}

// Entry workflow
workflow {
    if (!params.mri_file_path) {
        error "Please provide --mri_file_path parameter"
    }


    BIOMNI_PHYSIOLOGY_RECONSTRUCT_3D_FACE_FROM_MRI()
}
