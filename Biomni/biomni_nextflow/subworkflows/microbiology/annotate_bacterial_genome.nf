#!/usr/bin/env nextflow
/*
 * biomni_microbiology_annotate_bacterial_genome
 * Annotate a bacterial genome using Prokka to identify genes, proteins, and functional features.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.genome_file_path = null

// Processes
process ANNOTATE_BACTERIAL_GENOME {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(genome_file_path)

    output:
    path("annotate_bacterial_genome_output.txt"), emit: output

    script:
    """
    # Tool: biomni_microbiology_annotate_bacterial_genome
    # Runs in unified Docker container
    echo 'Running ANNOTATE_BACTERIAL_GENOME'
        touch annotate_bacterial_genome_output.txt
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

workflow BIOMNI_MICROBIOLOGY_ANNOTATE_BACTERIAL_GENOME {
    main:
    ch_genome_file_path = Channel.fromPath(params.genome_file_path)

    ANNOTATE_BACTERIAL_GENOME(ch_genome_file_path)
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_MICROBIOLOGY_ANNOTATE_BACTERIAL_GENOME()
}