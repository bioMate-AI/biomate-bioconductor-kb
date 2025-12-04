#!/usr/bin/env nextflow
/*
 * biomni_genomics_generate_gene_embeddings_with_ESM_models
 * Generate average protein embeddings for a list of Ensembl gene IDs using ESM (Evolutionary Scale Modeling) protein language models. This function fetches all protein isoform sequences for each gene, computes embeddings for each isoform using the specified ESM model and layer, then averages the embeddings across all isoforms to create a single representative embedding per gene. The embeddings are saved as PyTorch tensors for future use. Memory-friendly implementation with rolling averages, small batch processing, and automatic memory management. Automatically handles GPU/CPU device selection and includes error recovery for out-of-memory situations by falling back to single-sequence processing.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.ensembl_gene_ids = null

// Processes
process STEP_1__TORCH_STACK {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_1__torch_stack_output.txt"), emit: output

    script:
    """
    # Tool: python_torch_torch_stack
    # Runs in unified Docker container
    echo 'Running STEP_1__TORCH_STACK'
        touch step_1__torch_stack_output.txt
    """
}

process STEP_2__TORCH_SAVE {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_2__torch_save_output.txt"), emit: output

    script:
    """
    # Tool: python_torch_torch_save
    # Runs in unified Docker container
    echo 'Running STEP_2__TORCH_SAVE'
        touch step_2__torch_save_output.txt
    """
}

process STEP_3__TORCH_CUDA_EMPTY_CACHE {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_3__torch_cuda_empty_cache_output.txt"), emit: output

    script:
    """
    # Tool: python_torch_torch_cuda_empty_cache
    # Runs in unified Docker container
    echo 'Running STEP_3__TORCH_CUDA_EMPTY_CACHE'
        touch step_3__torch_cuda_empty_cache_output.txt
    """
}

process STEP_4__TORCH_CUDA_IS_AVAILABLE {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_4__torch_cuda_is_available_output.txt"), emit: output

    script:
    """
    # Tool: python_torch_torch_cuda_is_available
    # Runs in unified Docker container
    echo 'Running STEP_4__TORCH_CUDA_IS_AVAILABLE'
        touch step_4__torch_cuda_is_available_output.txt
    """
}

process STEP_5__TORCH_FROM_NUMPY {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_5__torch_from_numpy_output.txt"), emit: output

    script:
    """
    # Tool: python_torch_torch_from_numpy
    # Runs in unified Docker container
    echo 'Running STEP_5__TORCH_FROM_NUMPY'
        touch step_5__torch_from_numpy_output.txt
    """
}

workflow BIOMNI_GENOMICS_GENERATE_GENE_EMBEDDINGS_WITH_ESM_MODELS {
    main:
    ch_ensembl_gene_ids = Channel.value(params.ensembl_gene_ids)

    STEP_1__TORCH_STACK(ch_ensembl_gene_ids)
    STEP_2__TORCH_SAVE(STEP_1__TORCH_STACK.out.output)
    STEP_3__TORCH_CUDA_EMPTY_CACHE(STEP_2__TORCH_SAVE.out.output)
    STEP_4__TORCH_CUDA_IS_AVAILABLE(STEP_3__TORCH_CUDA_EMPTY_CACHE.out.output)
    STEP_5__TORCH_FROM_NUMPY(STEP_4__TORCH_CUDA_IS_AVAILABLE.out.output)

    emit:
    output = STEP_5__TORCH_FROM_NUMPY.out.output
}

workflow {
    BIOMNI_GENOMICS_GENERATE_GENE_EMBEDDINGS_WITH_ESM_MODELS()
}