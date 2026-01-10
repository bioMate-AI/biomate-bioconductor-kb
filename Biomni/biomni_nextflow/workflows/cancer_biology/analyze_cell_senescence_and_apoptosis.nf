#!/usr/bin/env nextflow
/*
 * biomni_cancer_biology_analyze_cell_senescence_and_apoptosis
 * Analyze flow cytometry data to quantify senescent and apoptotic cell populations.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.fcs_file_path = null

// Processes
process STEP_1__NP_PERCENTILE {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_1__np_percentile_output.txt"), emit: output

    script:
    """
    # Tool: python_numpy_np_percentile
    # Runs in unified Docker container
    echo 'Running STEP_1__NP_PERCENTILE'
        touch step_1__np_percentile_output.txt
    """
}

workflow BIOMNI_CANCER_BIOLOGY_ANALYZE_CELL_SENESCENCE_AND_APOPTOSIS {
    main:
    ch_fcs_file_path = Channel.value(params.fcs_file_path)

    STEP_1__NP_PERCENTILE(ch_fcs_file_path)

    emit:
    output = STEP_1__NP_PERCENTILE.out.output
}

workflow {
    BIOMNI_CANCER_BIOLOGY_ANALYZE_CELL_SENESCENCE_AND_APOPTOSIS()
}