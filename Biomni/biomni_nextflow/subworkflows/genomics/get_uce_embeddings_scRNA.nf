#!/usr/bin/env nextflow
/*
 * biomni_genomics_get_uce_embeddings_scRNA
 * The UCE embeddings are usually our default tools to get cell embeddings, we map UCE embeddings to IMA referece dataset and get the cell types for a better understanding.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.adata_filename = null
params.data_dir = null
params.data_root = null

// Processes
process GET_UCE_EMBEDDINGS_SCRNA {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(adata_filename)
    path(data_dir)
    path(DATA_ROOT)

    output:
    path("get_uce_embeddings_scrna_output.txt"), emit: output

    script:
    """
    # Tool: biomni_genomics_get_uce_embeddings_scRNA
    # Runs in unified Docker container
    echo 'Running GET_UCE_EMBEDDINGS_SCRNA'
        touch get_uce_embeddings_scrna_output.txt
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

workflow BIOMNI_GENOMICS_GET_UCE_EMBEDDINGS_SCRNA {
    main:
    ch_adata_filename = Channel.fromPath(params.adata_filename)
    ch_data_dir = Channel.fromPath(params.data_dir)
    ch_data_root = Channel.fromPath(params.data_root)

    GET_UCE_EMBEDDINGS_SCRNA(ch_adata_filename, ch_data_dir, ch_data_root)
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_GENOMICS_GET_UCE_EMBEDDINGS_SCRNA()
}