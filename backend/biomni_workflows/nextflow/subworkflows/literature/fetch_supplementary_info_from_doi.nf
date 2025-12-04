#!/usr/bin/env nextflow
/*
 * biomni_literature_fetch_supplementary_info_from_doi
 * Fetches supplementary information for a paper given its DOI and returns a research log.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process FETCH_SUPPLEMENTARY_INFO_FROM_DOI {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("fetch_supplementary_info_from_doi_output.txt"), emit: output

    script:
    """
    # Tool: biomni_literature_fetch_supplementary_info_from_doi
    # Runs in unified Docker container
    echo 'Running FETCH_SUPPLEMENTARY_INFO_FROM_DOI'
        touch fetch_supplementary_info_from_doi_output.txt
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

workflow BIOMNI_LITERATURE_FETCH_SUPPLEMENTARY_INFO_FROM_DOI {
    main:

    FETCH_SUPPLEMENTARY_INFO_FROM_DOI()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_LITERATURE_FETCH_SUPPLEMENTARY_INFO_FROM_DOI()
}