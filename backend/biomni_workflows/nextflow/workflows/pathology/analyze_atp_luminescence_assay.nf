#!/usr/bin/env nextflow
/*
 * biomni_pathology_analyze_atp_luminescence_assay
 * Analyze luminescence-based ATP assay data to determine intracellular ATP concentration.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.data_file = null
params.standard_curve_file = null

// Processes
process STEP_1__PD_READ_CSV {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_1__pd_read_csv_output.txt"), emit: output

    script:
    """
    # Tool: python_pandas_pd_read_csv
    # Runs in unified Docker container
    echo 'Running STEP_1__PD_READ_CSV'
        touch step_1__pd_read_csv_output.txt
    """
}

process STEP_2__NP_POLYFIT {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_2__np_polyfit_output.txt"), emit: output

    script:
    """
    # Tool: python_numpy_np_polyfit
    # Runs in unified Docker container
    echo 'Running STEP_2__NP_POLYFIT'
        touch step_2__np_polyfit_output.txt
    """
}

workflow BIOMNI_PATHOLOGY_ANALYZE_ATP_LUMINESCENCE_ASSAY {
    main:
    ch_data_file = Channel.value(params.data_file)
    ch_standard_curve_file = Channel.value(params.standard_curve_file)

    STEP_1__PD_READ_CSV(ch_standard_curve_file)
    STEP_2__NP_POLYFIT(STEP_1__PD_READ_CSV.out.output)

    emit:
    output = STEP_2__NP_POLYFIT.out.output
}

workflow {
    BIOMNI_PATHOLOGY_ANALYZE_ATP_LUMINESCENCE_ASSAY()
}