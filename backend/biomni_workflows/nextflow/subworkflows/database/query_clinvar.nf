#!/usr/bin/env nextflow
/*
 * biomni_database_query_clinvar
 * Take a natural language prompt and convert it to a structured ClinVar query.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process QUERY_CLINVAR {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("query_clinvar_output.txt"), emit: output

    script:
    """
    # Tool: biomni_database_query_clinvar
    # Runs in unified Docker container
    echo 'Running QUERY_CLINVAR'
        touch query_clinvar_output.txt
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

workflow BIOMNI_DATABASE_QUERY_CLINVAR {
    main:

    QUERY_CLINVAR()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_DATABASE_QUERY_CLINVAR()
}