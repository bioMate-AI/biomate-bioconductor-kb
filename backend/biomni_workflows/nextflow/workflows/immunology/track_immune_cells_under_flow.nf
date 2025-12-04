#!/usr/bin/env nextflow
/*
 * biomni_immunology_track_immune_cells_under_flow
 * Track immune cells under flow conditions and classify their behaviors.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.image_sequence_path = null

// Processes
process STEP_1__CV2_CVTCOLOR {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_1__cv2_cvtcolor_output.txt"), emit: output

    script:
    """
    # Tool: python_cv2_cv2_cvtColor
    # Runs in unified Docker container
    echo 'Running STEP_1__CV2_CVTCOLOR'
        touch step_1__cv2_cvtcolor_output.txt
    """
}

process STEP_2__CV2_IMREAD {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_2__cv2_imread_output.txt"), emit: output

    script:
    """
    # Tool: python_cv2_cv2_imread
    # Runs in unified Docker container
    echo 'Running STEP_2__CV2_IMREAD'
        touch step_2__cv2_imread_output.txt
    """
}

process STEP_3__CV2_GAUSSIANBLUR {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_3__cv2_gaussianblur_output.txt"), emit: output

    script:
    """
    # Tool: python_cv2_cv2_GaussianBlur
    # Runs in unified Docker container
    echo 'Running STEP_3__CV2_GAUSSIANBLUR'
        touch step_3__cv2_gaussianblur_output.txt
    """
}

process STEP_4__CV2_MORPHOLOGYEX {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_4__cv2_morphologyex_output.txt"), emit: output

    script:
    """
    # Tool: python_cv2_cv2_morphologyEx
    # Runs in unified Docker container
    echo 'Running STEP_4__CV2_MORPHOLOGYEX'
        touch step_4__cv2_morphologyex_output.txt
    """
}

process STEP_5__CV2_VIDEOCAPTURE {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_5__cv2_videocapture_output.txt"), emit: output

    script:
    """
    # Tool: python_cv2_cv2_VideoCapture
    # Runs in unified Docker container
    echo 'Running STEP_5__CV2_VIDEOCAPTURE'
        touch step_5__cv2_videocapture_output.txt
    """
}

workflow BIOMNI_IMMUNOLOGY_TRACK_IMMUNE_CELLS_UNDER_FLOW {
    main:
    ch_image_sequence_path = Channel.value(params.image_sequence_path)

    STEP_1__CV2_CVTCOLOR(ch_image_sequence_path)
    STEP_2__CV2_IMREAD(STEP_1__CV2_CVTCOLOR.out.output)
    STEP_3__CV2_GAUSSIANBLUR(STEP_2__CV2_IMREAD.out.output)
    STEP_4__CV2_MORPHOLOGYEX(STEP_3__CV2_GAUSSIANBLUR.out.output)
    STEP_5__CV2_VIDEOCAPTURE(STEP_4__CV2_MORPHOLOGYEX.out.output)

    emit:
    output = STEP_5__CV2_VIDEOCAPTURE.out.output
}

workflow {
    BIOMNI_IMMUNOLOGY_TRACK_IMMUNE_CELLS_UNDER_FLOW()
}