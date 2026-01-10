#!/usr/bin/env nextflow
/*
 * biomni_bioengineering_higuchi
 * 
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process HIGUCHI {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("higuchi_output.txt"), emit: output

    script:
    """
    # Tool: biomni_bioengineering_higuchi
    # Runs in unified Docker container
    echo 'Running HIGUCHI'
        touch higuchi_output.txt
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

workflow BIOMNI_BIOENGINEERING_HIGUCHI {
    main:

    HIGUCHI()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_BIOENGINEERING_HIGUCHI()
}