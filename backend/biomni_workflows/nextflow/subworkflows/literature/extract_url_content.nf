#!/usr/bin/env nextflow
/*
 * biomni_literature_extract_url_content
 * Extract the text content of a webpage using requests and BeautifulSoup.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process EXTRACT_URL_CONTENT {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("extract_url_content_output.txt"), emit: output

    script:
    """
    # Tool: biomni_literature_extract_url_content
    # Runs in unified Docker container
    echo 'Running EXTRACT_URL_CONTENT'
        touch extract_url_content_output.txt
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

workflow BIOMNI_LITERATURE_EXTRACT_URL_CONTENT {
    main:

    EXTRACT_URL_CONTENT()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_LITERATURE_EXTRACT_URL_CONTENT()
}