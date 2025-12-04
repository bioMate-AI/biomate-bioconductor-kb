#!/usr/bin/env nextflow
/*
 * biomni_synthetic_biology_create_biochemical_network_sbml_model
 * Generate a mathematical model of a biochemical network in SBML format.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.output_file = null

// Processes
process CREATE_BIOCHEMICAL_NETWORK_SBML_MODEL {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(output_file)

    output:
    path("create_biochemical_network_sbml_model_output.txt"), emit: output

    script:
    """
    # Tool: biomni_synthetic_biology_create_biochemical_network_sbml_model
    # Runs in unified Docker container
    echo 'Running CREATE_BIOCHEMICAL_NETWORK_SBML_MODEL'
        touch create_biochemical_network_sbml_model_output.txt
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

workflow BIOMNI_SYNTHETIC_BIOLOGY_CREATE_BIOCHEMICAL_NETWORK_SBML_MODEL {
    main:
    ch_output_file = Channel.fromPath(params.output_file)

    CREATE_BIOCHEMICAL_NETWORK_SBML_MODEL(ch_output_file)
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_SYNTHETIC_BIOLOGY_CREATE_BIOCHEMICAL_NETWORK_SBML_MODEL()
}