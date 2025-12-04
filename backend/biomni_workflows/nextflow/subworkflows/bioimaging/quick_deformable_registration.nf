#!/usr/bin/env nextflow
/*
 * biomni_bioimaging_quick_deformable_registration
 * Quick deformable (non-rigid) registration for local alignment refinement.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process QUICK_DEFORMABLE_REGISTRATION {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("quick_deformable_registration_output.txt"), emit: output

    script:
    """
    # Tool: biomni_bioimaging_quick_deformable_registration
    # Runs in unified Docker container
    echo 'Running QUICK_DEFORMABLE_REGISTRATION'
        touch quick_deformable_registration_output.txt
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

workflow BIOMNI_BIOIMAGING_QUICK_DEFORMABLE_REGISTRATION {
    main:

    QUICK_DEFORMABLE_REGISTRATION()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_BIOIMAGING_QUICK_DEFORMABLE_REGISTRATION()
}