#!/usr/bin/env nextflow
/*
 * biomni_molecular_biology_find_sequence_mutations
 * Compare query sequence against reference sequence to identify mutations.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process FIND_SEQUENCE_MUTATIONS {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("find_sequence_mutations_output.txt"), emit: output

    script:
    """
    # Tool: biomni_molecular_biology_find_sequence_mutations
    # Runs in unified Docker container
    echo 'Running FIND_SEQUENCE_MUTATIONS'
        touch find_sequence_mutations_output.txt
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

workflow BIOMNI_MOLECULAR_BIOLOGY_FIND_SEQUENCE_MUTATIONS {
    main:

    FIND_SEQUENCE_MUTATIONS()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_MOLECULAR_BIOLOGY_FIND_SEQUENCE_MUTATIONS()
}