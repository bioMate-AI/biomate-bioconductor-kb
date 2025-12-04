#!/usr/bin/env nextflow
/*
 * biomni_molecular_biology_design_primer
 * Design a single primer within the given sequence window.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.sequence = null
params.start_pos = null

// Processes
process STEP_1__MT_TM_WALLACE {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_1__mt_tm_wallace_output.txt"), emit: output

    script:
    """
    # Tool: python_bio_mt_Tm_Wallace
    # Runs in unified Docker container
    echo 'Running STEP_1__MT_TM_WALLACE'
        touch step_1__mt_tm_wallace_output.txt
    """
}

workflow BIOMNI_MOLECULAR_BIOLOGY_DESIGN_PRIMER {
    main:
    ch_sequence = Channel.value(params.sequence)
    ch_start_pos = Channel.value(params.start_pos)

    STEP_1__MT_TM_WALLACE(ch_start_pos)

    emit:
    output = STEP_1__MT_TM_WALLACE.out.output
}

workflow {
    BIOMNI_MOLECULAR_BIOLOGY_DESIGN_PRIMER()
}