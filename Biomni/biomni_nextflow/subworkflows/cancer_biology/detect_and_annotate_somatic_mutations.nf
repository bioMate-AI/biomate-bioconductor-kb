#!/usr/bin/env nextflow
/*
 * biomni_cancer_biology_detect_and_annotate_somatic_mutations
 * Detects and annotates somatic mutations in tumor samples compared to matched normal samples.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.snpeff_database = null

// Processes
process DETECT_AND_ANNOTATE_SOMATIC_MUTATIONS {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(snpeff_database)

    output:
    path("detect_and_annotate_somatic_mutations_output.txt"), emit: output

    script:
    """
    # Tool: biomni_cancer_biology_detect_and_annotate_somatic_mutations
    # Runs in unified Docker container
    echo 'Running DETECT_AND_ANNOTATE_SOMATIC_MUTATIONS'
        touch detect_and_annotate_somatic_mutations_output.txt
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

workflow BIOMNI_CANCER_BIOLOGY_DETECT_AND_ANNOTATE_SOMATIC_MUTATIONS {
    main:
    ch_snpeff_database = Channel.fromPath(params.snpeff_database)

    DETECT_AND_ANNOTATE_SOMATIC_MUTATIONS(ch_snpeff_database)
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_CANCER_BIOLOGY_DETECT_AND_ANNOTATE_SOMATIC_MUTATIONS()
}