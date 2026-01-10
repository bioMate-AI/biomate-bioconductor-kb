#!/usr/bin/env nextflow
/*
 * biomni_microbiology_quantify_biofilm_biomass_crystal_violet
 * Quantifies biofilm biomass using crystal violet staining assay data.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.save_path = null

// Processes
process QUANTIFY_BIOFILM_BIOMASS_CRYSTAL_VIOLET {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(save_path)

    output:
    path("quantify_biofilm_biomass_crystal_violet_output.txt"), emit: output

    script:
    """
    # Tool: biomni_microbiology_quantify_biofilm_biomass_crystal_violet
    # Runs in unified Docker container
    echo 'Running QUANTIFY_BIOFILM_BIOMASS_CRYSTAL_VIOLET'
        touch quantify_biofilm_biomass_crystal_violet_output.txt
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

workflow BIOMNI_MICROBIOLOGY_QUANTIFY_BIOFILM_BIOMASS_CRYSTAL_VIOLET {
    main:
    ch_save_path = Channel.fromPath(params.save_path)

    QUANTIFY_BIOFILM_BIOMASS_CRYSTAL_VIOLET(ch_save_path)
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_MICROBIOLOGY_QUANTIFY_BIOFILM_BIOMASS_CRYSTAL_VIOLET()
}