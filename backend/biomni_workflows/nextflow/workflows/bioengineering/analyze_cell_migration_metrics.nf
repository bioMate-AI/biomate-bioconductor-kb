#!/usr/bin/env nextflow
/*
 * biomni_bioengineering_analyze_cell_migration_metrics
 * Analyze cell migration metrics from time-lapse microscopy images.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.image_sequence_path = null

// Processes
process STEP_1__IO_IMREAD {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_1__io_imread_output.txt"), emit: output

    script:
    """
    # Tool: python_skimage_io_imread
    # Runs in unified Docker container
    echo 'Running STEP_1__IO_IMREAD'
        touch step_1__io_imread_output.txt
    """
}

process STEP_2__PD_DATAFRAME {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_2__pd_dataframe_output.txt"), emit: output

    script:
    """
    # Tool: python_pandas_pd_DataFrame
    # Runs in unified Docker container
    echo 'Running STEP_2__PD_DATAFRAME'
        touch step_2__pd_dataframe_output.txt
    """
}

process STEP_3__PD_CONCAT {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_3__pd_concat_output.txt"), emit: output

    script:
    """
    # Tool: python_pandas_pd_concat
    # Runs in unified Docker container
    echo 'Running STEP_3__PD_CONCAT'
        touch step_3__pd_concat_output.txt
    """
}

process STEP_4__NP_LINSPACE {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_4__np_linspace_output.txt"), emit: output

    script:
    """
    # Tool: python_numpy_np_linspace
    # Runs in unified Docker container
    echo 'Running STEP_4__NP_LINSPACE'
        touch step_4__np_linspace_output.txt
    """
}

process STEP_5__NP_ARCTAN2 {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_5__np_arctan2_output.txt"), emit: output

    script:
    """
    # Tool: python_numpy_np_arctan2
    # Runs in unified Docker container
    echo 'Running STEP_5__NP_ARCTAN2'
        touch step_5__np_arctan2_output.txt
    """
}

workflow BIOMNI_BIOENGINEERING_ANALYZE_CELL_MIGRATION_METRICS {
    main:
    ch_image_sequence_path = Channel.value(params.image_sequence_path)

    STEP_1__IO_IMREAD(ch_image_sequence_path)
    STEP_2__PD_DATAFRAME(STEP_1__IO_IMREAD.out.output)
    STEP_3__PD_CONCAT(STEP_2__PD_DATAFRAME.out.output)
    STEP_4__NP_LINSPACE(STEP_3__PD_CONCAT.out.output)
    STEP_5__NP_ARCTAN2(STEP_4__NP_LINSPACE.out.output)

    emit:
    output = STEP_5__NP_ARCTAN2.out.output
}

workflow {
    BIOMNI_BIOENGINEERING_ANALYZE_CELL_MIGRATION_METRICS()
}