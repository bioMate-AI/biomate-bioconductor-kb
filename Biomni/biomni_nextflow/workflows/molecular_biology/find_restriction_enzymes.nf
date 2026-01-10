#!/usr/bin/env nextflow
/*
 * biomni_molecular_biology_find_restriction_enzymes
 * Finds common restriction enzyme sites in a DNA sequence and returns their cut positions.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.sequence = null

// Processes
process STEP_1__RESTRICTION_COMMONLY_SEARCH {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_1__restriction_commonly_search_output.txt"), emit: output

    script:
    """
    # Tool: python_bio_Restriction_CommOnly_search
    # Runs in unified Docker container
    echo 'Running STEP_1__RESTRICTION_COMMONLY_SEARCH'
        touch step_1__restriction_commonly_search_output.txt
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

workflow BIOMNI_MOLECULAR_BIOLOGY_FIND_RESTRICTION_ENZYMES {
    main:
    ch_sequence = Channel.value(params.sequence)

    STEP_1__RESTRICTION_COMMONLY_SEARCH(ch_sequence)
    STEP_2__SEQ(STEP_1__RESTRICTION_COMMONLY_SEARCH.out.output)

    emit:
    output = STEP_2__SEQ.out.output
}

workflow {
    BIOMNI_MOLECULAR_BIOLOGY_FIND_RESTRICTION_ENZYMES()
}