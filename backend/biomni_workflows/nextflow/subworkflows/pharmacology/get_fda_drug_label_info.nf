#!/usr/bin/env nextflow
/*
 * biomni_pharmacology_get_fda_drug_label_info
 * 
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process GET_FDA_DRUG_LABEL_INFO {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("get_fda_drug_label_info_output.txt"), emit: output

    script:
    """
    # Tool: biomni_pharmacology_get_fda_drug_label_info
    # Runs in unified Docker container
    echo 'Running GET_FDA_DRUG_LABEL_INFO'
        touch get_fda_drug_label_info_output.txt
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

workflow BIOMNI_PHARMACOLOGY_GET_FDA_DRUG_LABEL_INFO {
    main:

    GET_FDA_DRUG_LABEL_INFO()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_PHARMACOLOGY_GET_FDA_DRUG_LABEL_INFO()
}