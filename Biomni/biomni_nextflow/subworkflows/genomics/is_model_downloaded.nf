#!/usr/bin/env nextflow
/*
 * biomni_genomics_is_model_downloaded
 * Check if model is already downloaded by looking for key files
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.checkpoint_path = null

// Processes
process IS_MODEL_DOWNLOADED {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(checkpoint_path)

    output:
    path("is_model_downloaded_output.txt"), emit: output

    script:
    """
    # Tool: biomni_genomics_is_model_downloaded
    # Runs in unified Docker container
    echo 'Running IS_MODEL_DOWNLOADED'
        touch is_model_downloaded_output.txt
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

workflow BIOMNI_GENOMICS_IS_MODEL_DOWNLOADED {
    main:
    ch_checkpoint_path = Channel.fromPath(params.checkpoint_path)

    IS_MODEL_DOWNLOADED(ch_checkpoint_path)
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_GENOMICS_IS_MODEL_DOWNLOADED()
}