#!/usr/bin/env nextflow
/*
 * biomni_synthetic_biology_gene_circuit_odes
 * 
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process GENE_CIRCUIT_ODES {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("gene_circuit_odes_output.txt"), emit: output

    script:
    """
    # Tool: biomni_synthetic_biology_gene_circuit_odes
    # Runs in unified Docker container
    echo 'Running GENE_CIRCUIT_ODES'
        touch gene_circuit_odes_output.txt
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

workflow BIOMNI_SYNTHETIC_BIOLOGY_GENE_CIRCUIT_ODES {
    main:

    GENE_CIRCUIT_ODES()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_SYNTHETIC_BIOLOGY_GENE_CIRCUIT_ODES()
}