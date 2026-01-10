#!/usr/bin/env nextflow
/*
 * biomni_physiology_reconstruct_3d_face_from_mri
 * Generate a 3D model of facial anatomy from MRI scans of the head and neck.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.mri_file_path = null

// Processes
process RECONSTRUCT_3D_FACE_FROM_MRI {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(mri_file_path)

    output:
    path("reconstruct_3d_face_from_mri_output.txt"), emit: output

    script:
    """
    # Tool: biomni_physiology_reconstruct_3d_face_from_mri
    # Runs in unified Docker container
    echo 'Running RECONSTRUCT_3D_FACE_FROM_MRI'
        touch reconstruct_3d_face_from_mri_output.txt
    """
}

process OUTPUT {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("output_output.txt"), emit: output

    script:
    """
    # Tool: cat1
    # Runs in unified Docker container
    echo 'Running OUTPUT'
        touch output_output.txt
    """
}

workflow BIOMNI_PHYSIOLOGY_RECONSTRUCT_3D_FACE_FROM_MRI {
    main:
    ch_mri_file_path = Channel.fromPath(params.mri_file_path)

    RECONSTRUCT_3D_FACE_FROM_MRI(ch_mri_file_path)
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_PHYSIOLOGY_RECONSTRUCT_3D_FACE_FROM_MRI()
}