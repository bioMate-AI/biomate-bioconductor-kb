#!/usr/bin/env nextflow
/*
 * biomni_bioimaging_calculate_similarity_metrics
 * Calculate similarity metrics between two medical images. Supports mutual information, mean squared error, correlation, and normalized cross correlation.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.image1_path = null
params.image2_path = null

// Processes
process STEP_1__NP_ISNAN {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_1__np_isnan_output.txt"), emit: output

    script:
    """
    # Tool: python_numpy_np_isnan
    # Runs in unified Docker container
    echo 'Running STEP_1__NP_ISNAN'
        touch step_1__np_isnan_output.txt
    """
}

process STEP_2__NP_HISTOGRAM2D {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_2__np_histogram2d_output.txt"), emit: output

    script:
    """
    # Tool: python_numpy_np_histogram2d
    # Runs in unified Docker container
    echo 'Running STEP_2__NP_HISTOGRAM2D'
        touch step_2__np_histogram2d_output.txt
    """
}

process STEP_3__NP_SUM {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_3__np_sum_output.txt"), emit: output

    script:
    """
    # Tool: python_numpy_np_sum
    # Runs in unified Docker container
    echo 'Running STEP_3__NP_SUM'
        touch step_3__np_sum_output.txt
    """
}

process STEP_4__NP_LOG2 {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_4__np_log2_output.txt"), emit: output

    script:
    """
    # Tool: python_numpy_np_log2
    # Runs in unified Docker container
    echo 'Running STEP_4__NP_LOG2'
        touch step_4__np_log2_output.txt
    """
}

process STEP_5__NP_CORRCOEF {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_5__np_corrcoef_output.txt"), emit: output

    script:
    """
    # Tool: python_numpy_np_corrcoef
    # Runs in unified Docker container
    echo 'Running STEP_5__NP_CORRCOEF'
        touch step_5__np_corrcoef_output.txt
    """
}

workflow BIOMNI_BIOIMAGING_CALCULATE_SIMILARITY_METRICS {
    main:
    ch_image1_path = Channel.value(params.image1_path)
    ch_image2_path = Channel.value(params.image2_path)

    STEP_1__NP_ISNAN(ch_image2_path)
    STEP_2__NP_HISTOGRAM2D(STEP_1__NP_ISNAN.out.output)
    STEP_3__NP_SUM(STEP_2__NP_HISTOGRAM2D.out.output)
    STEP_4__NP_LOG2(STEP_3__NP_SUM.out.output)
    STEP_5__NP_CORRCOEF(STEP_4__NP_LOG2.out.output)

    emit:
    output = STEP_5__NP_CORRCOEF.out.output
}

workflow {
    BIOMNI_BIOIMAGING_CALCULATE_SIMILARITY_METRICS()
}