#!/usr/bin/env nextflow
/*
 * biomni_molecular_biology_get_coding_sequences
 * 
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process STEP_1__ENTREZ_EFETCH {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("step_1__entrez_efetch_output.txt"), emit: output

    script:
    """
    # Tool: python_bio_Entrez_efetch
    # Runs in unified Docker container
    echo 'Running STEP_1__ENTREZ_EFETCH'
        touch step_1__entrez_efetch_output.txt
    """
}

process STEP_2__SEQIO_READ {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_2__seqio_read_output.txt"), emit: output

    script:
    """
    # Tool: python_bio_SeqIO_read
    # Runs in unified Docker container
    echo 'Running STEP_2__SEQIO_READ'
        touch step_2__seqio_read_output.txt
    """
}

workflow BIOMNI_MOLECULAR_BIOLOGY_GET_CODING_SEQUENCES {
    main:

    STEP_1__ENTREZ_EFETCH()
    STEP_2__SEQIO_READ(STEP_1__ENTREZ_EFETCH.out.output)

    emit:
    output = STEP_2__SEQIO_READ.out.output
}

workflow {
    BIOMNI_MOLECULAR_BIOLOGY_GET_CODING_SEQUENCES()
}