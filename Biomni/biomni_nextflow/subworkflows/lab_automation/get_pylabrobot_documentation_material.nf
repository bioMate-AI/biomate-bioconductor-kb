#!/usr/bin/env nextflow
/*
 * biomni_lab_automation_get_pylabrobot_documentation_material
 * 
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process GET_PYLABROBOT_DOCUMENTATION_MATERIAL {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("get_pylabrobot_documentation_material_output.txt"), emit: output

    script:
    """
    # Tool: biomni_lab_automation_get_pylabrobot_documentation_material
    # Runs in unified Docker container
    echo 'Running GET_PYLABROBOT_DOCUMENTATION_MATERIAL'
        touch get_pylabrobot_documentation_material_output.txt
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

workflow BIOMNI_LAB_AUTOMATION_GET_PYLABROBOT_DOCUMENTATION_MATERIAL {
    main:

    GET_PYLABROBOT_DOCUMENTATION_MATERIAL()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_LAB_AUTOMATION_GET_PYLABROBOT_DOCUMENTATION_MATERIAL()
}