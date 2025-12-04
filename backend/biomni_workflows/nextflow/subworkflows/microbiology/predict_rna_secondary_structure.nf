#!/usr/bin/env nextflow
/*
 * biomni_microbiology_predict_rna_secondary_structure
 * Predict the secondary structure of an RNA molecule using ViennaRNA.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process PREDICT_RNA_SECONDARY_STRUCTURE {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("predict_rna_secondary_structure_output.txt"), emit: output

    script:
    """
    # Tool: biomni_microbiology_predict_rna_secondary_structure
    # Runs in unified Docker container
    echo 'Running PREDICT_RNA_SECONDARY_STRUCTURE'
        touch predict_rna_secondary_structure_output.txt
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

workflow BIOMNI_MICROBIOLOGY_PREDICT_RNA_SECONDARY_STRUCTURE {
    main:

    PREDICT_RNA_SECONDARY_STRUCTURE()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_MICROBIOLOGY_PREDICT_RNA_SECONDARY_STRUCTURE()
}