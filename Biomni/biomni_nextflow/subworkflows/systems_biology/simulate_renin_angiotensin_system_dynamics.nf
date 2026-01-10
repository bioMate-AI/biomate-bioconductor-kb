#!/usr/bin/env nextflow
/*
 * biomni_systems_biology_simulate_renin_angiotensin_system_dynamics
 * 
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process SIMULATE_RENIN_ANGIOTENSIN_SYSTEM_DYNAMICS {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("simulate_renin_angiotensin_system_dynamics_output.txt"), emit: output

    script:
    """
    # Tool: biomni_systems_biology_simulate_renin_angiotensin_system_dynamics
    # Runs in unified Docker container
    echo 'Running SIMULATE_RENIN_ANGIOTENSIN_SYSTEM_DYNAMICS'
        touch simulate_renin_angiotensin_system_dynamics_output.txt
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

workflow BIOMNI_SYSTEMS_BIOLOGY_SIMULATE_RENIN_ANGIOTENSIN_SYSTEM_DYNAMICS {
    main:

    SIMULATE_RENIN_ANGIOTENSIN_SYSTEM_DYNAMICS()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_SYSTEMS_BIOLOGY_SIMULATE_RENIN_ANGIOTENSIN_SYSTEM_DYNAMICS()
}