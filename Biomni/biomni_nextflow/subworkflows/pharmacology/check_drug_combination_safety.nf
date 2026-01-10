#!/usr/bin/env nextflow
/*
 * biomni_pharmacology_check_drug_combination_safety
 * 
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.data_lake_path = null

// Processes
process CHECK_DRUG_COMBINATION_SAFETY {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(data_lake_path)

    output:
    path("check_drug_combination_safety_output.txt"), emit: output

    script:
    """
    # Tool: biomni_pharmacology_check_drug_combination_safety
    # Runs in unified Docker container
    echo 'Running CHECK_DRUG_COMBINATION_SAFETY'
        touch check_drug_combination_safety_output.txt
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

workflow BIOMNI_PHARMACOLOGY_CHECK_DRUG_COMBINATION_SAFETY {
    main:
    ch_data_lake_path = Channel.fromPath(params.data_lake_path)

    CHECK_DRUG_COMBINATION_SAFETY(ch_data_lake_path)
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_PHARMACOLOGY_CHECK_DRUG_COMBINATION_SAFETY()
}