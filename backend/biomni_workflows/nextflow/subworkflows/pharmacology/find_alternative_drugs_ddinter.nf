#!/usr/bin/env nextflow
/*
 * biomni_pharmacology_find_alternative_drugs_ddinter
 * 
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.data_lake_path = null

// Processes
process FIND_ALTERNATIVE_DRUGS_DDINTER {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(data_lake_path)

    output:
    path("find_alternative_drugs_ddinter_output.txt"), emit: output

    script:
    """
    # Tool: biomni_pharmacology_find_alternative_drugs_ddinter
    # Runs in unified Docker container
    echo 'Running FIND_ALTERNATIVE_DRUGS_DDINTER'
        touch find_alternative_drugs_ddinter_output.txt
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

workflow BIOMNI_PHARMACOLOGY_FIND_ALTERNATIVE_DRUGS_DDINTER {
    main:
    ch_data_lake_path = Channel.fromPath(params.data_lake_path)

    FIND_ALTERNATIVE_DRUGS_DDINTER(ch_data_lake_path)
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_PHARMACOLOGY_FIND_ALTERNATIVE_DRUGS_DDINTER()
}