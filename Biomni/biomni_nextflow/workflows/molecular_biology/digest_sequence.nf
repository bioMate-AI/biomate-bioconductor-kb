#!/usr/bin/env nextflow
/*
 * biomni_molecular_biology_digest_sequence
 * Simulates restriction enzyme digestion of a DNA sequence and returns the resulting fragments with their properties.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.dna_sequence = null
params.enzyme_names = null

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

workflow BIOMNI_MOLECULAR_BIOLOGY_DIGEST_SEQUENCE {
    main:
    ch_dna_sequence = Channel.value(params.dna_sequence)
    ch_enzyme_names = Channel.value(params.enzyme_names)

    STEP_1__SEQ(ch_enzyme_names)

    emit:
    output = STEP_1__SEQ.out.output
}

workflow {
    BIOMNI_MOLECULAR_BIOLOGY_DIGEST_SEQUENCE()
}