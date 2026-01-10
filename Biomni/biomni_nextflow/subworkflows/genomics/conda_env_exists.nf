#!/usr/bin/env nextflow
/*
 * biomni_genomics_conda_env_exists
 * 
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process CONDA_ENV_EXISTS {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("conda_env_exists_output.txt"), emit: output

    script:
    """
    # Tool: biomni_genomics_conda_env_exists
    # Runs in unified Docker container
    echo 'Running CONDA_ENV_EXISTS'
        touch conda_env_exists_output.txt
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

workflow BIOMNI_GENOMICS_CONDA_ENV_EXISTS {
    main:

    CONDA_ENV_EXISTS()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_GENOMICS_CONDA_ENV_EXISTS()
}