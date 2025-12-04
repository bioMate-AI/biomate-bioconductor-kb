#!/usr/bin/env nextflow
/*
 * biomni_pharmacology_query_drug_labels
 * Query FDA drug label information.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process QUERY_DRUG_LABELS {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("query_drug_labels_output.txt"), emit: output

    script:
    """
    # Tool: biomni_pharmacology_query_drug_labels
    # Runs in unified Docker container
    echo 'Running QUERY_DRUG_LABELS'
        touch query_drug_labels_output.txt
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

workflow BIOMNI_PHARMACOLOGY_QUERY_DRUG_LABELS {
    main:

    QUERY_DRUG_LABELS()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_PHARMACOLOGY_QUERY_DRUG_LABELS()
}