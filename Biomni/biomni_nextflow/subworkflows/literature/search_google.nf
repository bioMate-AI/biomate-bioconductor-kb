#!/usr/bin/env nextflow
/*
 * biomni_literature_search_google
 * Search using Google search.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process SEARCH_GOOGLE {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("search_google_output.txt"), emit: output

    script:
    """
    # Tool: biomni_literature_search_google
    # Runs in unified Docker container
    echo 'Running SEARCH_GOOGLE'
        touch search_google_output.txt
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

workflow BIOMNI_LITERATURE_SEARCH_GOOGLE {
    main:

    SEARCH_GOOGLE()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_LITERATURE_SEARCH_GOOGLE()
}