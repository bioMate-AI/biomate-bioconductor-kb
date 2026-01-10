#!/usr/bin/env nextflow
/*
 * biomni_literature_query_scholar
 * Query Google Scholar for papers based on the provided search query.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process QUERY_SCHOLAR {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("query_scholar_output.txt"), emit: output

    script:
    """
    # Tool: biomni_literature_query_scholar
    # Runs in unified Docker container
    echo 'Running QUERY_SCHOLAR'
        touch query_scholar_output.txt
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

workflow BIOMNI_LITERATURE_QUERY_SCHOLAR {
    main:

    QUERY_SCHOLAR()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_LITERATURE_QUERY_SCHOLAR()
}