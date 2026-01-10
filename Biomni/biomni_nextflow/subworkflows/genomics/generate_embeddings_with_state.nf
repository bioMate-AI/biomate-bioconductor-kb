#!/usr/bin/env nextflow
/*
 * biomni_genomics_generate_embeddings_with_state
 * 
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.adata_filename = null
params.data_dir = null
params.output_filename = null

// Processes
process GENERATE_EMBEDDINGS_WITH_STATE {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(adata_filename)
    path(data_dir)
    path(output_filename)

    output:
    path("generate_embeddings_with_state_output.txt"), emit: output

    script:
    """
    # Tool: biomni_genomics_generate_embeddings_with_state
    # Runs in unified Docker container
    echo 'Running GENERATE_EMBEDDINGS_WITH_STATE'
        touch generate_embeddings_with_state_output.txt
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

workflow BIOMNI_GENOMICS_GENERATE_EMBEDDINGS_WITH_STATE {
    main:
    ch_adata_filename = Channel.fromPath(params.adata_filename)
    ch_data_dir = Channel.fromPath(params.data_dir)
    ch_output_filename = Channel.fromPath(params.output_filename)

    GENERATE_EMBEDDINGS_WITH_STATE(ch_adata_filename, ch_data_dir, ch_output_filename)
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_GENOMICS_GENERATE_EMBEDDINGS_WITH_STATE()
}