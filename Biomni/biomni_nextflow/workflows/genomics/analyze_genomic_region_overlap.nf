#!/usr/bin/env nextflow
/*
 * biomni_genomics_analyze_genomic_region_overlap
 * Analyze overlaps between two or more sets of genomic regions.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.region_sets = null

// Processes
process STEP_1__STATS_APPEND {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_1__stats_append_output.txt"), emit: output

    script:
    """
    # Tool: python_scipy_stats_append
    # Runs in unified Docker container
    echo 'Running STEP_1__STATS_APPEND'
        touch step_1__stats_append_output.txt
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

workflow BIOMNI_GENOMICS_ANALYZE_GENOMIC_REGION_OVERLAP {
    main:
    ch_region_sets = Channel.value(params.region_sets)

    STEP_1__STATS_APPEND(ch_region_sets)
    STEP_2__PD_DATAFRAME(STEP_1__STATS_APPEND.out.output)

    emit:
    output = STEP_2__PD_DATAFRAME.out.output
}

workflow {
    BIOMNI_GENOMICS_ANALYZE_GENOMIC_REGION_OVERLAP()
}