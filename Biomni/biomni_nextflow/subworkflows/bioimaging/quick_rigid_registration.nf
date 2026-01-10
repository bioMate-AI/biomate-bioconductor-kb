#!/usr/bin/env nextflow
/*
 * biomni_bioimaging_quick_rigid_registration
 * Quick rigid registration (translation + rotation) of a moving image to a fixed image.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process QUICK_RIGID_REGISTRATION {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("quick_rigid_registration_output.txt"), emit: output

    script:
    """
    # Tool: biomni_bioimaging_quick_rigid_registration
    # Runs in unified Docker container
    echo 'Running QUICK_RIGID_REGISTRATION'
        touch quick_rigid_registration_output.txt
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

workflow BIOMNI_BIOIMAGING_QUICK_RIGID_REGISTRATION {
    main:

    QUICK_RIGID_REGISTRATION()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_BIOIMAGING_QUICK_RIGID_REGISTRATION()
}