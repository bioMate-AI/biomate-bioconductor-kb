#!/usr/bin/env nextflow
/*
 * biomni_physiology_analyze_ciliary_beat_frequency
 * Analyze ciliary beat frequency from high-speed video microscopy data using FFT analysis.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.video_path = null

// Processes
process STEP_1__CV2_VIDEOCAPTURE {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_1__cv2_videocapture_output.txt"), emit: output

    script:
    """
    # Tool: python_cv2_cv2_VideoCapture
    # Runs in unified Docker container
    echo 'Running STEP_1__CV2_VIDEOCAPTURE'
        touch step_1__cv2_videocapture_output.txt
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

process STEP_3__NP_MEDIAN {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_3__np_median_output.txt"), emit: output

    script:
    """
    # Tool: python_numpy_np_median
    # Runs in unified Docker container
    echo 'Running STEP_3__NP_MEDIAN'
        touch step_3__np_median_output.txt
    """
}

process STEP_4__NP_ARRAY {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_4__np_array_output.txt"), emit: output

    script:
    """
    # Tool: python_numpy_np_array
    # Runs in unified Docker container
    echo 'Running STEP_4__NP_ARRAY'
        touch step_4__np_array_output.txt
    """
}

process STEP_5__NP_ABS {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_5__np_abs_output.txt"), emit: output

    script:
    """
    # Tool: python_numpy_np_abs
    # Runs in unified Docker container
    echo 'Running STEP_5__NP_ABS'
        touch step_5__np_abs_output.txt
    """
}

workflow BIOMNI_PHYSIOLOGY_ANALYZE_CILIARY_BEAT_FREQUENCY {
    main:
    ch_video_path = Channel.value(params.video_path)

    STEP_1__CV2_VIDEOCAPTURE(ch_video_path)
    STEP_2__CV2_CVTCOLOR(STEP_1__CV2_VIDEOCAPTURE.out.output)
    STEP_3__NP_MEDIAN(STEP_2__CV2_CVTCOLOR.out.output)
    STEP_4__NP_ARRAY(STEP_3__NP_MEDIAN.out.output)
    STEP_5__NP_ABS(STEP_4__NP_ARRAY.out.output)

    emit:
    output = STEP_5__NP_ABS.out.output
}

workflow {
    BIOMNI_PHYSIOLOGY_ANALYZE_CILIARY_BEAT_FREQUENCY()
}