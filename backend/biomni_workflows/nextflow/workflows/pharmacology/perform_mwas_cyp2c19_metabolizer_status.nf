#!/usr/bin/env nextflow
/*
 * biomni_pharmacology_perform_mwas_cyp2c19_metabolizer_status
 * Perform a Methylome-wide Association Study (MWAS) to identify CpG sites significantly associated with CYP2C19 metabolizer status.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.methylation_data_path = null
params.metabolizer_status_path = null

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

process STEP_3__LINREGRESS {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_3__linregress_output.txt"), emit: output

    script:
    """
    # Tool: python_scipy_linregress
    # Runs in unified Docker container
    echo 'Running STEP_3__LINREGRESS'
        touch step_3__linregress_output.txt
    """
}

workflow BIOMNI_PHARMACOLOGY_PERFORM_MWAS_CYP2C19_METABOLIZER_STATUS {
    main:
    ch_methylation_data_path = Channel.value(params.methylation_data_path)
    ch_metabolizer_status_path = Channel.value(params.metabolizer_status_path)

    STEP_1__PD_DATAFRAME(ch_metabolizer_status_path)
    STEP_2__PD_READ_CSV(STEP_1__PD_DATAFRAME.out.output)
    STEP_3__LINREGRESS(STEP_2__PD_READ_CSV.out.output)

    emit:
    output = STEP_3__LINREGRESS.out.output
}

workflow {
    BIOMNI_PHARMACOLOGY_PERFORM_MWAS_CYP2C19_METABOLIZER_STATUS()
}