#!/usr/bin/env nextflow
/*
 * biomni_microbiology_count_bacterial_colonies
 * Count bacterial colonies from an image of agar plate using computer vision techniques.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.image_path = null

// Processes
process STEP_1__CV2_DILATE {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_1__cv2_dilate_output.txt"), emit: output

    script:
    """
    # Tool: python_cv2_cv2_dilate
    # Runs in unified Docker container
    echo 'Running STEP_1__CV2_DILATE'
        touch step_1__cv2_dilate_output.txt
    """
}

process STEP_2__CV2_CVTCOLOR {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_2__cv2_cvtcolor_output.txt"), emit: output

    script:
    """
    # Tool: python_cv2_cv2_cvtColor
    # Runs in unified Docker container
    echo 'Running STEP_2__CV2_CVTCOLOR'
        touch step_2__cv2_cvtcolor_output.txt
    """
}

process STEP_3__CV2_IMREAD {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_3__cv2_imread_output.txt"), emit: output

    script:
    """
    # Tool: python_cv2_cv2_imread
    # Runs in unified Docker container
    echo 'Running STEP_3__CV2_IMREAD'
        touch step_3__cv2_imread_output.txt
    """
}

process STEP_4__CV2_GAUSSIANBLUR {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_4__cv2_gaussianblur_output.txt"), emit: output

    script:
    """
    # Tool: python_cv2_cv2_GaussianBlur
    # Runs in unified Docker container
    echo 'Running STEP_4__CV2_GAUSSIANBLUR'
        touch step_4__cv2_gaussianblur_output.txt
    """
}

process STEP_5__CV2_DISTANCETRANSFORM {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_5__cv2_distancetransform_output.txt"), emit: output

    script:
    """
    # Tool: python_cv2_cv2_distanceTransform
    # Runs in unified Docker container
    echo 'Running STEP_5__CV2_DISTANCETRANSFORM'
        touch step_5__cv2_distancetransform_output.txt
    """
}

workflow BIOMNI_MICROBIOLOGY_COUNT_BACTERIAL_COLONIES {
    main:
    ch_image_path = Channel.value(params.image_path)

    STEP_1__CV2_DILATE(ch_image_path)
    STEP_2__CV2_CVTCOLOR(STEP_1__CV2_DILATE.out.output)
    STEP_3__CV2_IMREAD(STEP_2__CV2_CVTCOLOR.out.output)
    STEP_4__CV2_GAUSSIANBLUR(STEP_3__CV2_IMREAD.out.output)
    STEP_5__CV2_DISTANCETRANSFORM(STEP_4__CV2_GAUSSIANBLUR.out.output)

    emit:
    output = STEP_5__CV2_DISTANCETRANSFORM.out.output
}

workflow {
    BIOMNI_MICROBIOLOGY_COUNT_BACTERIAL_COLONIES()
}