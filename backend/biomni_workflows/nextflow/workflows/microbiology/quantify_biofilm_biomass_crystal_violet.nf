#!/usr/bin/env nextflow
/*
 * biomni_microbiology_quantify_biofilm_biomass_crystal_violet
 * Quantifies biofilm biomass using crystal violet staining assay data and returns a detailed research log.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.od_values = null

// Processes
process STEP_1__NP_STD {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_1__np_std_output.txt"), emit: output

    script:
    """
    # Tool: python_numpy_np_std
    # Runs in unified Docker container
    echo 'Running STEP_1__NP_STD'
        touch step_1__np_std_output.txt
    """
}

process STEP_2__NP_ARRAY {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_2__np_array_output.txt"), emit: output

    script:
    """
    # Tool: python_numpy_np_array
    # Runs in unified Docker container
    echo 'Running STEP_2__NP_ARRAY'
        touch step_2__np_array_output.txt
    """
}

process STEP_3__NP_MEAN {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_3__np_mean_output.txt"), emit: output

    script:
    """
    # Tool: python_numpy_np_mean
    # Runs in unified Docker container
    echo 'Running STEP_3__NP_MEAN'
        touch step_3__np_mean_output.txt
    """
}

process STEP_4__STATS_TTEST_1SAMP {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_4__stats_ttest_1samp_output.txt"), emit: output

    script:
    """
    # Tool: python_scipy_stats_ttest_1samp
    # Runs in unified Docker container
    echo 'Running STEP_4__STATS_TTEST_1SAMP'
        touch step_4__stats_ttest_1samp_output.txt
    """
}

process STEP_5__PD_DATAFRAME {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_5__pd_dataframe_output.txt"), emit: output

    script:
    """
    # Tool: python_pandas_pd_DataFrame
    # Runs in unified Docker container
    echo 'Running STEP_5__PD_DATAFRAME'
        touch step_5__pd_dataframe_output.txt
    """
}

workflow BIOMNI_MICROBIOLOGY_QUANTIFY_BIOFILM_BIOMASS_CRYSTAL_VIOLET {
    main:
    ch_od_values = Channel.value(params.od_values)

    STEP_1__NP_STD(ch_od_values)
    STEP_2__NP_ARRAY(STEP_1__NP_STD.out.output)
    STEP_3__NP_MEAN(STEP_2__NP_ARRAY.out.output)
    STEP_4__STATS_TTEST_1SAMP(STEP_3__NP_MEAN.out.output)
    STEP_5__PD_DATAFRAME(STEP_4__STATS_TTEST_1SAMP.out.output)

    emit:
    output = STEP_5__PD_DATAFRAME.out.output
}

workflow {
    BIOMNI_MICROBIOLOGY_QUANTIFY_BIOFILM_BIOMASS_CRYSTAL_VIOLET()
}