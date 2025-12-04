#!/usr/bin/env nextflow
/*
 * biomni_genomics_unsupervised_celltype_transfer_between_scRNA_datasets
 * 
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.path_to_annotated_h5ad = null
params.path_to_not_annotated_h5ad = null

// Processes
process UNSUPERVISED_CELLTYPE_TRANSFER_BETWEEN_SCRNA_DATASETS {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(path_to_annotated_h5ad)
    path(path_to_not_annotated_h5ad)

    output:
    path("unsupervised_celltype_transfer_between_scrna_datasets_output.txt"), emit: output

    script:
    """
    # Tool: biomni_genomics_unsupervised_celltype_transfer_between_scRNA_datasets
    # Runs in unified Docker container
    echo 'Running UNSUPERVISED_CELLTYPE_TRANSFER_BETWEEN_SCRNA_DATASETS'
        touch unsupervised_celltype_transfer_between_scrna_datasets_output.txt
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

workflow BIOMNI_GENOMICS_UNSUPERVISED_CELLTYPE_TRANSFER_BETWEEN_SCRNA_DATASETS {
    main:
    ch_path_to_annotated_h5ad = Channel.fromPath(params.path_to_annotated_h5ad)
    ch_path_to_not_annotated_h5ad = Channel.fromPath(params.path_to_not_annotated_h5ad)

    UNSUPERVISED_CELLTYPE_TRANSFER_BETWEEN_SCRNA_DATASETS(ch_path_to_annotated_h5ad, ch_path_to_not_annotated_h5ad)
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_GENOMICS_UNSUPERVISED_CELLTYPE_TRANSFER_BETWEEN_SCRNA_DATASETS()
}