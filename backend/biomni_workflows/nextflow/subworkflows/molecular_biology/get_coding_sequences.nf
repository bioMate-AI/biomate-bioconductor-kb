#!/usr/bin/env nextflow
/*
 * biomni_molecular_biology_get_coding_sequences
 * Extract coding sequences from RefSeq record.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process GET_CODING_SEQUENCES {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("get_coding_sequences_output.txt"), emit: output

    script:
    """
    # Tool: biomni_molecular_biology_get_coding_sequences
    # Runs in unified Docker container
    echo 'Running GET_CODING_SEQUENCES'
        touch get_coding_sequences_output.txt
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

workflow BIOMNI_MOLECULAR_BIOLOGY_GET_CODING_SEQUENCES {
    main:

    GET_CODING_SEQUENCES()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_MOLECULAR_BIOLOGY_GET_CODING_SEQUENCES()
}