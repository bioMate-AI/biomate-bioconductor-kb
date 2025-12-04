#!/usr/bin/env nextflow
/*
 * biomni_microbiology_glv_equations
 * 
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process GLV_EQUATIONS {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("glv_equations_output.txt"), emit: output

    script:
    """
    # Tool: biomni_microbiology_glv_equations
    # Runs in unified Docker container
    echo 'Running GLV_EQUATIONS'
        touch glv_equations_output.txt
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

workflow BIOMNI_MICROBIOLOGY_GLV_EQUATIONS {
    main:

    GLV_EQUATIONS()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_MICROBIOLOGY_GLV_EQUATIONS()
}