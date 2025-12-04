#!/usr/bin/env nextflow
/*
 * biomni_database_get_genes_near_ccre
 * Given a cCRE (Candidate cis-Regulatory Element), this function returns a string containing the
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process GET_GENES_NEAR_CCRE {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("get_genes_near_ccre_output.txt"), emit: output

    script:
    """
    # Tool: biomni_database_get_genes_near_ccre
    # Runs in unified Docker container
    echo 'Running GET_GENES_NEAR_CCRE'
        touch get_genes_near_ccre_output.txt
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

workflow BIOMNI_DATABASE_GET_GENES_NEAR_CCRE {
    main:

    GET_GENES_NEAR_CCRE()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_DATABASE_GET_GENES_NEAR_CCRE()
}