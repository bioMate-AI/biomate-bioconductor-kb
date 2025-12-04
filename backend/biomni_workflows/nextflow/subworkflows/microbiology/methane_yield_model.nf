#!/usr/bin/env nextflow
/*
 * biomni_microbiology_methane_yield_model
 * 
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process METHANE_YIELD_MODEL {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("methane_yield_model_output.txt"), emit: output

    script:
    """
    # Tool: biomni_microbiology_methane_yield_model
    # Runs in unified Docker container
    echo 'Running METHANE_YIELD_MODEL'
        touch methane_yield_model_output.txt
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

workflow BIOMNI_MICROBIOLOGY_METHANE_YIELD_MODEL {
    main:

    METHANE_YIELD_MODEL()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_MICROBIOLOGY_METHANE_YIELD_MODEL()
}