#!/usr/bin/env nextflow
/*
 * biomni_bioengineering_exp_decay
 * 
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process EXP_DECAY {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("exp_decay_output.txt"), emit: output

    script:
    """
    # Tool: biomni_bioengineering_exp_decay
    # Runs in unified Docker container
    echo 'Running EXP_DECAY'
        touch exp_decay_output.txt
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

workflow BIOMNI_BIOENGINEERING_EXP_DECAY {
    main:

    EXP_DECAY()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_BIOENGINEERING_EXP_DECAY()
}