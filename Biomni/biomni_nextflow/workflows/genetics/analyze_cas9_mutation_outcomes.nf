#!/usr/bin/env nextflow
/*
 * biomni_genetics_analyze_cas9_mutation_outcomes
 * Analyzes and categorizes mutations induced by Cas9 at target sites.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.reference_sequences = null
params.edited_sequences = null

// Processes
process STEP_1__PAIRWISE2_ALIGN_GLOBALMS {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_1__pairwise2_align_globalms_output.txt"), emit: output

    script:
    """
    # Tool: python_bio_pairwise2_align_globalms
    # Runs in unified Docker container
    echo 'Running STEP_1__PAIRWISE2_ALIGN_GLOBALMS'
        touch step_1__pairwise2_align_globalms_output.txt
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

workflow BIOMNI_GENETICS_ANALYZE_CAS9_MUTATION_OUTCOMES {
    main:
    ch_reference_sequences = Channel.value(params.reference_sequences)
    ch_edited_sequences = Channel.value(params.edited_sequences)

    STEP_1__PAIRWISE2_ALIGN_GLOBALMS(ch_edited_sequences)
    STEP_2__PD_DATAFRAME(STEP_1__PAIRWISE2_ALIGN_GLOBALMS.out.output)

    emit:
    output = STEP_2__PD_DATAFRAME.out.output
}

workflow {
    BIOMNI_GENETICS_ANALYZE_CAS9_MUTATION_OUTCOMES()
}