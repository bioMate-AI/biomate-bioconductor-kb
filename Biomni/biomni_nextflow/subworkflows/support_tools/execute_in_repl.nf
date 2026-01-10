#!/usr/bin/env nextflow
/*
 * biomni_support_tools_execute_in_repl
 * Helper function to execute the command in the persistent environment.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process EXECUTE_IN_REPL {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("execute_in_repl_output.txt"), emit: output

    script:
    """
    # Tool: biomni_support_tools_execute_in_repl
    # Runs in unified Docker container
    echo 'Running EXECUTE_IN_REPL'
        touch execute_in_repl_output.txt
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

workflow BIOMNI_SUPPORT_TOOLS_EXECUTE_IN_REPL {
    main:

    EXECUTE_IN_REPL()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_SUPPORT_TOOLS_EXECUTE_IN_REPL()
}