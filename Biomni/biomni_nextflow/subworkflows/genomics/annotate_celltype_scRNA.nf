#!/usr/bin/env nextflow
/*
 * biomni_genomics_annotate_celltype_scRNA
 * Annotate cell types based on gene markers and transferred labels using LLM.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.adata_filename = null
params.data_dir = null
params.data_info = null
params.data_lake_path = null

// Processes
process ANNOTATE_CELLTYPE_SCRNA {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(adata_filename)
    path(data_dir)
    path(data_info)
    path(data_lake_path)

    output:
    path("annotate_celltype_scrna_output.txt"), emit: output

    script:
    """
    # Tool: biomni_genomics_annotate_celltype_scRNA
    # Runs in unified Docker container
    echo 'Running ANNOTATE_CELLTYPE_SCRNA'
        touch annotate_celltype_scrna_output.txt
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

workflow BIOMNI_GENOMICS_ANNOTATE_CELLTYPE_SCRNA {
    main:
    ch_adata_filename = Channel.fromPath(params.adata_filename)
    ch_data_dir = Channel.fromPath(params.data_dir)
    ch_data_info = Channel.fromPath(params.data_info)
    ch_data_lake_path = Channel.fromPath(params.data_lake_path)

    ANNOTATE_CELLTYPE_SCRNA(ch_adata_filename, ch_data_dir, ch_data_info, ch_data_lake_path)
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_GENOMICS_ANNOTATE_CELLTYPE_SCRNA()
}