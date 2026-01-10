#!/usr/bin/env nextflow
/*
 * biomni_systems_biology_perform_flux_balance_analysis
 * 
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.model_file = null
params.output_file = null

// Processes
process PERFORM_FLUX_BALANCE_ANALYSIS {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(model_file)
    path(output_file)

    output:
    path("perform_flux_balance_analysis_output.txt"), emit: output

    script:
    """
    # Tool: biomni_systems_biology_perform_flux_balance_analysis
    # Runs in unified Docker container
    echo 'Running PERFORM_FLUX_BALANCE_ANALYSIS'
        touch perform_flux_balance_analysis_output.txt
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

workflow BIOMNI_SYSTEMS_BIOLOGY_PERFORM_FLUX_BALANCE_ANALYSIS {
    main:
    ch_model_file = Channel.fromPath(params.model_file)
    ch_output_file = Channel.fromPath(params.output_file)

    PERFORM_FLUX_BALANCE_ANALYSIS(ch_model_file, ch_output_file)
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_SYSTEMS_BIOLOGY_PERFORM_FLUX_BALANCE_ANALYSIS()
}