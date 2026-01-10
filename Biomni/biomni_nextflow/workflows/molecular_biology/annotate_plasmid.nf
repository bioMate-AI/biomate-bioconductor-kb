#!/usr/bin/env nextflow
/*
 * biomni_molecular_biology_annotate_plasmid
 * Annotate a DNA sequence using pLannotate's command-line interface.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.sequence = null

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

workflow BIOMNI_MOLECULAR_BIOLOGY_ANNOTATE_PLASMID {
    main:
    ch_sequence = Channel.value(params.sequence)

    STEP_1__PD_READ_CSV(ch_sequence)

    emit:
    output = STEP_1__PD_READ_CSV.out.output
}

workflow {
    BIOMNI_MOLECULAR_BIOLOGY_ANNOTATE_PLASMID()
}