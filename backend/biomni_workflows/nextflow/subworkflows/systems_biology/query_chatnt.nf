#!/usr/bin/env nextflow
/*
 * biomni_systems_biology_query_chatnt
 * 
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process QUERY_CHATNT {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("query_chatnt_output.txt"), emit: output

    script:
    """
    # Tool: biomni_systems_biology_query_chatnt
    # Runs in unified Docker container
    echo 'Running QUERY_CHATNT'
        touch query_chatnt_output.txt
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

workflow BIOMNI_SYSTEMS_BIOLOGY_QUERY_CHATNT {
    main:

    QUERY_CHATNT()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_SYSTEMS_BIOLOGY_QUERY_CHATNT()
}