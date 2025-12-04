#!/usr/bin/env nextflow
/*
 * biomni_glycoengineering_list_glycoengineering_resources
 * Curate and summarize external glycoengineering tools and resources.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process LIST_GLYCOENGINEERING_RESOURCES {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("list_glycoengineering_resources_output.txt"), emit: output

    script:
    """
    # Tool: biomni_glycoengineering_list_glycoengineering_resources
    # Runs in unified Docker container
    echo 'Running LIST_GLYCOENGINEERING_RESOURCES'
        touch list_glycoengineering_resources_output.txt
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

workflow BIOMNI_GLYCOENGINEERING_LIST_GLYCOENGINEERING_RESOURCES {
    main:

    LIST_GLYCOENGINEERING_RESOURCES()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_GLYCOENGINEERING_LIST_GLYCOENGINEERING_RESOURCES()
}