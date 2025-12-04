#!/usr/bin/env nextflow
/*
 * biomni_genomics_interspecies_gene_conversion
 * Convert ENSEMBL gene IDs between different species using BioMart homology mapping. This function converts a list of ENSEMBL gene IDs from one species to their homologous counterparts in another species using the Ensembl BioMart database. The conversion is based on one-to-one ortholog mappings between species.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.gene_list = null
params.source_species = null
params.target_species = null

// Processes
process STEP_1__PD_DATAFRAME {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_1__pd_dataframe_output.txt"), emit: output

    script:
    """
    # Tool: python_pandas_pd_DataFrame
    # Runs in unified Docker container
    echo 'Running STEP_1__PD_DATAFRAME'
        touch step_1__pd_dataframe_output.txt
    """
}

workflow BIOMNI_GENOMICS_INTERSPECIES_GENE_CONVERSION {
    main:
    ch_gene_list = Channel.value(params.gene_list)
    ch_source_species = Channel.value(params.source_species)
    ch_target_species = Channel.value(params.target_species)

    STEP_1__PD_DATAFRAME(ch_target_species)

    emit:
    output = STEP_1__PD_DATAFRAME.out.output
}

workflow {
    BIOMNI_GENOMICS_INTERSPECIES_GENE_CONVERSION()
}