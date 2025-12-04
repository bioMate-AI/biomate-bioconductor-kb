#!/usr/bin/env nextflow
/*
 * biomni_molecular_biology_pcr_simple
 * Simulate PCR amplification with given primers and sequence.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.sequence = null
params.forward_primer = null
params.reverse_primer = null

// Processes
process STEP_1__SEQ {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_1__seq_output.txt"), emit: output

    script:
    """
    # Tool: python_bio_Seq
    # Runs in unified Docker container
    echo 'Running STEP_1__SEQ'
        touch step_1__seq_output.txt
    """
}

workflow BIOMNI_MOLECULAR_BIOLOGY_PCR_SIMPLE {
    main:
    ch_sequence = Channel.value(params.sequence)
    ch_forward_primer = Channel.value(params.forward_primer)
    ch_reverse_primer = Channel.value(params.reverse_primer)

    STEP_1__SEQ(ch_reverse_primer)

    emit:
    output = STEP_1__SEQ.out.output
}

workflow {
    BIOMNI_MOLECULAR_BIOLOGY_PCR_SIMPLE()
}