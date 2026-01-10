#!/usr/bin/env nextflow
/*
 * biomni_bioengineering_korsmeyer_peppas
 * 
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process KORSMEYER_PEPPAS {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("korsmeyer_peppas_output.txt"), emit: output

    script:
    """
    # Tool: biomni_bioengineering_korsmeyer_peppas
    # Runs in unified Docker container
    echo 'Running KORSMEYER_PEPPAS'
        touch korsmeyer_peppas_output.txt
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

workflow BIOMNI_BIOENGINEERING_KORSMEYER_PEPPAS {
    main:

    KORSMEYER_PEPPAS()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_BIOENGINEERING_KORSMEYER_PEPPAS()
}