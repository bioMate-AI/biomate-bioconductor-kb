#!/usr/bin/env nextflow
/*
 * biomni_cancer_biology_detect_and_characterize_structural_variations
 * Detects and characterizes structural variations (SVs) in genomic sequencing data using LUMPY for SV detection followed by annotation with COSMIC and/or ClinVar databases.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.bam_file_path = null
params.reference_genome_path = null
params.output_dir = null

// Processes
process STEP_1__RUN {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_1__run_output.txt"), emit: output

    script:
    """
    # Tool: cli_bcftools_run
    # Runs in unified Docker container
    echo 'Running STEP_1__RUN'
        touch step_1__run_output.txt
    """
}

process STEP_2__RUN {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_2__run_output.txt"), emit: output

    script:
    """
    # Tool: cli_samtools_run
    # Runs in unified Docker container
    echo 'Running STEP_2__RUN'
        touch step_2__run_output.txt
    """
}

workflow BIOMNI_CANCER_BIOLOGY_DETECT_AND_CHARACTERIZE_STRUCTURAL_VARIATIONS {
    main:
    ch_bam_file_path = Channel.value(params.bam_file_path)
    ch_reference_genome_path = Channel.value(params.reference_genome_path)
    ch_output_dir = Channel.value(params.output_dir)

    STEP_1__RUN(ch_output_dir)
    STEP_2__RUN(STEP_1__RUN.out.output)

    emit:
    output = STEP_2__RUN.out.output
}

workflow {
    BIOMNI_CANCER_BIOLOGY_DETECT_AND_CHARACTERIZE_STRUCTURAL_VARIATIONS()
}