#!/usr/bin/env nextflow
/*
 * biomni_genomics_map_to_ima_interpret_scRNA
 * Map cell embeddings from the input dataset to the Integrated Megascale Atlas reference dataset using UCE embeddings.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.adata_filename = null
params.data_dir = null

// Processes
process MAP_TO_IMA_INTERPRET_SCRNA {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(adata_filename)
    path(data_dir)

    output:
    path("map_to_ima_interpret_scrna_output.txt"), emit: output

    script:
    """
    # Tool: biomni_genomics_map_to_ima_interpret_scRNA
    # Runs in unified Docker container
    echo 'Running MAP_TO_IMA_INTERPRET_SCRNA'
        touch map_to_ima_interpret_scrna_output.txt
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

workflow BIOMNI_GENOMICS_MAP_TO_IMA_INTERPRET_SCRNA {
    main:
    ch_adata_filename = Channel.fromPath(params.adata_filename)
    ch_data_dir = Channel.fromPath(params.data_dir)

    MAP_TO_IMA_INTERPRET_SCRNA(ch_adata_filename, ch_data_dir)
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_GENOMICS_MAP_TO_IMA_INTERPRET_SCRNA()
}