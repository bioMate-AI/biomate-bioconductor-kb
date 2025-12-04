#!/usr/bin/env nextflow
/*
 * biomni_database_blast_sequence
 * Identify a DNA or protein sequence using NCBI BLAST.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.sequence = null
params.database = null
params.program = null

// Processes
process STEP_1__NCBIWWW_QBLAST {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_1__ncbiwww_qblast_output.txt"), emit: output

    script:
    """
    # Tool: python_bio_NCBIWWW_qblast
    # Runs in unified Docker container
    echo 'Running STEP_1__NCBIWWW_QBLAST'
        touch step_1__ncbiwww_qblast_output.txt
    """
}

process STEP_2__NCBIXML_PARSE {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_2__ncbixml_parse_output.txt"), emit: output

    script:
    """
    # Tool: python_bio_NCBIXML_parse
    # Runs in unified Docker container
    echo 'Running STEP_2__NCBIXML_PARSE'
        touch step_2__ncbixml_parse_output.txt
    """
}

process STEP_3__SEQ {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_3__seq_output.txt"), emit: output

    script:
    """
    # Tool: python_bio_Seq
    # Runs in unified Docker container
    echo 'Running STEP_3__SEQ'
        touch step_3__seq_output.txt
    """
}

workflow BIOMNI_DATABASE_BLAST_SEQUENCE {
    main:
    ch_sequence = Channel.value(params.sequence)
    ch_database = Channel.value(params.database)
    ch_program = Channel.value(params.program)

    STEP_1__NCBIWWW_QBLAST(ch_program)
    STEP_2__NCBIXML_PARSE(STEP_1__NCBIWWW_QBLAST.out.output)
    STEP_3__SEQ(STEP_2__NCBIXML_PARSE.out.output)

    emit:
    output = STEP_3__SEQ.out.output
}

workflow {
    BIOMNI_DATABASE_BLAST_SEQUENCE()
}