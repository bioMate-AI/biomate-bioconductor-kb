#!/usr/bin/env nextflow
/*
 * biomni_biophysics_analyze_tissue_deformation_flow
 * Quantify tissue deformation and flow dynamics from microscopy image sequence.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process ANALYZE_TISSUE_DEFORMATION_FLOW {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("analyze_tissue_deformation_flow_output.txt"), emit: output

    script:
    """
    # Tool: biomni_biophysics_analyze_tissue_deformation_flow
    # Runs in unified Docker container
    echo 'Running ANALYZE_TISSUE_DEFORMATION_FLOW'
        touch analyze_tissue_deformation_flow_output.txt
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

workflow BIOMNI_BIOPHYSICS_ANALYZE_TISSUE_DEFORMATION_FLOW {
    main:

    ANALYZE_TISSUE_DEFORMATION_FLOW()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_BIOPHYSICS_ANALYZE_TISSUE_DEFORMATION_FLOW()
}