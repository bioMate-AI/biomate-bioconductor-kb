#!/usr/bin/env nextflow
/*
 * biomni_lab_automation_run_async
 * 
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process RUN_ASYNC {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("run_async_output.txt"), emit: output

    script:
    """
    # Tool: biomni_lab_automation_run_async
    # Runs in unified Docker container
    echo 'Running RUN_ASYNC'
        touch run_async_output.txt
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

workflow BIOMNI_LAB_AUTOMATION_RUN_ASYNC {
    main:

    RUN_ASYNC()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_LAB_AUTOMATION_RUN_ASYNC()
}