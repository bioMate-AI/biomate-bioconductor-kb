#!/usr/bin/env nextflow
/*
 * biomni_genomics_generate_transcriptformer_embeddings
 * 
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.adata_filename = null
params.data_dir = null
params.output_filename = null
params.checkpoint_path = null
params.n_data_workers = null
params.oom_dataloader = null

// Processes
process GENERATE_TRANSCRIPTFORMER_EMBEDDINGS {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(adata_filename)
    path(data_dir)
    path(output_filename)
    path(checkpoint_path)
    path(n_data_workers)
    path(oom_dataloader)

    output:
    path("generate_transcriptformer_embeddings_output.txt"), emit: output

    script:
    """
    # Tool: biomni_genomics_generate_transcriptformer_embeddings
    # Runs in unified Docker container
    echo 'Running GENERATE_TRANSCRIPTFORMER_EMBEDDINGS'
        touch generate_transcriptformer_embeddings_output.txt
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

workflow BIOMNI_GENOMICS_GENERATE_TRANSCRIPTFORMER_EMBEDDINGS {
    main:
    ch_adata_filename = Channel.fromPath(params.adata_filename)
    ch_data_dir = Channel.fromPath(params.data_dir)
    ch_output_filename = Channel.fromPath(params.output_filename)
    ch_checkpoint_path = Channel.fromPath(params.checkpoint_path)
    ch_n_data_workers = Channel.fromPath(params.n_data_workers)
    ch_oom_dataloader = Channel.fromPath(params.oom_dataloader)

    GENERATE_TRANSCRIPTFORMER_EMBEDDINGS(ch_adata_filename, ch_data_dir, ch_output_filename, ch_checkpoint_path, ch_n_data_workers, ch_oom_dataloader)
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_GENOMICS_GENERATE_TRANSCRIPTFORMER_EMBEDDINGS()
}