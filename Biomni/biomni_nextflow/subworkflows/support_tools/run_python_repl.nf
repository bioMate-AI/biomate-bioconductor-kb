#!/usr/bin/env nextflow
/*
 * biomni_support_tools_run_python_repl
 * Executes the provided Python command in a persistent environment and returns the output.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process RUN_PYTHON_REPL {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("run_python_repl_output.txt"), emit: output

    script:
    """
    # Tool: biomni_support_tools_run_python_repl
    # Runs in unified Docker container
    echo 'Running RUN_PYTHON_REPL'
        touch run_python_repl_output.txt
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

workflow BIOMNI_SUPPORT_TOOLS_RUN_PYTHON_REPL {
    main:

    RUN_PYTHON_REPL()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_SUPPORT_TOOLS_RUN_PYTHON_REPL()
}