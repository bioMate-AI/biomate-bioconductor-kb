#!/usr/bin/env nextflow
/*
 * biomni_database_query_kegg
 * Take a natural language prompt and convert it to a structured KEGG API query.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process QUERY_KEGG {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("query_kegg_output.txt"), emit: output

    script:
    """
    # Tool: biomni_database_query_kegg
    # Runs in unified Docker container
    echo 'Running QUERY_KEGG'
        touch query_kegg_output.txt
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

workflow BIOMNI_DATABASE_QUERY_KEGG {
    main:

    QUERY_KEGG()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_DATABASE_QUERY_KEGG()
}