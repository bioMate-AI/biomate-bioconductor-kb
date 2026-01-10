#!/usr/bin/env nextflow
/*
 * biomni_genomics_analyze_comparative_genomics_and_haplotypes
 * Perform comparative genomics and haplotype analysis on multiple genome samples.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.sample_fasta_files = null
params.reference_genome_path = null

// Processes
process ANALYZE_COMPARATIVE_GENOMICS_AND_HAPLOTYPES {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(sample_fasta_files)
    path(reference_genome_path)

    output:
    path("analyze_comparative_genomics_and_haplotypes_output.txt"), emit: output

    script:
    """
    # Tool: biomni_genomics_analyze_comparative_genomics_and_haplotypes
    # Runs in unified Docker container
    echo 'Running ANALYZE_COMPARATIVE_GENOMICS_AND_HAPLOTYPES'
        touch analyze_comparative_genomics_and_haplotypes_output.txt
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

workflow BIOMNI_GENOMICS_ANALYZE_COMPARATIVE_GENOMICS_AND_HAPLOTYPES {
    main:
    ch_sample_fasta_files = Channel.fromPath(params.sample_fasta_files)
    ch_reference_genome_path = Channel.fromPath(params.reference_genome_path)

    ANALYZE_COMPARATIVE_GENOMICS_AND_HAPLOTYPES(ch_sample_fasta_files, ch_reference_genome_path)
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_GENOMICS_ANALYZE_COMPARATIVE_GENOMICS_AND_HAPLOTYPES()
}