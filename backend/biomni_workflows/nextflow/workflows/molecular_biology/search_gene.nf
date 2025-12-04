#!/usr/bin/env nextflow
/*
 * biomni_molecular_biology_search_gene
 * 
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process STEP_1__ENTREZ_READ {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("step_1__entrez_read_output.txt"), emit: output

    script:
    """
    # Tool: python_bio_Entrez_read
    # Runs in unified Docker container
    echo 'Running STEP_1__ENTREZ_READ'
        touch step_1__entrez_read_output.txt
    """
}

process STEP_2__ENTREZ_ESEARCH {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_2__entrez_esearch_output.txt"), emit: output

    script:
    """
    # Tool: python_bio_Entrez_esearch
    # Runs in unified Docker container
    echo 'Running STEP_2__ENTREZ_ESEARCH'
        touch step_2__entrez_esearch_output.txt
    """
}

workflow BIOMNI_MOLECULAR_BIOLOGY_SEARCH_GENE {
    main:

    STEP_1__ENTREZ_READ()
    STEP_2__ENTREZ_ESEARCH(STEP_1__ENTREZ_READ.out.output)

    emit:
    output = STEP_2__ENTREZ_ESEARCH.out.output
}

workflow {
    BIOMNI_MOLECULAR_BIOLOGY_SEARCH_GENE()
}