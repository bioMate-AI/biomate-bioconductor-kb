#!/usr/bin/env nextflow
/*
 * biomni_cell_biology_perform_facs_cell_sorting
 * Performs Fluorescence-Activated Cell Sorting (FACS) to enrich cell populations based on fluorescence characteristics.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.cell_suspension_data = null
params.fluorescence_parameter = null

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

workflow BIOMNI_CELL_BIOLOGY_PERFORM_FACS_CELL_SORTING {
    main:
    ch_cell_suspension_data = Channel.value(params.cell_suspension_data)
    ch_fluorescence_parameter = Channel.value(params.fluorescence_parameter)

    STEP_1__PD_DATAFRAME(ch_fluorescence_parameter)
    STEP_2__PD_READ_CSV(STEP_1__PD_DATAFRAME.out.output)

    emit:
    output = STEP_2__PD_READ_CSV.out.output
}

workflow {
    BIOMNI_CELL_BIOLOGY_PERFORM_FACS_CELL_SORTING()
}