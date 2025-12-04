#!/usr/bin/env nextflow
/*
 * biomni_pharmacology_bi_exp_model
 * 
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process BI_EXP_MODEL {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("bi_exp_model_output.txt"), emit: output

    script:
    """
    # Tool: biomni_pharmacology_bi_exp_model
    # Runs in unified Docker container
    echo 'Running BI_EXP_MODEL'
        touch bi_exp_model_output.txt
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

workflow BIOMNI_PHARMACOLOGY_BI_EXP_MODEL {
    main:

    BI_EXP_MODEL()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_PHARMACOLOGY_BI_EXP_MODEL()
}