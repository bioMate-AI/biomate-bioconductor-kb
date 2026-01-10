#!/usr/bin/env nextflow
/*
 * biomni_molecular_biology_get_refseq_id
 * Get RefSeq ID from gene record.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process GET_REFSEQ_ID {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("get_refseq_id_output.txt"), emit: output

    script:
    """
    # Tool: biomni_molecular_biology_get_refseq_id
    # Runs in unified Docker container
    echo 'Running GET_REFSEQ_ID'
        touch get_refseq_id_output.txt
    """
}

process OUTPUT {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("output_output.txt"), emit: output

    script:
    """
    # Tool: cat1
    # Runs in unified Docker container
    echo 'Running OUTPUT'
        touch output_output.txt
    """
}

workflow BIOMNI_MOLECULAR_BIOLOGY_GET_REFSEQ_ID {
    main:

    GET_REFSEQ_ID()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_MOLECULAR_BIOLOGY_GET_REFSEQ_ID()
}