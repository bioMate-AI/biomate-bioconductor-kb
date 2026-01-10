#!/usr/bin/env nextflow
/*
 * biomni_immunology_analyze_bacterial_growth_curve
 * Analyzes bacterial growth curve data to determine growth parameters such as doubling time, growth rate, and lag phase.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.time_points = null
params.od_values = null
params.strain_name = null

// Processes
process STEP_1__NP_ARRAY {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_1__np_array_output.txt"), emit: output

    script:
    """
    # Tool: python_numpy_np_array
    # Runs in unified Docker container
    echo 'Running STEP_1__NP_ARRAY'
        touch step_1__np_array_output.txt
    """
}

process STEP_2__PD_DATAFRAME {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_2__pd_dataframe_output.txt"), emit: output

    script:
    """
    # Tool: python_pandas_pd_DataFrame
    # Runs in unified Docker container
    echo 'Running STEP_2__PD_DATAFRAME'
        touch step_2__pd_dataframe_output.txt
    """
}

workflow BIOMNI_IMMUNOLOGY_ANALYZE_BACTERIAL_GROWTH_CURVE {
    main:
    ch_time_points = Channel.value(params.time_points)
    ch_od_values = Channel.value(params.od_values)
    ch_strain_name = Channel.value(params.strain_name)

    STEP_1__NP_ARRAY(ch_strain_name)
    STEP_2__PD_DATAFRAME(STEP_1__NP_ARRAY.out.output)

    emit:
    output = STEP_2__PD_DATAFRAME.out.output
}

workflow {
    BIOMNI_IMMUNOLOGY_ANALYZE_BACTERIAL_GROWTH_CURVE()
}