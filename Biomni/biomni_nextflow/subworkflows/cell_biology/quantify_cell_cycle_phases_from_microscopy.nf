#!/usr/bin/env nextflow
/*
 * biomni_cell_biology_quantify_cell_cycle_phases_from_microscopy
 * Quantify the percentage of cells in each cell cycle phase using Calcofluor white stained microscopy images.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.image_paths = null

// Processes
process QUANTIFY_CELL_CYCLE_PHASES_FROM_MICROSCOPY {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(image_paths)

    output:
    path("quantify_cell_cycle_phases_from_microscopy_output.txt"), emit: output

    script:
    """
    # Tool: biomni_cell_biology_quantify_cell_cycle_phases_from_microscopy
    # Runs in unified Docker container
    echo 'Running QUANTIFY_CELL_CYCLE_PHASES_FROM_MICROSCOPY'
        touch quantify_cell_cycle_phases_from_microscopy_output.txt
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

workflow BIOMNI_CELL_BIOLOGY_QUANTIFY_CELL_CYCLE_PHASES_FROM_MICROSCOPY {
    main:
    ch_image_paths = Channel.fromPath(params.image_paths)

    QUANTIFY_CELL_CYCLE_PHASES_FROM_MICROSCOPY(ch_image_paths)
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_CELL_BIOLOGY_QUANTIFY_CELL_CYCLE_PHASES_FROM_MICROSCOPY()
}