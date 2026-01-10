#!/usr/bin/env nextflow
/*
 * biomni_pharmacology_retrieve_topk_repurposing_drugs_from_disease_txgnn
 * This function computes TxGNN model predictions for drug repurposing. It takes in the paths to the data,
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.data_lake_path = null

// Processes
process RETRIEVE_TOPK_REPURPOSING_DRUGS_FROM_DISEASE_TXGNN {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(data_lake_path)

    output:
    path("retrieve_topk_repurposing_drugs_from_disease_txgnn_output.txt"), emit: output

    script:
    """
    # Tool: biomni_pharmacology_retrieve_topk_repurposing_drugs_from_disease_txgnn
    # Runs in unified Docker container
    echo 'Running RETRIEVE_TOPK_REPURPOSING_DRUGS_FROM_DISEASE_TXGNN'
        touch retrieve_topk_repurposing_drugs_from_disease_txgnn_output.txt
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

workflow BIOMNI_PHARMACOLOGY_RETRIEVE_TOPK_REPURPOSING_DRUGS_FROM_DISEASE_TXGNN {
    main:
    ch_data_lake_path = Channel.fromPath(params.data_lake_path)

    RETRIEVE_TOPK_REPURPOSING_DRUGS_FROM_DISEASE_TXGNN(ch_data_lake_path)
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_PHARMACOLOGY_RETRIEVE_TOPK_REPURPOSING_DRUGS_FROM_DISEASE_TXGNN()
}