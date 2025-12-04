#!/usr/bin/env nextflow
/*
 * biomni_bioengineering_zero_order
 * 
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process ZERO_ORDER {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("zero_order_output.txt"), emit: output

    script:
    """
    # Tool: biomni_bioengineering_zero_order
    # Runs in unified Docker container
    echo 'Running ZERO_ORDER'
        touch zero_order_output.txt
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

workflow BIOMNI_BIOENGINEERING_ZERO_ORDER {
    main:

    ZERO_ORDER()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_BIOENGINEERING_ZERO_ORDER()
}