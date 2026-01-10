#!/usr/bin/env nextflow
/*
 * biomni_cell_biology_analyze_mitochondrial_morphology_and_potential
 * Quantifies metrics of mitochondrial morphology and membrane potential from fluorescence microscopy images.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.morphology_image_path = null
params.potential_image_path = null

// Processes
process ANALYZE_MITOCHONDRIAL_MORPHOLOGY_AND_POTENTIAL {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(morphology_image_path)
    path(potential_image_path)

    output:
    path("analyze_mitochondrial_morphology_and_potential_output.txt"), emit: output

    script:
    """
    # Tool: biomni_cell_biology_analyze_mitochondrial_morphology_and_potential
    # Runs in unified Docker container
    echo 'Running ANALYZE_MITOCHONDRIAL_MORPHOLOGY_AND_POTENTIAL'
        touch analyze_mitochondrial_morphology_and_potential_output.txt
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

workflow BIOMNI_CELL_BIOLOGY_ANALYZE_MITOCHONDRIAL_MORPHOLOGY_AND_POTENTIAL {
    main:
    ch_morphology_image_path = Channel.fromPath(params.morphology_image_path)
    ch_potential_image_path = Channel.fromPath(params.potential_image_path)

    ANALYZE_MITOCHONDRIAL_MORPHOLOGY_AND_POTENTIAL(ch_morphology_image_path, ch_potential_image_path)
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_CELL_BIOLOGY_ANALYZE_MITOCHONDRIAL_MORPHOLOGY_AND_POTENTIAL()
}