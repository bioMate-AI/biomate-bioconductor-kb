#!/usr/bin/env nextflow
/*
 * biomni_lab_automation_target
 * 
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process TARGET {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("target_output.txt"), emit: output

    script:
    """
    # Tool: biomni_lab_automation_target
    # Runs in unified Docker container
    echo 'Running TARGET'
        touch target_output.txt
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

workflow BIOMNI_LAB_AUTOMATION_TARGET {
    main:

    TARGET()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_LAB_AUTOMATION_TARGET()
}