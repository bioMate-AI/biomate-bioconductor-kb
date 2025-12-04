#!/usr/bin/env nextflow
/*
 * biomni_genomics_generate_gene_embeddings_with_ESM_models
 * 
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.save_path = null

// Processes
process GENERATE_GENE_EMBEDDINGS_WITH_ESM_MODELS {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(save_path)

    output:
    path("generate_gene_embeddings_with_esm_models_output.txt"), emit: output

    script:
    """
    # Tool: biomni_genomics_generate_gene_embeddings_with_ESM_models
    # Runs in unified Docker container
    echo 'Running GENERATE_GENE_EMBEDDINGS_WITH_ESM_MODELS'
        touch generate_gene_embeddings_with_esm_models_output.txt
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

workflow BIOMNI_GENOMICS_GENERATE_GENE_EMBEDDINGS_WITH_ESM_MODELS {
    main:
    ch_save_path = Channel.fromPath(params.save_path)

    GENERATE_GENE_EMBEDDINGS_WITH_ESM_MODELS(ch_save_path)
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_GENOMICS_GENERATE_GENE_EMBEDDINGS_WITH_ESM_MODELS()
}