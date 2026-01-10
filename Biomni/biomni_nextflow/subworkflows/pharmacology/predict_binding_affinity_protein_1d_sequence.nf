#!/usr/bin/env nextflow
/*
 * biomni_pharmacology_predict_binding_affinity_protein_1d_sequence
 * 
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process PREDICT_BINDING_AFFINITY_PROTEIN_1D_SEQUENCE {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("predict_binding_affinity_protein_1d_sequence_output.txt"), emit: output

    script:
    """
    # Tool: biomni_pharmacology_predict_binding_affinity_protein_1d_sequence
    # Runs in unified Docker container
    echo 'Running PREDICT_BINDING_AFFINITY_PROTEIN_1D_SEQUENCE'
        touch predict_binding_affinity_protein_1d_sequence_output.txt
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

workflow BIOMNI_PHARMACOLOGY_PREDICT_BINDING_AFFINITY_PROTEIN_1D_SEQUENCE {
    main:

    PREDICT_BINDING_AFFINITY_PROTEIN_1D_SEQUENCE()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_PHARMACOLOGY_PREDICT_BINDING_AFFINITY_PROTEIN_1D_SEQUENCE()
}