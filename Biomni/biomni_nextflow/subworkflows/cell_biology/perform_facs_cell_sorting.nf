#!/usr/bin/env nextflow
/*
 * biomni_cell_biology_perform_facs_cell_sorting
 * Performs Fluorescence-Activated Cell Sorting (FACS) to enrich cell populations based on fluorescence characteristics.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.cell_suspension_data = null
params.output_file = null

// Processes
process PERFORM_FACS_CELL_SORTING {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(cell_suspension_data)
    path(output_file)

    output:
    path("perform_facs_cell_sorting_output.txt"), emit: output

    script:
    """
    # Tool: biomni_cell_biology_perform_facs_cell_sorting
    # Runs in unified Docker container
    echo 'Running PERFORM_FACS_CELL_SORTING'
        touch perform_facs_cell_sorting_output.txt
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

workflow BIOMNI_CELL_BIOLOGY_PERFORM_FACS_CELL_SORTING {
    main:
    ch_cell_suspension_data = Channel.fromPath(params.cell_suspension_data)
    ch_output_file = Channel.fromPath(params.output_file)

    PERFORM_FACS_CELL_SORTING(ch_cell_suspension_data, ch_output_file)
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_CELL_BIOLOGY_PERFORM_FACS_CELL_SORTING()
}