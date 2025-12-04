#!/usr/bin/env nextflow
/*
 * biomni_pharmacology_grade_adverse_events_using_vcog_ctcae
 * Grade and monitor adverse events in animal studies using the VCOG-CTCAE standard.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.clinical_data_file = null

// Processes
process STEP_1__PD_READ_CSV {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_1__pd_read_csv_output.txt"), emit: output

    script:
    """
    # Tool: python_pandas_pd_read_csv
    # Runs in unified Docker container
    echo 'Running STEP_1__PD_READ_CSV'
        touch step_1__pd_read_csv_output.txt
    """
}

workflow BIOMNI_PHARMACOLOGY_GRADE_ADVERSE_EVENTS_USING_VCOG_CTCAE {
    main:
    ch_clinical_data_file = Channel.value(params.clinical_data_file)

    STEP_1__PD_READ_CSV(ch_clinical_data_file)

    emit:
    output = STEP_1__PD_READ_CSV.out.output
}

workflow {
    BIOMNI_PHARMACOLOGY_GRADE_ADVERSE_EVENTS_USING_VCOG_CTCAE()
}