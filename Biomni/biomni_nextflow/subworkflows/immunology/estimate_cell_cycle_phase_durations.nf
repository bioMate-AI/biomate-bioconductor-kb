#!/usr/bin/env nextflow
/*
 * biomni_immunology_estimate_cell_cycle_phase_durations
 * 
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.flow_cytometry_data = null

// Processes
process ESTIMATE_CELL_CYCLE_PHASE_DURATIONS {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(flow_cytometry_data)

    output:
    path("estimate_cell_cycle_phase_durations_output.txt"), emit: output

    script:
    """
    # Tool: biomni_immunology_estimate_cell_cycle_phase_durations
    # Runs in unified Docker container
    echo 'Running ESTIMATE_CELL_CYCLE_PHASE_DURATIONS'
        touch estimate_cell_cycle_phase_durations_output.txt
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

workflow BIOMNI_IMMUNOLOGY_ESTIMATE_CELL_CYCLE_PHASE_DURATIONS {
    main:
    ch_flow_cytometry_data = Channel.fromPath(params.flow_cytometry_data)

    ESTIMATE_CELL_CYCLE_PHASE_DURATIONS(ch_flow_cytometry_data)
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_IMMUNOLOGY_ESTIMATE_CELL_CYCLE_PHASE_DURATIONS()
}