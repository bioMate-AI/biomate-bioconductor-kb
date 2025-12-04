#!/usr/bin/env nextflow
/*
 * biomni_genomics_unsupervised_celltype_transfer_between_scRNA_datasets
 * Transfer cell type labels from an annotated reference scRNA-seq dataset to an unannotated query dataset using popV. Loads both AnnData .h5ad files, prepares count layers for scVI, processes the query against the reference, and runs selected annotation methods (default: SCANVI_POPV). Saves predictions to 'output_folder/popv_output/predictions.csv'. This function allows you to use different annotaiton methods i.e. CELLTYPIST, KNN_BBKNN, KNN_HARMONY, KNN_SCANORAMA, KNN_SCVI, ONCLASS, Random_Forest, SCANVI_POPV, Support_Vector, XGboost. Based on you transfer task you can select the multiple best annotation methods. Beware each annotation method adds computational requirements for running the tool. By default it uses SCANVI_POPV method.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.path_to_annotated_h5ad = null
params.path_to_not_annotated_h5ad = null
params.ref_labels_key = null

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

workflow BIOMNI_GENOMICS_UNSUPERVISED_CELLTYPE_TRANSFER_BETWEEN_SCRNA_DATASETS {
    main:
    ch_path_to_annotated_h5ad = Channel.value(params.path_to_annotated_h5ad)
    ch_path_to_not_annotated_h5ad = Channel.value(params.path_to_not_annotated_h5ad)
    ch_ref_labels_key = Channel.value(params.ref_labels_key)

    STEP_1__SC_READ_H5AD(ch_ref_labels_key)

    emit:
    output = STEP_1__SC_READ_H5AD.out.output
}

workflow {
    BIOMNI_GENOMICS_UNSUPERVISED_CELLTYPE_TRANSFER_BETWEEN_SCRNA_DATASETS()
}