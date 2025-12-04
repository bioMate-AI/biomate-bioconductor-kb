#!/usr/bin/env nextflow
/*
 * biomni_genetics_elbo_loss
 * 
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process ELBO_LOSS {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("elbo_loss_output.txt"), emit: output

    script:
    """
    # Tool: biomni_genetics_elbo_loss
    # Runs in unified Docker container
    echo 'Running ELBO_LOSS'
        touch elbo_loss_output.txt
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

workflow BIOMNI_GENETICS_ELBO_LOSS {
    main:

    ELBO_LOSS()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_GENETICS_ELBO_LOSS()
}