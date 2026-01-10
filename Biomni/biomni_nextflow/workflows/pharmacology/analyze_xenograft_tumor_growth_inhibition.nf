#!/usr/bin/env nextflow
/*
 * biomni_pharmacology_analyze_xenograft_tumor_growth_inhibition
 * Analyze tumor growth inhibition in xenograft models across different treatment groups.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.data_path = null
params.time_column = null
params.volume_column = null
params.group_column = null
params.subject_column = null

// Processes
process STEP_1__PD_DATAFRAME {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_1__pd_dataframe_output.txt"), emit: output

    script:
    """
    # Tool: python_pandas_pd_DataFrame
    # Runs in unified Docker container
    echo 'Running STEP_1__PD_DATAFRAME'
        touch step_1__pd_dataframe_output.txt
    """
}

process STEP_2__PD_READ_CSV {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_2__pd_read_csv_output.txt"), emit: output

    script:
    """
    # Tool: python_pandas_pd_read_csv
    # Runs in unified Docker container
    echo 'Running STEP_2__PD_READ_CSV'
        touch step_2__pd_read_csv_output.txt
    """
}

process STEP_3__STATS_LINREGRESS {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_3__stats_linregress_output.txt"), emit: output

    script:
    """
    # Tool: python_scipy_stats_linregress
    # Runs in unified Docker container
    echo 'Running STEP_3__STATS_LINREGRESS'
        touch step_3__stats_linregress_output.txt
    """
}

process STEP_4__STATS_SEM {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_4__stats_sem_output.txt"), emit: output

    script:
    """
    # Tool: python_scipy_stats_sem
    # Runs in unified Docker container
    echo 'Running STEP_4__STATS_SEM'
        touch step_4__stats_sem_output.txt
    """
}

process STEP_5__NP_MEAN {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_5__np_mean_output.txt"), emit: output

    script:
    """
    # Tool: python_numpy_np_mean
    # Runs in unified Docker container
    echo 'Running STEP_5__NP_MEAN'
        touch step_5__np_mean_output.txt
    """
}

workflow BIOMNI_PHARMACOLOGY_ANALYZE_XENOGRAFT_TUMOR_GROWTH_INHIBITION {
    main:
    ch_data_path = Channel.value(params.data_path)
    ch_time_column = Channel.value(params.time_column)
    ch_volume_column = Channel.value(params.volume_column)
    ch_group_column = Channel.value(params.group_column)
    ch_subject_column = Channel.value(params.subject_column)

    STEP_1__PD_DATAFRAME(ch_subject_column)
    STEP_2__PD_READ_CSV(STEP_1__PD_DATAFRAME.out.output)
    STEP_3__STATS_LINREGRESS(STEP_2__PD_READ_CSV.out.output)
    STEP_4__STATS_SEM(STEP_3__STATS_LINREGRESS.out.output)
    STEP_5__NP_MEAN(STEP_4__STATS_SEM.out.output)

    emit:
    output = STEP_5__NP_MEAN.out.output
}

workflow {
    BIOMNI_PHARMACOLOGY_ANALYZE_XENOGRAFT_TUMOR_GROWTH_INHIBITION()
}