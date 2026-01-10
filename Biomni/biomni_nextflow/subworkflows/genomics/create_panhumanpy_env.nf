#!/usr/bin/env nextflow
/*
 * biomni_genomics_create_panhumanpy_env
 * 
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process CREATE_PANHUMANPY_ENV {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("create_panhumanpy_env_output.txt"), emit: output

    script:
    """
    # Tool: biomni_genomics_create_panhumanpy_env
    # Runs in unified Docker container
    echo 'Running CREATE_PANHUMANPY_ENV'
        touch create_panhumanpy_env_output.txt
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

workflow BIOMNI_GENOMICS_CREATE_PANHUMANPY_ENV {
    main:

    CREATE_PANHUMANPY_ENV()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_GENOMICS_CREATE_PANHUMANPY_ENV()
}