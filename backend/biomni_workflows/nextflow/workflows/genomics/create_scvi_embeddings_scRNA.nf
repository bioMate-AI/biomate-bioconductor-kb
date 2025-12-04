#!/usr/bin/env nextflow
/*
 * biomni_genomics_create_scvi_embeddings_scRNA
 * Create scVI and scANVI embeddings for single-cell RNA-seq data, saving the results to an AnnData object.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.adata_filename = null
params.batch_key = null
params.label_key = null
params.data_dir = null

// Processes
process STEP_1__SC_READ_H5AD {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_1__sc_read_h5ad_output.txt"), emit: output

    script:
    """
    # Tool: python_scanpy_sc_read_h5ad
    # Runs in unified Docker container
    echo 'Running STEP_1__SC_READ_H5AD'
        touch step_1__sc_read_h5ad_output.txt
    """
}

workflow BIOMNI_GENOMICS_CREATE_SCVI_EMBEDDINGS_SCRNA {
    main:
    ch_adata_filename = Channel.value(params.adata_filename)
    ch_batch_key = Channel.value(params.batch_key)
    ch_label_key = Channel.value(params.label_key)
    ch_data_dir = Channel.value(params.data_dir)

    STEP_1__SC_READ_H5AD(ch_data_dir)

    emit:
    output = STEP_1__SC_READ_H5AD.out.output
}

workflow {
    BIOMNI_GENOMICS_CREATE_SCVI_EMBEDDINGS_SCRNA()
}