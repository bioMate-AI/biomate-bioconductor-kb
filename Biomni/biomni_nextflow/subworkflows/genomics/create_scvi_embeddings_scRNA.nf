#!/usr/bin/env nextflow
/*
 * biomni_genomics_create_scvi_embeddings_scRNA
 * 
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.adata_filename = null
params.data_dir = null

// Processes
process CREATE_SCVI_EMBEDDINGS_SCRNA {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(adata_filename)
    path(data_dir)

    output:
    path("create_scvi_embeddings_scrna_output.txt"), emit: output

    script:
    """
    # Tool: biomni_genomics_create_scvi_embeddings_scRNA
    # Runs in unified Docker container
    echo 'Running CREATE_SCVI_EMBEDDINGS_SCRNA'
        touch create_scvi_embeddings_scrna_output.txt
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

workflow BIOMNI_GENOMICS_CREATE_SCVI_EMBEDDINGS_SCRNA {
    main:
    ch_adata_filename = Channel.fromPath(params.adata_filename)
    ch_data_dir = Channel.fromPath(params.data_dir)

    CREATE_SCVI_EMBEDDINGS_SCRNA(ch_adata_filename, ch_data_dir)
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_GENOMICS_CREATE_SCVI_EMBEDDINGS_SCRNA()
}