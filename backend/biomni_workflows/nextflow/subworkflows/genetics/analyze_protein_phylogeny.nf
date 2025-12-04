#!/usr/bin/env nextflow
/*
 * biomni_genetics_analyze_protein_phylogeny
 * Perform phylogenetic analysis on a set of protein sequences.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process ANALYZE_PROTEIN_PHYLOGENY {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("analyze_protein_phylogeny_output.txt"), emit: output

    script:
    """
    # Tool: biomni_genetics_analyze_protein_phylogeny
    # Runs in unified Docker container
    echo 'Running ANALYZE_PROTEIN_PHYLOGENY'
        touch analyze_protein_phylogeny_output.txt
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

workflow BIOMNI_GENETICS_ANALYZE_PROTEIN_PHYLOGENY {
    main:

    ANALYZE_PROTEIN_PHYLOGENY()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_GENETICS_ANALYZE_PROTEIN_PHYLOGENY()
}