#!/usr/bin/env nextflow
/*
 * biomni_biochemistry_analyze_protein_conservation
 * Perform multiple sequence alignment and phylogenetic analysis to identify conserved protein regions.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process ANALYZE_PROTEIN_CONSERVATION {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("analyze_protein_conservation_output.txt"), emit: output

    script:
    """
    # Tool: biomni_biochemistry_analyze_protein_conservation
    # Runs in unified Docker container
    echo 'Running ANALYZE_PROTEIN_CONSERVATION'
        touch analyze_protein_conservation_output.txt
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

workflow BIOMNI_BIOCHEMISTRY_ANALYZE_PROTEIN_CONSERVATION {
    main:

    ANALYZE_PROTEIN_CONSERVATION()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_BIOCHEMISTRY_ANALYZE_PROTEIN_CONSERVATION()
}