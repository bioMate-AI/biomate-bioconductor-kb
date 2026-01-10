#!/usr/bin/env nextflow
/*
 * biomni_cancer_biology_norm_chr
 * 
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process NORM_CHR {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("norm_chr_output.txt"), emit: output

    script:
    """
    # Tool: biomni_cancer_biology_norm_chr
    # Runs in unified Docker container
    echo 'Running NORM_CHR'
        touch norm_chr_output.txt
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

workflow BIOMNI_CANCER_BIOLOGY_NORM_CHR {
    main:

    NORM_CHR()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_CANCER_BIOLOGY_NORM_CHR()
}