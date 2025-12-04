#!/usr/bin/env nextflow
/*
 * biomni_microbiology_vfa_production_model
 * 
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process VFA_PRODUCTION_MODEL {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("vfa_production_model_output.txt"), emit: output

    script:
    """
    # Tool: biomni_microbiology_vfa_production_model
    # Runs in unified Docker container
    echo 'Running VFA_PRODUCTION_MODEL'
        touch vfa_production_model_output.txt
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

workflow BIOMNI_MICROBIOLOGY_VFA_PRODUCTION_MODEL {
    main:

    VFA_PRODUCTION_MODEL()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_MICROBIOLOGY_VFA_PRODUCTION_MODEL()
}