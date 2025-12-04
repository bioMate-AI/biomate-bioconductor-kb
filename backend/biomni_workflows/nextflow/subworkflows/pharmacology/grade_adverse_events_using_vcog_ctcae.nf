#!/usr/bin/env nextflow
/*
 * biomni_pharmacology_grade_adverse_events_using_vcog_ctcae
 * Grade and monitor adverse events in animal studies using the VCOG-CTCAE standard.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.clinical_data_file = null

// Processes
process GRADE_ADVERSE_EVENTS_USING_VCOG_CTCAE {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(clinical_data_file)

    output:
    path("grade_adverse_events_using_vcog_ctcae_output.txt"), emit: output

    script:
    """
    # Tool: biomni_pharmacology_grade_adverse_events_using_vcog_ctcae
    # Runs in unified Docker container
    echo 'Running GRADE_ADVERSE_EVENTS_USING_VCOG_CTCAE'
        touch grade_adverse_events_using_vcog_ctcae_output.txt
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

workflow BIOMNI_PHARMACOLOGY_GRADE_ADVERSE_EVENTS_USING_VCOG_CTCAE {
    main:
    ch_clinical_data_file = Channel.fromPath(params.clinical_data_file)

    GRADE_ADVERSE_EVENTS_USING_VCOG_CTCAE(ch_clinical_data_file)
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_PHARMACOLOGY_GRADE_ADVERSE_EVENTS_USING_VCOG_CTCAE()
}