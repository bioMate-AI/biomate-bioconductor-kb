#!/usr/bin/env nextflow
/*
 * biomni_microbiology_bacterial_dynamics
 * 
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process BACTERIAL_DYNAMICS {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("bacterial_dynamics_output.txt"), emit: output

    script:
    """
    # Tool: biomni_microbiology_bacterial_dynamics
    # Runs in unified Docker container
    echo 'Running BACTERIAL_DYNAMICS'
        touch bacterial_dynamics_output.txt
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

workflow BIOMNI_MICROBIOLOGY_BACTERIAL_DYNAMICS {
    main:

    BACTERIAL_DYNAMICS()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_MICROBIOLOGY_BACTERIAL_DYNAMICS()
}