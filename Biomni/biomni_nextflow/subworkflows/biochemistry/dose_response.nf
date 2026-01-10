#!/usr/bin/env nextflow
/*
 * biomni_biochemistry_dose_response
 * 
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process DOSE_RESPONSE {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("dose_response_output.txt"), emit: output

    script:
    """
    # Tool: biomni_biochemistry_dose_response
    # Runs in unified Docker container
    echo 'Running DOSE_RESPONSE'
        touch dose_response_output.txt
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

workflow BIOMNI_BIOCHEMISTRY_DOSE_RESPONSE {
    main:

    DOSE_RESPONSE()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_BIOCHEMISTRY_DOSE_RESPONSE()
}