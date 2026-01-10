#!/usr/bin/env nextflow
/*
 * biomni_molecular_biology_annotate_plasmid
 * Annotate a DNA sequence using pLannotate's command-line interface.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process ANNOTATE_PLASMID {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("annotate_plasmid_output.txt"), emit: output

    script:
    """
    # Tool: biomni_molecular_biology_annotate_plasmid
    # Runs in unified Docker container
    echo 'Running ANNOTATE_PLASMID'
        touch annotate_plasmid_output.txt
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

workflow BIOMNI_MOLECULAR_BIOLOGY_ANNOTATE_PLASMID {
    main:

    ANNOTATE_PLASMID()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_MOLECULAR_BIOLOGY_ANNOTATE_PLASMID()
}