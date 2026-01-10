#!/usr/bin/env nextflow
/*
 * biomni_biochemistry_one_site_model
 * One-site binding model for ITC data.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process ONE_SITE_MODEL {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("one_site_model_output.txt"), emit: output

    script:
    """
    # Tool: biomni_biochemistry_one_site_model
    # Runs in unified Docker container
    echo 'Running ONE_SITE_MODEL'
        touch one_site_model_output.txt
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

workflow BIOMNI_BIOCHEMISTRY_ONE_SITE_MODEL {
    main:

    ONE_SITE_MODEL()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_BIOCHEMISTRY_ONE_SITE_MODEL()
}