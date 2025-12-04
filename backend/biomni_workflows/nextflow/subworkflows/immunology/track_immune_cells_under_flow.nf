#!/usr/bin/env nextflow
/*
 * biomni_immunology_track_immune_cells_under_flow
 * Track immune cells under flow conditions and classify their behaviors.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.image_sequence_path = null

// Processes
process TRACK_IMMUNE_CELLS_UNDER_FLOW {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(image_sequence_path)

    output:
    path("track_immune_cells_under_flow_output.txt"), emit: output

    script:
    """
    # Tool: biomni_immunology_track_immune_cells_under_flow
    # Runs in unified Docker container
    echo 'Running TRACK_IMMUNE_CELLS_UNDER_FLOW'
        touch track_immune_cells_under_flow_output.txt
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

workflow BIOMNI_IMMUNOLOGY_TRACK_IMMUNE_CELLS_UNDER_FLOW {
    main:
    ch_image_sequence_path = Channel.fromPath(params.image_sequence_path)

    TRACK_IMMUNE_CELLS_UNDER_FLOW(ch_image_sequence_path)
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_IMMUNOLOGY_TRACK_IMMUNE_CELLS_UNDER_FLOW()
}