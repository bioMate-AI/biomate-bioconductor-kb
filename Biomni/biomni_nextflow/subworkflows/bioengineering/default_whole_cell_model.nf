#!/usr/bin/env nextflow
/*
 * biomni_bioengineering_default_whole_cell_model
 * 
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process DEFAULT_WHOLE_CELL_MODEL {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("default_whole_cell_model_output.txt"), emit: output

    script:
    """
    # Tool: biomni_bioengineering_default_whole_cell_model
    # Runs in unified Docker container
    echo 'Running DEFAULT_WHOLE_CELL_MODEL'
        touch default_whole_cell_model_output.txt
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

workflow BIOMNI_BIOENGINEERING_DEFAULT_WHOLE_CELL_MODEL {
    main:

    DEFAULT_WHOLE_CELL_MODEL()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_BIOENGINEERING_DEFAULT_WHOLE_CELL_MODEL()
}