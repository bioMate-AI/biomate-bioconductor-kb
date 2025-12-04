#!/usr/bin/env nextflow
/*
 * biomni_immunology_isolate_purify_immune_cells
 * Simulates the isolation and purification of immune cells from tissue samples.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process ISOLATE_PURIFY_IMMUNE_CELLS {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("isolate_purify_immune_cells_output.txt"), emit: output

    script:
    """
    # Tool: biomni_immunology_isolate_purify_immune_cells
    # Runs in unified Docker container
    echo 'Running ISOLATE_PURIFY_IMMUNE_CELLS'
        touch isolate_purify_immune_cells_output.txt
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

workflow BIOMNI_IMMUNOLOGY_ISOLATE_PURIFY_IMMUNE_CELLS {
    main:

    ISOLATE_PURIFY_IMMUNE_CELLS()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_IMMUNOLOGY_ISOLATE_PURIFY_IMMUNE_CELLS()
}