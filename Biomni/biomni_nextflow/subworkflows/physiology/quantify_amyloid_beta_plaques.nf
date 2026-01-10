#!/usr/bin/env nextflow
/*
 * biomni_physiology_quantify_amyloid_beta_plaques
 * 
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.image_path = null

// Processes
process QUANTIFY_AMYLOID_BETA_PLAQUES {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(image_path)

    output:
    path("quantify_amyloid_beta_plaques_output.txt"), emit: output

    script:
    """
    # Tool: biomni_physiology_quantify_amyloid_beta_plaques
    # Runs in unified Docker container
    echo 'Running QUANTIFY_AMYLOID_BETA_PLAQUES'
        touch quantify_amyloid_beta_plaques_output.txt
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

workflow BIOMNI_PHYSIOLOGY_QUANTIFY_AMYLOID_BETA_PLAQUES {
    main:
    ch_image_path = Channel.fromPath(params.image_path)

    QUANTIFY_AMYLOID_BETA_PLAQUES(ch_image_path)
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_PHYSIOLOGY_QUANTIFY_AMYLOID_BETA_PLAQUES()
}