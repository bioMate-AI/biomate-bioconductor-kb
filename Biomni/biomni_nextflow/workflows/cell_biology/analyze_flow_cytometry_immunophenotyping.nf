#!/usr/bin/env nextflow
/*
 * biomni_cell_biology_analyze_flow_cytometry_immunophenotyping
 * Analyze flow cytometry data to identify and quantify specific cell populations based on surface markers.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.fcs_file_path = null
params.gating_strategy = null

// Processes
process STEP_1__PD_DATAFRAME {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_1__pd_dataframe_output.txt"), emit: output

    script:
    """
    # Tool: python_pandas_pd_DataFrame
    # Runs in unified Docker container
    echo 'Running STEP_1__PD_DATAFRAME'
        touch step_1__pd_dataframe_output.txt
    """
}

workflow BIOMNI_CELL_BIOLOGY_ANALYZE_FLOW_CYTOMETRY_IMMUNOPHENOTYPING {
    main:
    ch_fcs_file_path = Channel.value(params.fcs_file_path)
    ch_gating_strategy = Channel.value(params.gating_strategy)

    STEP_1__PD_DATAFRAME(ch_gating_strategy)

    emit:
    output = STEP_1__PD_DATAFRAME.out.output
}

workflow {
    BIOMNI_CELL_BIOLOGY_ANALYZE_FLOW_CYTOMETRY_IMMUNOPHENOTYPING()
}