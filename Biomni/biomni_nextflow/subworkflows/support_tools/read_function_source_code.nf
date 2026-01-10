#!/usr/bin/env nextflow
/*
 * biomni_support_tools_read_function_source_code
 * Read the source code of a function from any module path.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process READ_FUNCTION_SOURCE_CODE {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("read_function_source_code_output.txt"), emit: output

    script:
    """
    # Tool: biomni_support_tools_read_function_source_code
    # Runs in unified Docker container
    echo 'Running READ_FUNCTION_SOURCE_CODE'
        touch read_function_source_code_output.txt
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

workflow BIOMNI_SUPPORT_TOOLS_READ_FUNCTION_SOURCE_CODE {
    main:

    READ_FUNCTION_SOURCE_CODE()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_SUPPORT_TOOLS_READ_FUNCTION_SOURCE_CODE()
}