#!/usr/bin/env nextflow
/*
 * biomni_pharmacology_estimate_alpha_particle_radiotherapy_dosimetry
 * Estimate radiation absorbed doses to tumor and normal organs for alpha-particle radiotherapeutics.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.biodistribution_data = null
params.output_file = null

// Processes
process ESTIMATE_ALPHA_PARTICLE_RADIOTHERAPY_DOSIMETRY {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(biodistribution_data)
    path(output_file)

    output:
    path("estimate_alpha_particle_radiotherapy_dosimetry_output.txt"), emit: output

    script:
    """
    # Tool: biomni_pharmacology_estimate_alpha_particle_radiotherapy_dosimetry
    # Runs in unified Docker container
    echo 'Running ESTIMATE_ALPHA_PARTICLE_RADIOTHERAPY_DOSIMETRY'
        touch estimate_alpha_particle_radiotherapy_dosimetry_output.txt
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

workflow BIOMNI_PHARMACOLOGY_ESTIMATE_ALPHA_PARTICLE_RADIOTHERAPY_DOSIMETRY {
    main:
    ch_biodistribution_data = Channel.fromPath(params.biodistribution_data)
    ch_output_file = Channel.fromPath(params.output_file)

    ESTIMATE_ALPHA_PARTICLE_RADIOTHERAPY_DOSIMETRY(ch_biodistribution_data, ch_output_file)
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_PHARMACOLOGY_ESTIMATE_ALPHA_PARTICLE_RADIOTHERAPY_DOSIMETRY()
}