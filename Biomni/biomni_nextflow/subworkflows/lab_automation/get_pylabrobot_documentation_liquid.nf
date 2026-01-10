#!/usr/bin/env nextflow
/*
 * biomni_lab_automation_get_pylabrobot_documentation_liquid
 * Get the documentation for a specific section of the PyLabRobot tutorial.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process GET_PYLABROBOT_DOCUMENTATION_LIQUID {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("get_pylabrobot_documentation_liquid_output.txt"), emit: output

    script:
    """
    # Tool: biomni_lab_automation_get_pylabrobot_documentation_liquid
    # Runs in unified Docker container
    echo 'Running GET_PYLABROBOT_DOCUMENTATION_LIQUID'
        touch get_pylabrobot_documentation_liquid_output.txt
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

workflow BIOMNI_LAB_AUTOMATION_GET_PYLABROBOT_DOCUMENTATION_LIQUID {
    main:

    GET_PYLABROBOT_DOCUMENTATION_LIQUID()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_LAB_AUTOMATION_GET_PYLABROBOT_DOCUMENTATION_LIQUID()
}