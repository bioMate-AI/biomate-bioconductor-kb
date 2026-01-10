#!/usr/bin/env nextflow
/*
 * biomni_immunology_analyze_cfse_cell_proliferation
 * Analyze CFSE-labeled cell samples to quantify cell division and proliferation.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.fcs_file_path = null

// Processes
process STEP_1__NP_RANDOM_SEED {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_1__np_random_seed_output.txt"), emit: output

    script:
    """
    # Tool: python_numpy_np_random_seed
    # Runs in unified Docker container
    echo 'Running STEP_1__NP_RANDOM_SEED'
        touch step_1__np_random_seed_output.txt
    """
}

process STEP_2__NP_HISTOGRAM {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_2__np_histogram_output.txt"), emit: output

    script:
    """
    # Tool: python_numpy_np_histogram
    # Runs in unified Docker container
    echo 'Running STEP_2__NP_HISTOGRAM'
        touch step_2__np_histogram_output.txt
    """
}

process STEP_3__NP_SORT {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_3__np_sort_output.txt"), emit: output

    script:
    """
    # Tool: python_numpy_np_sort
    # Runs in unified Docker container
    echo 'Running STEP_3__NP_SORT'
        touch step_3__np_sort_output.txt
    """
}

process STEP_4__NP_LOG10 {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_4__np_log10_output.txt"), emit: output

    script:
    """
    # Tool: python_numpy_np_log10
    # Runs in unified Docker container
    echo 'Running STEP_4__NP_LOG10'
        touch step_4__np_log10_output.txt
    """
}

process STEP_5__NP_WHERE {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_5__np_where_output.txt"), emit: output

    script:
    """
    # Tool: python_numpy_np_where
    # Runs in unified Docker container
    echo 'Running STEP_5__NP_WHERE'
        touch step_5__np_where_output.txt
    """
}

workflow BIOMNI_IMMUNOLOGY_ANALYZE_CFSE_CELL_PROLIFERATION {
    main:
    ch_fcs_file_path = Channel.value(params.fcs_file_path)

    STEP_1__NP_RANDOM_SEED(ch_fcs_file_path)
    STEP_2__NP_HISTOGRAM(STEP_1__NP_RANDOM_SEED.out.output)
    STEP_3__NP_SORT(STEP_2__NP_HISTOGRAM.out.output)
    STEP_4__NP_LOG10(STEP_3__NP_SORT.out.output)
    STEP_5__NP_WHERE(STEP_4__NP_LOG10.out.output)

    emit:
    output = STEP_5__NP_WHERE.out.output
}

workflow {
    BIOMNI_IMMUNOLOGY_ANALYZE_CFSE_CELL_PROLIFERATION()
}