#!/usr/bin/env nextflow
/*
 * biomni_genetics_identify_transcription_factor_binding_sites
 * Identifies binding sites for a specific transcription factor in a genomic sequence.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.sequence = null
params.tf_name = null

// Processes
process STEP_1__MOTIFS_READ {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_1__motifs_read_output.txt"), emit: output

    script:
    """
    # Tool: python_bio_motifs_read
    # Runs in unified Docker container
    echo 'Running STEP_1__MOTIFS_READ'
        touch step_1__motifs_read_output.txt
    """
}

process STEP_2__SEQ {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_2__seq_output.txt"), emit: output

    script:
    """
    # Tool: python_bio_Seq
    # Runs in unified Docker container
    echo 'Running STEP_2__SEQ'
        touch step_2__seq_output.txt
    """
}

workflow BIOMNI_GENETICS_IDENTIFY_TRANSCRIPTION_FACTOR_BINDING_SITES {
    main:
    ch_sequence = Channel.value(params.sequence)
    ch_tf_name = Channel.value(params.tf_name)

    STEP_1__MOTIFS_READ(ch_tf_name)
    STEP_2__SEQ(STEP_1__MOTIFS_READ.out.output)

    emit:
    output = STEP_2__SEQ.out.output
}

workflow {
    BIOMNI_GENETICS_IDENTIFY_TRANSCRIPTION_FACTOR_BINDING_SITES()
}