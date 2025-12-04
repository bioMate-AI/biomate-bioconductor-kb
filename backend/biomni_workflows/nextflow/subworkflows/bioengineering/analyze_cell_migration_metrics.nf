#!/usr/bin/env nextflow
/*
 * biomni_bioengineering_analyze_cell_migration_metrics
 * Analyze cell migration metrics from time-lapse microscopy images.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.image_sequence_path = null

// Processes
process ANALYZE_CELL_MIGRATION_METRICS {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(image_sequence_path)

    output:
    path("analyze_cell_migration_metrics_output.txt"), emit: output

    script:
    """
    # Tool: biomni_bioengineering_analyze_cell_migration_metrics
    # Runs in unified Docker container
    echo 'Running ANALYZE_CELL_MIGRATION_METRICS'
        touch analyze_cell_migration_metrics_output.txt
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

workflow BIOMNI_BIOENGINEERING_ANALYZE_CELL_MIGRATION_METRICS {
    main:
    ch_image_sequence_path = Channel.fromPath(params.image_sequence_path)

    ANALYZE_CELL_MIGRATION_METRICS(ch_image_sequence_path)
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_BIOENGINEERING_ANALYZE_CELL_MIGRATION_METRICS()
}