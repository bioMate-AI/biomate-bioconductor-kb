#!/usr/bin/env nextflow
/*
 * biomni_immunology_analyze_ebv_antibody_titers
 * Analyze ELISA data to quantify EBV antibody titers in plasma/serum samples.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.raw_od_data = null
params.standard_curve_data = null
params.sample_metadata = null

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

process STEP_2__PD_CONCAT {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_2__pd_concat_output.txt"), emit: output

    script:
    """
    # Tool: python_pandas_pd_concat
    # Runs in unified Docker container
    echo 'Running STEP_2__PD_CONCAT'
        touch step_2__pd_concat_output.txt
    """
}

process STEP_3__NP_POLYFIT {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_3__np_polyfit_output.txt"), emit: output

    script:
    """
    # Tool: python_numpy_np_polyfit
    # Runs in unified Docker container
    echo 'Running STEP_3__NP_POLYFIT'
        touch step_3__np_polyfit_output.txt
    """
}

workflow BIOMNI_IMMUNOLOGY_ANALYZE_EBV_ANTIBODY_TITERS {
    main:
    ch_raw_od_data = Channel.value(params.raw_od_data)
    ch_standard_curve_data = Channel.value(params.standard_curve_data)
    ch_sample_metadata = Channel.value(params.sample_metadata)

    STEP_1__PD_DATAFRAME(ch_sample_metadata)
    STEP_2__PD_CONCAT(STEP_1__PD_DATAFRAME.out.output)
    STEP_3__NP_POLYFIT(STEP_2__PD_CONCAT.out.output)

    emit:
    output = STEP_3__NP_POLYFIT.out.output
}

workflow {
    BIOMNI_IMMUNOLOGY_ANALYZE_EBV_ANTIBODY_TITERS()
}