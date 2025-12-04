#!/usr/bin/env nextflow
/*
 * biomni_systems_biology_ode_system
 * 
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process ODE_SYSTEM {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("ode_system_output.txt"), emit: output

    script:
    """
    # Tool: biomni_systems_biology_ode_system
    # Runs in unified Docker container
    echo 'Running ODE_SYSTEM'
        touch ode_system_output.txt
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

workflow BIOMNI_SYSTEMS_BIOLOGY_ODE_SYSTEM {
    main:

    ODE_SYSTEM()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_SYSTEMS_BIOLOGY_ODE_SYSTEM()
}