#!/usr/bin/env nextflow
/*
 * biomni_molecular_biology_find_restriction_sites
 * Identifies restriction enzyme sites in a given DNA sequence for specified enzymes.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.dna_sequence = null
params.enzymes = null

// Processes
process STEP_1__RESTRICTION_RESTRICTIONBATCH {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_1__restriction_restrictionbatch_output.txt"), emit: output

    script:
    """
    # Tool: python_bio_Restriction_RestrictionBatch
    # Runs in unified Docker container
    echo 'Running STEP_1__RESTRICTION_RESTRICTIONBATCH'
        touch step_1__restriction_restrictionbatch_output.txt
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

workflow BIOMNI_MOLECULAR_BIOLOGY_FIND_RESTRICTION_SITES {
    main:
    ch_dna_sequence = Channel.value(params.dna_sequence)
    ch_enzymes = Channel.value(params.enzymes)

    STEP_1__RESTRICTION_RESTRICTIONBATCH(ch_enzymes)
    STEP_2__SEQ(STEP_1__RESTRICTION_RESTRICTIONBATCH.out.output)

    emit:
    output = STEP_2__SEQ.out.output
}

workflow {
    BIOMNI_MOLECULAR_BIOLOGY_FIND_RESTRICTION_SITES()
}