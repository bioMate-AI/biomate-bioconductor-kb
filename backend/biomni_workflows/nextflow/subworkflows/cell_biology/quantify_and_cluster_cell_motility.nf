#!/usr/bin/env nextflow
/*
 * biomni_cell_biology_quantify_and_cluster_cell_motility
 * Quantify cell motility features from time-lapse microscopy images and cluster cells based on motility patterns.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.image_sequence_path = null

// Processes
process QUANTIFY_AND_CLUSTER_CELL_MOTILITY {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(image_sequence_path)

    output:
    path("quantify_and_cluster_cell_motility_output.txt"), emit: output

    script:
    """
    # Tool: biomni_cell_biology_quantify_and_cluster_cell_motility
    # Runs in unified Docker container
    echo 'Running QUANTIFY_AND_CLUSTER_CELL_MOTILITY'
        touch quantify_and_cluster_cell_motility_output.txt
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

workflow BIOMNI_CELL_BIOLOGY_QUANTIFY_AND_CLUSTER_CELL_MOTILITY {
    main:
    ch_image_sequence_path = Channel.fromPath(params.image_sequence_path)

    QUANTIFY_AND_CLUSTER_CELL_MOTILITY(ch_image_sequence_path)
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_CELL_BIOLOGY_QUANTIFY_AND_CLUSTER_CELL_MOTILITY()
}