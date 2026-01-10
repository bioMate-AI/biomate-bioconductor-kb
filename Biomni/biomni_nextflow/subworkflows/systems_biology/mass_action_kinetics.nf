#!/usr/bin/env nextflow
/*
 * biomni_systems_biology_mass_action_kinetics
 * 
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process MASS_ACTION_KINETICS {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("mass_action_kinetics_output.txt"), emit: output

    script:
    """
    # Tool: biomni_systems_biology_mass_action_kinetics
    # Runs in unified Docker container
    echo 'Running MASS_ACTION_KINETICS'
        touch mass_action_kinetics_output.txt
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

workflow BIOMNI_SYSTEMS_BIOLOGY_MASS_ACTION_KINETICS {
    main:

    MASS_ACTION_KINETICS()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_SYSTEMS_BIOLOGY_MASS_ACTION_KINETICS()
}