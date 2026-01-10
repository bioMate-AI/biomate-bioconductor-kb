#!/usr/bin/env nextflow
/*
 * biomni_cancer_biology_analyze_copy_number_purity_ploidy_and_focal_events
 * CNVkit-based copy number workflow: CNV segmentation, purity/ploidy & HRD approximation, focal events.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process ANALYZE_COPY_NUMBER_PURITY_PLOIDY_AND_FOCAL_EVENTS {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("analyze_copy_number_purity_ploidy_and_focal_events_output.txt"), emit: output

    script:
    """
    # Tool: biomni_cancer_biology_analyze_copy_number_purity_ploidy_and_focal_events
    # Runs in unified Docker container
    echo 'Running ANALYZE_COPY_NUMBER_PURITY_PLOIDY_AND_FOCAL_EVENTS'
        touch analyze_copy_number_purity_ploidy_and_focal_events_output.txt
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

workflow BIOMNI_CANCER_BIOLOGY_ANALYZE_COPY_NUMBER_PURITY_PLOIDY_AND_FOCAL_EVENTS {
    main:

    ANALYZE_COPY_NUMBER_PURITY_PLOIDY_AND_FOCAL_EVENTS()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_CANCER_BIOLOGY_ANALYZE_COPY_NUMBER_PURITY_PLOIDY_AND_FOCAL_EVENTS()
}