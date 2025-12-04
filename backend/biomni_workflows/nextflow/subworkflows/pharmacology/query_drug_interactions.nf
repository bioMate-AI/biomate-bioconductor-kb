#!/usr/bin/env nextflow
/*
 * biomni_pharmacology_query_drug_interactions
 * 
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.data_lake_path = null

// Processes
process QUERY_DRUG_INTERACTIONS {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(data_lake_path)

    output:
    path("query_drug_interactions_output.txt"), emit: output

    script:
    """
    # Tool: biomni_pharmacology_query_drug_interactions
    # Runs in unified Docker container
    echo 'Running QUERY_DRUG_INTERACTIONS'
        touch query_drug_interactions_output.txt
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

workflow BIOMNI_PHARMACOLOGY_QUERY_DRUG_INTERACTIONS {
    main:
    ch_data_lake_path = Channel.fromPath(params.data_lake_path)

    QUERY_DRUG_INTERACTIONS(ch_data_lake_path)
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_PHARMACOLOGY_QUERY_DRUG_INTERACTIONS()
}