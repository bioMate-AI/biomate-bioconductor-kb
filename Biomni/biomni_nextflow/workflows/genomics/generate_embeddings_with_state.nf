#!/usr/bin/env nextflow
/*
 * biomni_genomics_generate_embeddings_with_state
 * Generate State embeddings for single-cell RNA-seq data using the SE-600M model. This function downloads the SE-600M model from Hugging Face, installs required dependencies (git-lfs, uv, arc-state), and generates embeddings for the input AnnData object. The SE-600M model is a state-of-the-art embedding model for single-cell data that can capture complex biological patterns and cell states. Features include real-time streaming output, automatic retry with reduced batch size on failure, GPU detection and warnings, and input validation.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.adata_filename = null
params.data_dir = null
params.model_folder = null

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

process STEP_2__TORCH_CUDA_CURRENT_DEVICE {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_2__torch_cuda_current_device_output.txt"), emit: output

    script:
    """
    # Tool: python_torch_torch_cuda_current_device
    # Runs in unified Docker container
    echo 'Running STEP_2__TORCH_CUDA_CURRENT_DEVICE'
        touch step_2__torch_cuda_current_device_output.txt
    """
}

process STEP_3__TORCH_CUDA_DEVICE_COUNT {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_3__torch_cuda_device_count_output.txt"), emit: output

    script:
    """
    # Tool: python_torch_torch_cuda_device_count
    # Runs in unified Docker container
    echo 'Running STEP_3__TORCH_CUDA_DEVICE_COUNT'
        touch step_3__torch_cuda_device_count_output.txt
    """
}

process STEP_4__TORCH_CUDA_GET_DEVICE_NAME {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_4__torch_cuda_get_device_name_output.txt"), emit: output

    script:
    """
    # Tool: python_torch_torch_cuda_get_device_name
    # Runs in unified Docker container
    echo 'Running STEP_4__TORCH_CUDA_GET_DEVICE_NAME'
        touch step_4__torch_cuda_get_device_name_output.txt
    """
}

process STEP_5__TORCH_CUDA_IS_AVAILABLE {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_5__torch_cuda_is_available_output.txt"), emit: output

    script:
    """
    # Tool: python_torch_torch_cuda_is_available
    # Runs in unified Docker container
    echo 'Running STEP_5__TORCH_CUDA_IS_AVAILABLE'
        touch step_5__torch_cuda_is_available_output.txt
    """
}

workflow BIOMNI_GENOMICS_GENERATE_EMBEDDINGS_WITH_STATE {
    main:
    ch_adata_filename = Channel.value(params.adata_filename)
    ch_data_dir = Channel.value(params.data_dir)
    ch_model_folder = Channel.value(params.model_folder)

    STEP_1__SC_READ_H5AD(ch_model_folder)
    STEP_2__TORCH_CUDA_CURRENT_DEVICE(STEP_1__SC_READ_H5AD.out.output)
    STEP_3__TORCH_CUDA_DEVICE_COUNT(STEP_2__TORCH_CUDA_CURRENT_DEVICE.out.output)
    STEP_4__TORCH_CUDA_GET_DEVICE_NAME(STEP_3__TORCH_CUDA_DEVICE_COUNT.out.output)
    STEP_5__TORCH_CUDA_IS_AVAILABLE(STEP_4__TORCH_CUDA_GET_DEVICE_NAME.out.output)

    emit:
    output = STEP_5__TORCH_CUDA_IS_AVAILABLE.out.output
}

workflow {
    BIOMNI_GENOMICS_GENERATE_EMBEDDINGS_WITH_STATE()
}