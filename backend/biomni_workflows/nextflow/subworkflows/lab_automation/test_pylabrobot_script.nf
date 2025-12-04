#!/usr/bin/env nextflow
/*
 * biomni_lab_automation_test_pylabrobot_script
 * Test a PyLabRobot script using simulation and validation.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.script_input = null

// Processes
process TEST_PYLABROBOT_SCRIPT {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(script_input)

    output:
    path("test_pylabrobot_script_output.txt"), emit: output

    script:
    """
    # Tool: biomni_lab_automation_test_pylabrobot_script
    # Runs in unified Docker container
    echo 'Running TEST_PYLABROBOT_SCRIPT'
        touch test_pylabrobot_script_output.txt
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

workflow BIOMNI_LAB_AUTOMATION_TEST_PYLABROBOT_SCRIPT {
    main:
    ch_script_input = Channel.fromPath(params.script_input)

    TEST_PYLABROBOT_SCRIPT(ch_script_input)
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_LAB_AUTOMATION_TEST_PYLABROBOT_SCRIPT()
}