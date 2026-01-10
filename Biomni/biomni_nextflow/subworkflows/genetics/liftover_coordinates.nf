#!/usr/bin/env nextflow
/*
 * biomni_genetics_liftover_coordinates
 * Perform liftover of genomic coordinates between hg19 and hg38 formats with detailed intermediate steps.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.input_format = null
params.data_path = null

// Processes
process LIFTOVER_COORDINATES {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_format)
    path(data_path)

    output:
    path("liftover_coordinates_output.txt"), emit: output

    script:
    """
    # Tool: biomni_genetics_liftover_coordinates
    # Runs in unified Docker container
    echo 'Running LIFTOVER_COORDINATES'
        touch liftover_coordinates_output.txt
    """
}

process OUTPUT {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("output_output.txt"), emit: output

    script:
    """
    # Tool: cat1
    # Runs in unified Docker container
    echo 'Running OUTPUT'
        touch output_output.txt
    """
}

workflow BIOMNI_GENETICS_LIFTOVER_COORDINATES {
    main:
    ch_input_format = Channel.fromPath(params.input_format)
    ch_data_path = Channel.fromPath(params.data_path)

    LIFTOVER_COORDINATES(ch_input_format, ch_data_path)
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_GENETICS_LIFTOVER_COORDINATES()
}