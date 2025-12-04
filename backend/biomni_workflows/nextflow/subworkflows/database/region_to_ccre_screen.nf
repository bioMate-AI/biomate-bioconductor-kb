#!/usr/bin/env nextflow
/*
 * biomni_database_region_to_ccre_screen
 * Given starting and ending coordinates, this function retrieves information of intersecting cCREs.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process REGION_TO_CCRE_SCREEN {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("region_to_ccre_screen_output.txt"), emit: output

    script:
    """
    # Tool: biomni_database_region_to_ccre_screen
    # Runs in unified Docker container
    echo 'Running REGION_TO_CCRE_SCREEN'
        touch region_to_ccre_screen_output.txt
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

workflow BIOMNI_DATABASE_REGION_TO_CCRE_SCREEN {
    main:

    REGION_TO_CCRE_SCREEN()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_DATABASE_REGION_TO_CCRE_SCREEN()
}