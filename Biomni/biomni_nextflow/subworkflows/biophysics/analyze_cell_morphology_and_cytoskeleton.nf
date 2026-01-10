#!/usr/bin/env nextflow
/*
 * biomni_biophysics_analyze_cell_morphology_and_cytoskeleton
 * Quantifies cell morphology and cytoskeletal organization from fluorescence microscopy images.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.image_path = null

// Processes
process ANALYZE_CELL_MORPHOLOGY_AND_CYTOSKELETON {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(image_path)

    output:
    path("analyze_cell_morphology_and_cytoskeleton_output.txt"), emit: output

    script:
    """
    # Tool: biomni_biophysics_analyze_cell_morphology_and_cytoskeleton
    # Runs in unified Docker container
    echo 'Running ANALYZE_CELL_MORPHOLOGY_AND_CYTOSKELETON'
        touch analyze_cell_morphology_and_cytoskeleton_output.txt
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

workflow BIOMNI_BIOPHYSICS_ANALYZE_CELL_MORPHOLOGY_AND_CYTOSKELETON {
    main:
    ch_image_path = Channel.fromPath(params.image_path)

    ANALYZE_CELL_MORPHOLOGY_AND_CYTOSKELETON(ch_image_path)
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_BIOPHYSICS_ANALYZE_CELL_MORPHOLOGY_AND_CYTOSKELETON()
}