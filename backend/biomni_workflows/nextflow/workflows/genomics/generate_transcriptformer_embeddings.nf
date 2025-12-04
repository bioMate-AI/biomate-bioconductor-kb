#!/usr/bin/env nextflow
/*
 * biomni_genomics_generate_transcriptformer_embeddings
 * Generate Transcriptformer embeddings for single-cell RNA-seq data. This function downloads model checkpoints, prepares the AnnData object with required fields (ensembl_id, raw counts, assay metadata), and runs inference to generate cell or gene embeddings. Transcriptformer is a transformer-based model that can learn rich representations of single-cell gene expression data. The function automatically handles Ensembl ID pattern detection, model downloading, data preprocessing, and creates missing assay metadata columns with 'unknown' values if needed.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.adata_filename = null
params.data_dir = null

// Processes
process STEP_1__TORCH_CUDA_CURRENT_DEVICE {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_1__torch_cuda_current_device_output.txt"), emit: output

    script:
    """
    # Tool: python_torch_torch_cuda_current_device
    # Runs in unified Docker container
    echo 'Running STEP_1__TORCH_CUDA_CURRENT_DEVICE'
        touch step_1__torch_cuda_current_device_output.txt
    """
}

process STEP_2__TORCH_CUDA_DEVICE_COUNT {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_2__torch_cuda_device_count_output.txt"), emit: output

    script:
    """
    # Tool: python_torch_torch_cuda_device_count
    # Runs in unified Docker container
    echo 'Running STEP_2__TORCH_CUDA_DEVICE_COUNT'
        touch step_2__torch_cuda_device_count_output.txt
    """
}

process STEP_3__TORCH_CUDA_GET_DEVICE_NAME {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_3__torch_cuda_get_device_name_output.txt"), emit: output

    script:
    """
    # Tool: python_torch_torch_cuda_get_device_name
    # Runs in unified Docker container
    echo 'Running STEP_3__TORCH_CUDA_GET_DEVICE_NAME'
        touch step_3__torch_cuda_get_device_name_output.txt
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

process STEP_5__TORCH_CUDA_GET_DEVICE_PROPERTIES {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_5__torch_cuda_get_device_properties_output.txt"), emit: output

    script:
    """
    # Tool: python_torch_torch_cuda_get_device_properties
    # Runs in unified Docker container
    echo 'Running STEP_5__TORCH_CUDA_GET_DEVICE_PROPERTIES'
        touch step_5__torch_cuda_get_device_properties_output.txt
    """
}

workflow BIOMNI_GENOMICS_GENERATE_TRANSCRIPTFORMER_EMBEDDINGS {
    main:
    ch_adata_filename = Channel.value(params.adata_filename)
    ch_data_dir = Channel.value(params.data_dir)

    STEP_1__TORCH_CUDA_CURRENT_DEVICE(ch_data_dir)
    STEP_2__TORCH_CUDA_DEVICE_COUNT(STEP_1__TORCH_CUDA_CURRENT_DEVICE.out.output)
    STEP_3__TORCH_CUDA_GET_DEVICE_NAME(STEP_2__TORCH_CUDA_DEVICE_COUNT.out.output)
    STEP_4__TORCH_CUDA_IS_AVAILABLE(STEP_3__TORCH_CUDA_GET_DEVICE_NAME.out.output)
    STEP_5__TORCH_CUDA_GET_DEVICE_PROPERTIES(STEP_4__TORCH_CUDA_IS_AVAILABLE.out.output)

    emit:
    output = STEP_5__TORCH_CUDA_GET_DEVICE_PROPERTIES.out.output
}

workflow {
    BIOMNI_GENOMICS_GENERATE_TRANSCRIPTFORMER_EMBEDDINGS()
}