#!/usr/bin/env nextflow
/*
 * biomni_pathology_analyze_thrombus_histology
 * Analyze histological images of thrombus samples stained with H&E to identify and quantify
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.image_path = null

// Processes
process ANALYZE_THROMBUS_HISTOLOGY {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(image_path)

    output:
    path("analyze_thrombus_histology_output.txt"), emit: output

    script:
    """
    # Tool: biomni_pathology_analyze_thrombus_histology
    # Runs in unified Docker container
    echo 'Running ANALYZE_THROMBUS_HISTOLOGY'
        touch analyze_thrombus_histology_output.txt
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

workflow BIOMNI_PATHOLOGY_ANALYZE_THROMBUS_HISTOLOGY {
    main:
    ch_image_path = Channel.fromPath(params.image_path)

    ANALYZE_THROMBUS_HISTOLOGY(ch_image_path)
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_PATHOLOGY_ANALYZE_THROMBUS_HISTOLOGY()
}