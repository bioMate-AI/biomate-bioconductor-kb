#!/usr/bin/env nextflow
/*
 * biomni_genetics_analyze_crispr_genome_editing
 * Analyzes CRISPR-Cas9 genome editing results by comparing original and edited sequences.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.original_sequence = null
params.edited_sequence = null
params.guide_rna = null

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

workflow BIOMNI_GENETICS_ANALYZE_CRISPR_GENOME_EDITING {
    main:
    ch_original_sequence = Channel.value(params.original_sequence)
    ch_edited_sequence = Channel.value(params.edited_sequence)
    ch_guide_rna = Channel.value(params.guide_rna)

    STEP_1__PAIRWISE2_ALIGN_GLOBALMS(ch_guide_rna)
    STEP_2__SEQ(STEP_1__PAIRWISE2_ALIGN_GLOBALMS.out.output)

    emit:
    output = STEP_2__SEQ.out.output
}

workflow {
    BIOMNI_GENETICS_ANALYZE_CRISPR_GENOME_EDITING()
}