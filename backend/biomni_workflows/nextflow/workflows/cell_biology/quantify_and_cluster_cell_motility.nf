#!/usr/bin/env nextflow
/*
 * biomni_cell_biology_quantify_and_cluster_cell_motility
 * Quantify cell motility features from time-lapse microscopy images and cluster cells based on motility patterns.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.image_sequence_path = null

// Processes
process STEP_1__CV2_MOMENTS {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_1__cv2_moments_output.txt"), emit: output

    script:
    """
    # Tool: python_cv2_cv2_moments
    # Runs in unified Docker container
    echo 'Running STEP_1__CV2_MOMENTS'
        touch step_1__cv2_moments_output.txt
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

process STEP_3__CV2_CONTOURAREA {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_3__cv2_contourarea_output.txt"), emit: output

    script:
    """
    # Tool: python_cv2_cv2_contourArea
    # Runs in unified Docker container
    echo 'Running STEP_3__CV2_CONTOURAREA'
        touch step_3__cv2_contourarea_output.txt
    """
}

process STEP_4__CV2_FINDCONTOURS {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_4__cv2_findcontours_output.txt"), emit: output

    script:
    """
    # Tool: python_cv2_cv2_findContours
    # Runs in unified Docker container
    echo 'Running STEP_4__CV2_FINDCONTOURS'
        touch step_4__cv2_findcontours_output.txt
    """
}

process STEP_5__CV2_THRESHOLD {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_5__cv2_threshold_output.txt"), emit: output

    script:
    """
    # Tool: python_cv2_cv2_threshold
    # Runs in unified Docker container
    echo 'Running STEP_5__CV2_THRESHOLD'
        touch step_5__cv2_threshold_output.txt
    """
}

workflow BIOMNI_CELL_BIOLOGY_QUANTIFY_AND_CLUSTER_CELL_MOTILITY {
    main:
    ch_image_sequence_path = Channel.value(params.image_sequence_path)

    STEP_1__CV2_MOMENTS(ch_image_sequence_path)
    STEP_2__CV2_IMREAD(STEP_1__CV2_MOMENTS.out.output)
    STEP_3__CV2_CONTOURAREA(STEP_2__CV2_IMREAD.out.output)
    STEP_4__CV2_FINDCONTOURS(STEP_3__CV2_CONTOURAREA.out.output)
    STEP_5__CV2_THRESHOLD(STEP_4__CV2_FINDCONTOURS.out.output)

    emit:
    output = STEP_5__CV2_THRESHOLD.out.output
}

workflow {
    BIOMNI_CELL_BIOLOGY_QUANTIFY_AND_CLUSTER_CELL_MOTILITY()
}