#!/usr/bin/env nextflow
/*
 * biomni_database_query_emdb
 * Query the Electron Microscopy Data Bank (EMDB) for 3D macromolecular structures.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process QUERY_EMDB {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("query_emdb_output.txt"), emit: output

    script:
    """
    # Tool: biomni_database_query_emdb
    # Runs in unified Docker container
    echo 'Running QUERY_EMDB'
        touch query_emdb_output.txt
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

workflow BIOMNI_DATABASE_QUERY_EMDB {
    main:

    QUERY_EMDB()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_DATABASE_QUERY_EMDB()
}