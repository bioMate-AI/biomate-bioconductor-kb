#!/usr/bin/env nextflow
/*
 * biomni_pharmacology_perform_mwas_cyp2c19_metabolizer_status
 * Perform a Methylome-wide Association Study (MWAS) to identify CpG sites significantly associated with CYP2C19 metabolizer status.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.methylation_data_path = null
params.metabolizer_status_path = null
params.covariates_path = null
params.output_file = null

// Processes
process PERFORM_MWAS_CYP2C19_METABOLIZER_STATUS {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(methylation_data_path)
    path(metabolizer_status_path)
    path(covariates_path)
    path(output_file)

    output:
    path("perform_mwas_cyp2c19_metabolizer_status_output.txt"), emit: output

    script:
    """
    # Tool: biomni_pharmacology_perform_mwas_cyp2c19_metabolizer_status
    # Runs in unified Docker container
    echo 'Running PERFORM_MWAS_CYP2C19_METABOLIZER_STATUS'
        touch perform_mwas_cyp2c19_metabolizer_status_output.txt
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

workflow BIOMNI_PHARMACOLOGY_PERFORM_MWAS_CYP2C19_METABOLIZER_STATUS {
    main:
    ch_methylation_data_path = Channel.fromPath(params.methylation_data_path)
    ch_metabolizer_status_path = Channel.fromPath(params.metabolizer_status_path)
    ch_covariates_path = Channel.fromPath(params.covariates_path)
    ch_output_file = Channel.fromPath(params.output_file)

    PERFORM_MWAS_CYP2C19_METABOLIZER_STATUS(ch_methylation_data_path, ch_metabolizer_status_path, ch_covariates_path, ch_output_file)
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_PHARMACOLOGY_PERFORM_MWAS_CYP2C19_METABOLIZER_STATUS()
}