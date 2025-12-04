#!/usr/bin/env nextflow
/*
 * biomni_database_get_hpo_names
 * Retrieve the names of given HPO terms.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.data_lake_path = null

// Processes
process GET_HPO_NAMES {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(data_lake_path)

    output:
    path("get_hpo_names_output.txt"), emit: output

    script:
    """
    # Tool: biomni_database_get_hpo_names
    # Runs in unified Docker container
    echo 'Running GET_HPO_NAMES'
        touch get_hpo_names_output.txt
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

workflow BIOMNI_DATABASE_GET_HPO_NAMES {
    main:
    ch_data_lake_path = Channel.fromPath(params.data_lake_path)

    GET_HPO_NAMES(ch_data_lake_path)
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_DATABASE_GET_HPO_NAMES()
}