#!/usr/bin/env nextflow
/*
 * biomni_molecular_biology_reverse_complement
 * Get the reverse complement of a DNA sequence.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process REVERSE_COMPLEMENT {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("reverse_complement_output.txt"), emit: output

    script:
    """
    # Tool: biomni_molecular_biology_reverse_complement
    # Runs in unified Docker container
    echo 'Running REVERSE_COMPLEMENT'
        touch reverse_complement_output.txt
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

workflow BIOMNI_MOLECULAR_BIOLOGY_REVERSE_COMPLEMENT {
    main:

    REVERSE_COMPLEMENT()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_MOLECULAR_BIOLOGY_REVERSE_COMPLEMENT()
}