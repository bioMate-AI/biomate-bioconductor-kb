#!/usr/bin/env nextflow
/*
 * biomni_biochemistry_analyze_rna_secondary_structure_features
 * Calculate numeric values for various structural features of an RNA secondary structure.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process ANALYZE_RNA_SECONDARY_STRUCTURE_FEATURES {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("analyze_rna_secondary_structure_features_output.txt"), emit: output

    script:
    """
    # Tool: biomni_biochemistry_analyze_rna_secondary_structure_features
    # Runs in unified Docker container
    echo 'Running ANALYZE_RNA_SECONDARY_STRUCTURE_FEATURES'
        touch analyze_rna_secondary_structure_features_output.txt
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

workflow BIOMNI_BIOCHEMISTRY_ANALYZE_RNA_SECONDARY_STRUCTURE_FEATURES {
    main:

    ANALYZE_RNA_SECONDARY_STRUCTURE_FEATURES()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_BIOCHEMISTRY_ANALYZE_RNA_SECONDARY_STRUCTURE_FEATURES()
}