#!/usr/bin/env nextflow
/*
 * biomni_systems_biology_model_protein_dimerization_network
 * 
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process MODEL_PROTEIN_DIMERIZATION_NETWORK {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("model_protein_dimerization_network_output.txt"), emit: output

    script:
    """
    # Tool: biomni_systems_biology_model_protein_dimerization_network
    # Runs in unified Docker container
    echo 'Running MODEL_PROTEIN_DIMERIZATION_NETWORK'
        touch model_protein_dimerization_network_output.txt
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

workflow BIOMNI_SYSTEMS_BIOLOGY_MODEL_PROTEIN_DIMERIZATION_NETWORK {
    main:

    MODEL_PROTEIN_DIMERIZATION_NETWORK()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_SYSTEMS_BIOLOGY_MODEL_PROTEIN_DIMERIZATION_NETWORK()
}