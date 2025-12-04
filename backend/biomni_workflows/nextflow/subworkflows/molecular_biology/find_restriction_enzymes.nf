#!/usr/bin/env nextflow
/*
 * biomni_molecular_biology_find_restriction_enzymes
 * Finds common restriction enzyme sites in a DNA sequence.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process FIND_RESTRICTION_ENZYMES {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("find_restriction_enzymes_output.txt"), emit: output

    script:
    """
    # Tool: biomni_molecular_biology_find_restriction_enzymes
    # Runs in unified Docker container
    echo 'Running FIND_RESTRICTION_ENZYMES'
        touch find_restriction_enzymes_output.txt
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

workflow BIOMNI_MOLECULAR_BIOLOGY_FIND_RESTRICTION_ENZYMES {
    main:

    FIND_RESTRICTION_ENZYMES()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_MOLECULAR_BIOLOGY_FIND_RESTRICTION_ENZYMES()
}