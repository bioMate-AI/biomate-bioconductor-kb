#!/usr/bin/env nextflow
/*
 * biomni_bioengineering_first_order
 * 
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process FIRST_ORDER {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("first_order_output.txt"), emit: output

    script:
    """
    # Tool: biomni_bioengineering_first_order
    # Runs in unified Docker container
    echo 'Running FIRST_ORDER'
        touch first_order_output.txt
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

workflow BIOMNI_BIOENGINEERING_FIRST_ORDER {
    main:

    FIRST_ORDER()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_BIOENGINEERING_FIRST_ORDER()
}