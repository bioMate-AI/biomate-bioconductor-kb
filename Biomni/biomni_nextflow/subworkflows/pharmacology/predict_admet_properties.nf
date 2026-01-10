#!/usr/bin/env nextflow
/*
 * biomni_pharmacology_predict_admet_properties
 * 
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process PREDICT_ADMET_PROPERTIES {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("predict_admet_properties_output.txt"), emit: output

    script:
    """
    # Tool: biomni_pharmacology_predict_admet_properties
    # Runs in unified Docker container
    echo 'Running PREDICT_ADMET_PROPERTIES'
        touch predict_admet_properties_output.txt
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

workflow BIOMNI_PHARMACOLOGY_PREDICT_ADMET_PROPERTIES {
    main:

    PREDICT_ADMET_PROPERTIES()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_PHARMACOLOGY_PREDICT_ADMET_PROPERTIES()
}