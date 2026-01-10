#!/usr/bin/env nextflow
/*
 * biomni_pharmacology_ADMET_pred
 * 
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process ADMET_PRED {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("admet_pred_output.txt"), emit: output

    script:
    """
    # Tool: biomni_pharmacology_ADMET_pred
    # Runs in unified Docker container
    echo 'Running ADMET_PRED'
        touch admet_pred_output.txt
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

workflow BIOMNI_PHARMACOLOGY_ADMET_PRED {
    main:

    ADMET_PRED()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_PHARMACOLOGY_ADMET_PRED()
}